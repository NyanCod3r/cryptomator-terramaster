#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="cryptomator/cryptomator"
CLI_REPO="cryptomator/cli"
APP_NAME="Cryptomator"
APP_ID="cryptomator"
PKG_REVISION="${PKG_REVISION:-0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${REPO_DIR}/build"

usage() {
    echo "Usage: $0 <version> <arch>"
    echo ""
    echo "Arguments:"
    echo "  version   Cryptomator version for branding (e.g. 1.19.2)"
    echo "  arch      Target architecture: x86_64 or aarch64"
    echo ""
    echo "Environment variables:"
    echo "  PKG_REVISION   Package revision number (default: 0)"
    echo "  GH_TOKEN       GitHub token for API requests (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 1.19.2 x86_64"
    echo "  PKG_REVISION=1 $0 1.19.2 aarch64"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

VERSION="$1"
ARCH="$2"

case "$ARCH" in
    x86_64)
        TOS_LABEL="TOS7_TOS6"
        APP_DIR_PREFIX="x64_tos6_apps"
        CLI_ARCH="linux-x64"
        ;;
    aarch64)
        TOS_LABEL="TOS6"
        APP_DIR_PREFIX="arm_tos6_apps"
        CLI_ARCH="linux-aarch64"
        ;;
    *)
        echo "Error: unsupported architecture '${ARCH}'. Use x86_64 or aarch64."
        exit 1
        ;;
esac

TPK_VERSION="${VERSION}.${PKG_REVISION}"
TPK_NAME="${APP_NAME} ${TOS_LABEL} ${TPK_VERSION} ${ARCH}.tpk"

echo "Building: ${TPK_NAME}"
echo "Upstream: ${UPSTREAM_REPO} @ ${VERSION}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo ">>> Cloning app-pkg-tools"
if [ ! -d "${BUILD_DIR}/app-pkg-tools" ]; then
    git clone --depth 1 https://github.com/TerraMasterOfficial/app-pkg-tools.git "${BUILD_DIR}/app-pkg-tools"
fi

echo ">>> Fetching latest cryptomator/cli release"
CLI_TAG=$(curl -sf \
    ${GH_TOKEN:+-H "Authorization: token ${GH_TOKEN}"} \
    "https://api.github.com/repos/${CLI_REPO}/releases/latest" \
    | jq -r '.tag_name')

if [ -z "$CLI_TAG" ] || [ "$CLI_TAG" = "null" ]; then
    echo "Error: Failed to fetch latest cryptomator/cli release"
    exit 1
fi

echo "Cryptomator version: ${VERSION}"
echo "CLI engine version: ${CLI_TAG}"

RELEASE_JSON=$(curl -sf \
    ${GH_TOKEN:+-H "Authorization: token ${GH_TOKEN}"} \
    "https://api.github.com/repos/${CLI_REPO}/releases/tags/${CLI_TAG}")

DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
    | jq -r ".assets[] | select(.name | test(\"cryptomator-cli-.*${CLI_ARCH}.*\\\\.zip$\")) | .browser_download_url" \
    | head -1)

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "Error: No CLI zip found for ${CLI_ARCH} in CLI release ${CLI_TAG}"
    echo "Available assets:"
    echo "$RELEASE_JSON" | jq -r '.assets[].name'
    exit 1
fi

CLI_ZIP="${BUILD_DIR}/cryptomator-cli.zip"
echo "Downloading: ${DOWNLOAD_URL}"
curl -sSfL -o "$CLI_ZIP" "$DOWNLOAD_URL"

echo ">>> Extracting CLI"
unzip "$CLI_ZIP" -d "${BUILD_DIR}"

echo ">>> Preparing TOS package structure"
PKG_DIR="${BUILD_DIR}/app-pkg-tools/${APP_DIR_PREFIX}/${APP_NAME}/output"
mkdir -p "${PKG_DIR}/sbin"
mkdir -p "${PKG_DIR}/lib"
mkdir -p "${PKG_DIR}/images/icons"
mkdir -p "${PKG_DIR}/images/cryptomator"
mkdir -p "${PKG_DIR}/init.d"
mkdir -p "${PKG_DIR}/scripts"
mkdir -p "${PKG_DIR}/config"
mkdir -p "${PKG_DIR}/modules"

cp -a "${BUILD_DIR}/cryptomator-cli" "${PKG_DIR}/lib/cryptomator-cli"

cp "${REPO_DIR}/tpk/sbin/cryptomator-api" "${PKG_DIR}/sbin/"
chmod +x "${PKG_DIR}/sbin/cryptomator-api"

export TPK_VERSION PLATFORM="$ARCH"
envsubst '${TPK_VERSION} ${PLATFORM}' \
    < "${REPO_DIR}/tpk/config.ini.template" \
    > "${PKG_DIR}/config.ini"

sed "s/^version = .*/version = ${VERSION}/" \
    "${REPO_DIR}/tpk/cryptomator.lang" > "${PKG_DIR}/cryptomator.lang"

cp "${REPO_DIR}/tpk/init.d/cryptomator.service" "${PKG_DIR}/init.d/"
cp "${REPO_DIR}/tpk/scripts/install.sh" "${PKG_DIR}/scripts/"
cp "${REPO_DIR}/tpk/scripts/remove.sh" "${PKG_DIR}/scripts/"
chmod +x "${PKG_DIR}/scripts/"*.sh

cp "${REPO_DIR}/tpk/images/icons/cryptomator.svg" "${PKG_DIR}/images/icons/cryptomator.svg"
cp "${REPO_DIR}/tpk/images/cryptomator/vaults.svg" "${PKG_DIR}/images/cryptomator/vaults.svg"
cp "${REPO_DIR}/tpk/modules/index.json" "${PKG_DIR}/modules/index.json"

echo ">>> Building webui.bz2"
tar -Jcf "${PKG_DIR}/webui.bz2" -C "${REPO_DIR}/tpk/webui" .

echo ">>> Building TPK (proper binary format)"
cd "${PKG_DIR}"

echo "Generating INFO manifest..."
: > INFO
find . -mindepth 1 -not -name INFO -not -name config.ini -not -path ./INFO -not -path ./config.ini | sort | while IFS= read -r entry; do
    entry="${entry#./}"
    if [ -d "$entry" ]; then
        echo "1:folder:${entry}:" >> INFO
    elif [ -f "$entry" ]; then
        fmd5=$(md5sum "$entry" | awk '{print $1}')
        echo "1:file:${entry}:${fmd5}" >> INFO
    fi
done

echo "Creating tar.xz payload..."
tar cJf /tmp/payload.tar.xz .

PAYLOAD_MD5=$(md5sum /tmp/payload.tar.xz | awk '{print $1}')
echo "Payload MD5: ${PAYLOAD_MD5}"

jq -c --arg md5 "$PAYLOAD_MD5" 'del(.user, .group, .low_memory, .cli) | {id: .id, md5: $md5} + (. | to_entries | map(select(.key != "id")) | from_entries)' config.ini > /tmp/header.json

mkdir -p "${REPO_DIR}/dist"
python3 -c "
import sys
header = open('/tmp/header.json','rb').read()
lang = open('${APP_ID}.lang','rb').read()
payload = open('/tmp/payload.tar.xz','rb').read()
if len(header) > 2048:
    print(f'ERROR: JSON header too large ({len(header)} > 2048)', file=sys.stderr)
    sys.exit(1)
if len(lang) > 8192:
    print(f'ERROR: Lang file too large ({len(lang)} > 8192)', file=sys.stderr)
    sys.exit(1)
tpk = header + b'\x00' * (2048 - len(header)) + lang + b'\x00' * (8192 - len(lang)) + payload
open('${REPO_DIR}/dist/${TPK_NAME}','wb').write(tpk)
print(f'TPK assembled: {len(tpk)} bytes (header={len(header)}, lang={len(lang)}, payload={len(payload)})')
"

echo ""
echo "Done: dist/${TPK_NAME}"
ls -lh "${REPO_DIR}/dist/${TPK_NAME}"
