#!/bin/bash
set -e

rm -f /usr/local/bin/cryptomator-api
systemctl stop cryptomator 2>/dev/null || true
systemctl disable cryptomator 2>/dev/null || true
rm -f /var/api/cryptomator.sock

echo "Cryptomator removed"
