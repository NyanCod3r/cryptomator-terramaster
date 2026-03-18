#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="cryptomator/cryptomator"
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
    echo "  version   Upstream Cryptomator version (e.g. 1.19.1)"
    echo "  arch      Target architecture: x86_64 or aarch64"
    echo ""
    echo "Environment variables:"
    echo "  PKG_REVISION   Package revision number (default: 0)"
    echo "  GH_TOKEN       GitHub token for API requests (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 1.19.1 x86_64"
    echo "  PKG_REVISION=1 $0 1.19.1 aarch64"
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
        MAKEAPP_TOOL="makeapp_x64"
        APP_DIR_PREFIX="x64_tos6_apps"
        APPIMAGE_SUFFIX="x86_64"
        ;;
    aarch64)
        TOS_LABEL="TOS6"
        MAKEAPP_TOOL="makeapp_arm"
        APP_DIR_PREFIX="arm_tos6_apps"
        APPIMAGE_SUFFIX="aarch64"
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

echo ">>> Downloading AppImage for ${ARCH}"
AUTH_HEADER=""
if [ -n "${GH_TOKEN:-}" ]; then
    AUTH_HEADER="-H \"Authorization: token ${GH_TOKEN}\""
fi

RELEASE_JSON=$(curl -sf \
    ${AUTH_HEADER:+-H "Authorization: token ${GH_TOKEN}"} \
    "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${VERSION}")

DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
    | jq -r ".assets[] | select(.name | test(\"cryptomator-.*${APPIMAGE_SUFFIX}.*\\\\.AppImage$\")) | .browser_download_url" \
    | head -1)

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "Error: No AppImage found for ${ARCH} in release ${VERSION}"
    echo "Available assets:"
    echo "$RELEASE_JSON" | jq -r '.assets[].name'
    exit 1
fi

APPIMAGE_PATH="${BUILD_DIR}/cryptomator.AppImage"
echo "Downloading: ${DOWNLOAD_URL}"
curl -sSfL -o "$APPIMAGE_PATH" "$DOWNLOAD_URL"
chmod +x "$APPIMAGE_PATH"

echo ">>> Extracting AppImage"
cd "${BUILD_DIR}"
if ! ./cryptomator.AppImage --appimage-extract 2>/dev/null; then
    echo "Native extraction failed, using unsquashfs"
    OFFSET=$(grep -Poab 'hsqs' cryptomator.AppImage | head -1 | cut -d: -f1)
    if [ -z "$OFFSET" ]; then
        echo "Error: Cannot find squashfs magic in AppImage"
        exit 1
    fi
    unsquashfs -offset "$OFFSET" -dest squashfs-root cryptomator.AppImage
fi

echo ">>> Preparing TOS package structure"
PKG_DIR="${BUILD_DIR}/app-pkg-tools/${APP_DIR_PREFIX}/${APP_NAME}/output"
mkdir -p "${PKG_DIR}/bin"
mkdir -p "${PKG_DIR}/lib/cryptomator"
mkdir -p "${PKG_DIR}/images/icons"
mkdir -p "${PKG_DIR}/init.d"
mkdir -p "${PKG_DIR}/scripts"
mkdir -p "${PKG_DIR}/config"

cp -a "${BUILD_DIR}/squashfs-root/"* "${PKG_DIR}/lib/cryptomator/"

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

ICON_SRC=$(find "${BUILD_DIR}/squashfs-root" -maxdepth 2 \
    \( -name "cryptomator.png" -o -name "org.cryptomator.Cryptomator.png" \) \
    | head -1)
if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "${PKG_DIR}/images/icons/cryptomator.png"
fi

cat > "${PKG_DIR}/bin/cryptomator" << 'WRAPPER'
#!/bin/sh
INSTALL_DIR="/usr/local/app/cryptomator"
export LD_LIBRARY_PATH="${INSTALL_DIR}/lib/cryptomator/usr/lib:${LD_LIBRARY_PATH:-}"
exec "${INSTALL_DIR}/lib/cryptomator/AppRun" "$@"
WRAPPER
chmod +x "${PKG_DIR}/bin/cryptomator"

echo ">>> Computing MD5 and building TPK"
cd "${PKG_DIR}"
MD5=$(find . -type f ! -name config.ini -exec md5sum {} \; | sort | md5sum | awk '{print $1}')
echo "MD5: ${MD5}"
jq --arg md5 "$MD5" '.md5 = $md5' config.ini > config.ini.tmp && mv config.ini.tmp config.ini

echo "Final config.ini:"
cat config.ini

echo ">>> Creating TPK archive"
mkdir -p "${REPO_DIR}/dist"
cd "${PKG_DIR}"
tar czf "${REPO_DIR}/dist/${TPK_NAME}" .

echo ""
echo "Done: dist/${TPK_NAME}"
ls -lh "${REPO_DIR}/dist/${TPK_NAME}"
