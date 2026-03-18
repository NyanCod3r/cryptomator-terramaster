# Cryptomator for TerraMaster TOS

Automated packaging of [Cryptomator](https://github.com/cryptomator/cryptomator) as `.tpk` packages for TerraMaster NAS devices running TOS.

## How it works

A GitHub Actions workflow runs every 6 hours to:

1. **Sync** this fork with the upstream `cryptomator/cryptomator` repository
2. **Check** for new upstream releases via the GitHub API
3. **Build** `.tpk` packages for each architecture by downloading the upstream AppImage, extracting it, and repackaging with TOS metadata
4. **Release** the `.tpk` files as a GitHub Release matching the upstream version tag

Each upstream release produces two `.tpk` packages:

| Package | Architecture | TOS Version |
|---------|-------------|-------------|
| `Cryptomator TOS7_TOS6 <ver>.0 x86_64.tpk` | x86_64 (Intel/AMD) | TOS 6 + TOS 7 |
| `Cryptomator TOS6 <ver>.0 aarch64.tpk` | aarch64 (ARM) | TOS 6 |

## Installation on TerraMaster NAS

1. Download the `.tpk` matching your NAS CPU architecture from [Releases](../../releases)
2. Open the TOS web interface
3. Go to **App Management** > **Install from TPK**
4. Select the downloaded `.tpk` file

## Manual build

Prerequisites: `git`, `jq`, `curl`, `squashfs-tools`

````bash
chmod +x scripts/build-tpk.sh
scripts/build-tpk.sh 1.19.1 x86_64
scripts/build-tpk.sh 1.19.1 aarch64
````

Output goes to `dist/`.

Set `GH_TOKEN` to avoid GitHub API rate limits:

````bash
export GH_TOKEN="ghp_..."
scripts/build-tpk.sh 1.19.1 x86_64
````

## Repository structure

````
.github/workflows/
  sync-and-release.yml   # CI: upstream sync + release automation
tpk/
  config.ini.template    # TOS package metadata template
  cryptomator.lang       # Multilingual app name/description
  init.d/
    cryptomator.service  # systemd service unit
  scripts/
    install.sh           # Post-install script
    remove.sh            # Pre-removal script
scripts/
  build-tpk.sh           # Local build script
````

## Configuration

The workflow is configured via environment variables at the top of the workflow file:

| Variable | Default | Description |
|----------|---------|-------------|
| `UPSTREAM_REPO` | `cryptomator/cryptomator` | Upstream GitHub repository |
| `APP_NAME` | `Cryptomator` | Application display name |
| `PKG_REVISION` | `0` | Package revision suffix (the `.0` in `1.19.1.0`) |

To force a build for a specific version, use the **workflow_dispatch** trigger from the Actions tab and provide the version string.

## TOS package format

Packages are built using the [TerraMaster app-pkg-tools](https://github.com/TerraMasterOfficial/app-pkg-tools). The `.tpk` contains:

- `config.ini` - JSON metadata (app ID, version, platform, dependencies)
- `cryptomator.lang` - Multilingual strings
- `init.d/cryptomator.service` - systemd unit for auto-start
- `bin/cryptomator` - CLI wrapper
- `lib/cryptomator/` - Extracted AppImage contents (JRE + application)
- `images/icons/cryptomator.png` - App icon
- `scripts/install.sh` / `scripts/remove.sh` - Lifecycle hooks

## License

Cryptomator is licensed under [GPLv3](https://github.com/cryptomator/cryptomator/blob/main/LICENSE.txt) by Skymatic GmbH. This packaging repository only adds TOS integration files.
