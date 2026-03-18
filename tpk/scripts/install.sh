#!/bin/sh
set -e

APP_DIR="/usr/local/app/cryptomator"

mkdir -p "${APP_DIR}/config"
mkdir -p "${APP_DIR}/data"

if [ ! -f "${APP_DIR}/config/cryptomator.env" ]; then
    cat > "${APP_DIR}/config/cryptomator.env" << 'EOF'
# Cryptomator environment configuration
# Add vault paths and options here
# CRYPTOMATOR_OPTS=""
EOF
fi

chmod +x "${APP_DIR}/bin/cryptomator" 2>/dev/null || true
chmod +x "${APP_DIR}/lib/cryptomator/AppRun" 2>/dev/null || true

echo "Cryptomator installed successfully"
