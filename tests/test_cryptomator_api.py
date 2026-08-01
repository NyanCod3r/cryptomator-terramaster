import importlib.util
import json
import signal
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


MODULE_PATH = (
    Path(__file__).resolve().parents[1] / "tpk" / "sbin" / "cryptomator-api"
)
sys.dont_write_bytecode = True
MODULE_LOADER = SourceFileLoader("cryptomator_api", str(MODULE_PATH))
MODULE_SPEC = importlib.util.spec_from_loader(MODULE_LOADER.name, MODULE_LOADER)
if MODULE_SPEC is None:
    raise RuntimeError("Unable to load cryptomator-api")
cryptomator_api = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_LOADER.exec_module(cryptomator_api)


class CryptomatorApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.config_dir = self.root / "state"
        self.vaults_file = self.config_dir / "vaults.json"
        self.legacy_vaults_file = self.root / "legacy" / "vaults.json"
        self.mount_base = self.root / "mounts"
        self.cli_bin = self.root / "cryptomator-cli"
        self.cli_bin.touch()

        self.patchers = [
            mock.patch.object(cryptomator_api, "CONFIG_DIR", self.config_dir),
            mock.patch.object(cryptomator_api, "VAULTS_FILE", self.vaults_file),
            mock.patch.object(
                cryptomator_api,
                "LEGACY_VAULTS_FILE",
                self.legacy_vaults_file,
            ),
            mock.patch.object(cryptomator_api, "MOUNT_BASE", self.mount_base),
            mock.patch.object(cryptomator_api, "CLI_BIN", self.cli_bin),
        ]
        for patcher in self.patchers:
            patcher.start()
        cryptomator_api.vault_procs.clear()

    def tearDown(self) -> None:
        cryptomator_api.vault_procs.clear()
        for patcher in reversed(self.patchers):
            patcher.stop()
        self.temp_dir.cleanup()

    def write_vaults(self, path: Path, vaults: list[dict[str, object]]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(vaults), encoding="utf-8")

    def request(
        self,
        method: str,
        route: str,
        body: dict[str, str] | None = None,
    ) -> tuple[dict[str, object], int]:
        response: dict[str, object] = {}
        status_code = 200
        handler = object.__new__(cryptomator_api.Handler)
        handler._body = lambda: body or {}

        def reply(data: bytes, status: int = 200) -> None:
            nonlocal response, status_code
            response = json.loads(data.decode("utf-8"))
            status_code = status

        handler._reply = reply
        handler._handle(method, route)
        return response, status_code

    def test_load_migrates_legacy_numeric_id(self) -> None:
        self.write_vaults(
            self.legacy_vaults_file,
            [{"id": 123, "name": "Legacy", "path": "/vault"}],
        )

        vaults = cryptomator_api.load_vaults()

        self.assertEqual("123", vaults[0]["id"])
        self.assertTrue(self.vaults_file.is_file())
        self.assertEqual("123", json.loads(self.vaults_file.read_text())[0]["id"])

    def test_import_existing_vault(self) -> None:
        vault_path = self.root / "O'Brien Vault"
        vault_path.mkdir()
        (vault_path / "vault.cryptomator").write_text("{}", encoding="utf-8")

        response, status = self.request(
            "POST",
            "vaults",
            {"path": str(vault_path), "name": "O'Brien Vault"},
        )

        self.assertEqual(200, status)
        self.assertTrue(response["code"])
        saved_vault = json.loads(self.vaults_file.read_text(encoding="utf-8"))[0]
        self.assertIsInstance(saved_vault["id"], str)
        self.assertEqual(str(vault_path.resolve()), saved_vault["path"])

    def test_unlock_finds_legacy_numeric_id(self) -> None:
        self.write_vaults(
            self.vaults_file,
            [
                {
                    "id": 123,
                    "name": "Legacy",
                    "path": "/vault",
                    "mount_point": str(self.mount_base / "123"),
                }
            ],
        )
        process = mock.Mock()
        process.poll.return_value = None

        with mock.patch.object(
            cryptomator_api.subprocess,
            "Popen",
            return_value=process,
        ) as popen, mock.patch.object(cryptomator_api.time, "sleep"):
            response, status = self.request(
                "POST",
                "vaults/123/unlock",
                {"password": "secret"},
            )

        self.assertEqual(200, status)
        self.assertTrue(response["code"])
        self.assertIn("123", cryptomator_api.vault_procs)
        process.stdin.write.assert_called_once_with(b"secret\n")
        command = popen.call_args.args[0]
        self.assertEqual(str(self.cli_bin), command[0])
        self.assertEqual("/vault", command[-1])

    def test_lock_uses_sigint_for_graceful_unmount(self) -> None:
        process = mock.Mock()
        process.poll.return_value = None
        cryptomator_api.vault_procs["123"] = process

        response, status = self.request("POST", "vaults/123/lock")

        self.assertEqual(200, status)
        self.assertTrue(response["code"])
        process.send_signal.assert_called_once_with(signal.SIGINT)
        self.assertNotIn("123", cryptomator_api.vault_procs)

    def test_delete_removes_legacy_numeric_id(self) -> None:
        self.write_vaults(
            self.vaults_file,
            [{"id": 123, "name": "Legacy", "path": "/vault"}],
        )

        response, status = self.request("DELETE", "vaults/123")

        self.assertEqual(200, status)
        self.assertTrue(response["code"])
        self.assertEqual([], json.loads(self.vaults_file.read_text(encoding="utf-8")))

    def test_unlock_route_must_match_exactly(self) -> None:
        response, status = self.request(
            "POST",
            "vaults/123/unlock/extra",
            {"password": "secret"},
        )

        self.assertEqual(404, status)
        self.assertFalse(response["code"])


if __name__ == "__main__":
    unittest.main()
