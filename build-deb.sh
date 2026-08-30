#!/usr/bin/env bash
set -euo pipefail

# Build a Debian Trixie .deb package of RadioBot.
# Output: ./radiobot_5.0.0_amd64.deb

cd "$(dirname "$0")"

mkdir -p artifacts

docker build -f Dockerfile.debian-trixie -t radiobot-deb .
docker run --rm -v "$(pwd)/artifacts:/out" radiobot-deb cp /build/radiobot_5.0.0_amd64.deb /out/

cp artifacts/radiobot_5.0.0_amd64.deb .
echo "Package built: ./radiobot_5.0.0_amd64.deb"
