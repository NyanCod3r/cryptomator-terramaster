# Cryptomator for TerraMaster TOS

This repository packages [Cryptomator CLI](https://github.com/cryptomator/cli) as a headless `.tpk` application for TerraMaster NAS devices running TOS 6.

The upstream JavaFX desktop interface cannot run on a headless NAS. This port uses a small browser interface and a Python service to manage one Cryptomator CLI process per unlocked vault.

## How it works

1. TOS loads `webui.bz2` in an iframe.
2. The WebUI sends requests through `/v2/proxy/cryptomator`.
3. `cryptomator-api` receives those requests on `/var/api/cryptomator.sock`.
4. The service starts Cryptomator CLI with the Linux FUSE mount provider.
5. Unlocked files appear under `/mnt/cryptomator/<vault-id>`.

The package supports existing password-protected Cryptomator vaults. Vault creation and Hub vaults are not provided by the current WebUI.

Vault registrations are stored in `/var/lib/cryptomator/vaults.json`. Package upgrades do not replace this file. Passwords are sent to the CLI process through standard input and are not stored.

## Packages

Each upstream Cryptomator release produces two files:

| Package | Architecture | TOS version |
|---------|--------------|-------------|
| `Cryptomator TOS7_TOS6 <version>.<revision> x86_64.tpk` | x86_64 | TOS 6 and TOS 7 |
| `Cryptomator TOS6 <version>.<revision> aarch64.tpk` | aarch64 | TOS 6 |

The package version follows the desktop release for discoverability. The vault engine is the latest published Cryptomator CLI release.

## Installation

1. Download the `.tpk` for the NAS CPU architecture from [Releases](../../releases).
2. Open the TOS web interface.
3. Go to **App Management** > **Install from TPK**.
4. Select the downloaded file.
5. Open Cryptomator from the TOS desktop.

Use **Import Vault** and enter the directory that contains `vault.cryptomator` or `masterkey.cryptomator`, such as `/Volume1/data/MyVault`.

## Manual build

Required tools are `git`, `jq`, `curl`, `unzip`, `tar`, `xz`, `envsubst`, and `python3`.

This read-only check runs from the repository root and prints each available tool. Expected result: one executable path per tool. Risk level: safe.

```bash
command -v git jq curl unzip tar xz envsubst python3
```

This command builds the x86_64 package from the repository root. Expected result: one `.tpk` file under `dist/`. Risk level: safe; it replaces the local `build/` directory.

```bash
bash scripts/build-tpk.sh 1.19.1 x86_64
```

This command builds the aarch64 package from the repository root. Expected result: one `.tpk` file under `dist/`. Risk level: safe; it replaces the local `build/` directory.

```bash
bash scripts/build-tpk.sh 1.19.1 aarch64
```

Set `GH_TOKEN` in the shell before building if unauthenticated GitHub API limits are a problem. Do not write the token into this repository.

## Validation

This read-only command runs the API regression tests from the repository root. Expected result: all tests pass. Risk level: safe.

```bash
python3 -m unittest discover -s tests -v
```

The `Validate TNAS package` workflow runs these tests and checks shell syntax, package metadata, and the WebUI archive on pushes and pull requests that change TNAS files.

The `Build and Release TNAS TPK` workflow checks for new upstream releases and builds both CPU architectures. A manual run can force a specific version.

## Repository structure

```text
.github/workflows/
  build.yml                 TNAS source validation
  sync-and-release.yml      TPK build and release automation
scripts/
  build-tpk.sh              Local package builder
tests/
  test_cryptomator_api.py   Backend regression tests
tpk/
  config.ini.template       TOS package metadata
  cryptomator.lang          TOS translations
  init.d/                   systemd service
  modules/                  TOS iframe module metadata
  sbin/                     Unix-socket API service
  scripts/                  Install and removal hooks
  webui/                    Vault management interface
```

## TPK contents

The package contains:

- `config.ini` with TOS metadata
- `cryptomator.lang` with translated package details
- `init.d/cryptomator.service` for service startup
- `lib/cryptomator-cli/` with the CLI, runtime, and native FUSE bindings
- `sbin/cryptomator-api` with the local API service
- `webui.bz2` with the browser interface
- lifecycle scripts, icons, and module metadata

## License

The desktop source retains its [GPLv3 license](LICENSE.txt). Cryptomator CLI is distributed under its upstream AGPLv3 terms. The TNAS integration files in this repository must be distributed under compatible terms.
