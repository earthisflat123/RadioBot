#!/usr/bin/env bash
# Package the vcpkg + deps trees from the Windows VM into a 7z archive on the host.
# If the VM is ever recreated, setup.ps1 will find radiobot-windows-deps.7z in the
# shared folder and extract it instead of rebuilding ffmpeg/etc from scratch.

set -euo pipefail

SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-builder}"
SSH_HOST="${SSH_HOST:-localhost}"
IDENTITY="${IDENTITY:-$HOME/.ssh/radiobot_windows_builder}"
OUT_DIR="${OUT_DIR:-.}"

if [[ ! -f "$IDENTITY" ]]; then
    cat <<EOF
SSH private key not found at: $IDENTITY
Run ./prepare-windows-build.sh first to generate the key pair.
EOF
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "Packaging dependency archive inside the VM..."
ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}" \
    'powershell -ExecutionPolicy Bypass -NoProfile -File C:\OEM\package-deps.ps1'

# The VM script tries to write directly to the host share (\\host.lan\Data).
# If it fell back to C:\Temp, pull the archive out with scp.
if ! ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}" \
    'powershell -ExecutionPolicy Bypass -NoProfile -Command "Test-Path C:\Temp\radiobot-windows-deps.7z"' | grep -q '^True$'; then
    echo "Archive not found in C:\\Temp, assuming it was written directly to the host share."
    exit 0
fi

echo "Copying archive from VM C:\\Temp to host..."
scp -P "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -i "$IDENTITY" \
    "${SSH_USER}@${SSH_HOST}:C:/Temp/radiobot-windows-deps.7z" "$OUT_DIR/radiobot-windows-deps.7z"

echo "Dependency archive saved to: $OUT_DIR/radiobot-windows-deps.7z"
