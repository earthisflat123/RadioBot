#!/usr/bin/env bash
# Tail the setup log from the running Windows VM via SSH.
# The setup script writes to C:\Temp\setup-radiobot.log.

set -euo pipefail

SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-builder}"
SSH_HOST="${SSH_HOST:-localhost}"
IDENTITY="${IDENTITY:-$HOME/.ssh/radiobot_windows_builder}"

if [[ ! -f "$IDENTITY" ]]; then
    echo "SSH private key not found at: $IDENTITY"
    echo "Run ./prepare-windows-build.sh first."
    exit 1
fi

echo "Tailing setup log from the Windows VM (press Ctrl+C to stop)..."
ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}" \
    'powershell -ExecutionPolicy Bypass -NoProfile -Command "Get-Content -Path C:\Temp\setup-radiobot.log -Wait -Tail 50"'
