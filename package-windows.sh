#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-builder}"
SSH_HOST="${SSH_HOST:-localhost}"
IDENTITY="${IDENTITY:-$HOME/.ssh/radiobot_windows_builder}"

if [[ ! -f "$IDENTITY" ]]; then
    cat <<EOF
SSH private key not found at: $IDENTITY
Run ./prepare-windows-build.sh first to generate the key pair.
EOF
    exit 1
fi

echo "Building RadioBot Windows installer package in the VM..."
ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}" \
    'powershell -ExecutionPolicy Bypass -NoProfile -File C:\OEM\package-installer.ps1'

echo ""
echo "Copying installer from the VM..."
scp -P "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}:C:/RadioBot/artifacts/RadioBot-setup.exe" "artifacts/RadioBot-setup.exe"

echo ""
echo "Installer package is ready: artifacts/RadioBot-setup.exe"
