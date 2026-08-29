#!/usr/bin/env bash
set -euo pipefail

# Generate an SSH key pair so the host can connect to the Windows VM
# without a password. The public key is placed in windows-oem/ so it is
# baked into the Windows install image and added to authorized_keys.

OEM_DIR="windows-oem"
KEY="${HOME}/.ssh/radiobot_windows_builder"
PUB="${KEY}.pub"

mkdir -p "$OEM_DIR"

if [[ ! -f "$KEY" ]]; then
    echo "Generating SSH key pair for Windows VM..."
    mkdir -p "$(dirname "$KEY")"
    ssh-keygen -t rsa -b 4096 -f "$KEY" -N "" -C "radiobot-windows-builder"
    chmod 600 "$KEY"
    chmod 644 "$PUB"
else
    echo "SSH key already exists at $KEY"
fi

cp "$PUB" "$OEM_DIR/id_rsa.pub"
chmod 644 "$OEM_DIR/id_rsa.pub"

cat <<EOF

Prerequisites:
  - KVM is available on the host (/dev/kvm)
  - Docker Compose can access /dev/net/tun
  - At least 64 GB free disk space and 8 GB RAM
  - The host has a working internet connection

The Windows VM will be created with:
  - Visual Studio Build Tools 2022
  - vcpkg + core dependencies in C:\deps
  - OpenSSH server on port 22 (exposed as localhost:2222)

Next steps:
  1. Start the Windows VM:
       docker compose -f docker-compose.windows.yml up -d

  2. Wait for Windows to install and the setup script to complete.
     This can take 30-60 minutes. You can monitor it at:
       http://localhost:8006  (web VNC)
       rdesktop localhost:3389  (RDP)

  3. Once setup is done, build:
       IDENTITY="$KEY" ./build-windows.sh

  4. Built .exe and .dll files will appear in ./artifacts/ on the host
     (they are written to the shared Z: drive inside the VM).

Note: the first boot needs the SSH public key in windows-oem/ before the
Windows image is generated. If you already started the VM, destroy its
storage volume (./windows-storage) and start again.
EOF
