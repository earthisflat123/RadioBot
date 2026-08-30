#!/bin/bash
# Download the test MP3s used for end-to-end RadioBot testing.
# These tracks are from the Free Music Archive and are licensed CC0 1.0 Universal.
# See README.md for attribution.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/mp3s"

mkdir -p "$OUT_DIR"

curl -L -A "Mozilla/5.0" \
  -o "$OUT_DIR/Soft_and_Furious_-_01_-_Youre_Magic.mp3" \
  "https://files.freemusicarchive.org/storage-freemusicarchive-org/music/Music_for_Video/Soft_and_Furious/Bae/Soft_and_Furious_-_01_-_Youre_Magic.mp3"

curl -L -A "Mozilla/5.0" \
  -o "$OUT_DIR/Soft_and_Furious_-_02_-_Game_On.mp3" \
  "https://files.freemusicarchive.org/storage-freemusicarchive-org/music/Music_for_Video/Soft_and_Furious/Bae/Soft_and_Furious_-_02_-_Game_On.mp3"

echo "Test MP3s downloaded to $OUT_DIR"
