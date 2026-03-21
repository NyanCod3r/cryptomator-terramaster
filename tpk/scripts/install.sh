#!/bin/bash
set -e

ROOT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPTS_PATH=$(dirname "$ROOT_PATH")
APP_ROOT=$(dirname "$SCRIPTS_PATH")

ln -sf "${APP_ROOT}/sbin/cryptomator-api" /usr/local/bin/cryptomator-api
chmod +x "${APP_ROOT}/sbin/cryptomator-api"
mkdir -p /mnt/cryptomator

echo "Cryptomator installed successfully"
