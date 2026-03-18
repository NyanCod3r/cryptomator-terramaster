#!/bin/sh
set -e

APP_DIR="/usr/local/app/cryptomator"

systemctl stop cryptomator.service 2>/dev/null || true
systemctl disable cryptomator.service 2>/dev/null || true
rm -f /etc/systemd/system/cryptomator.service 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

echo "Cryptomator removed"
