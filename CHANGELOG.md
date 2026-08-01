# Changelog

All notable changes to the TerraMaster package are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Upstream Cryptomator changes are documented in the [Cryptomator releases](https://github.com/cryptomator/cryptomator/releases).

## Unreleased

### Changed

- Converted the fork into a packaging-only repository.
- Removed unused JavaFX source, Maven configuration, desktop distribution files, IDE files, and upstream desktop automation.
- Changed release detection to check revision-specific TPK assets for both architectures.
- Kept GitHub release tags equal to upstream Cryptomator release tags.
- Updated the release action to `softprops/action-gh-release@v3`.

## TNAS package revision 1

### Fixed

- Normalize legacy numeric vault IDs so imported vaults can be unlocked without a false `Vault not found` response.
- Match unlock and lock API routes exactly.
- Send `SIGINT` to Cryptomator CLI for its documented graceful unmount behavior.
- Handle vault names containing apostrophes without generating invalid inline JavaScript.

### Changed

- Store vault registrations under `/var/lib/cryptomator` and migrate the old app-local configuration on first use.
- Replace inherited Cryptomator desktop workflows with TNAS package validation and release workflows.
- Add backend regression tests for import, unlock, lock, deletion, migration, and route handling.
