#!/usr/bin/env bash
set -euo pipefail

# Build a .deb package of RadioBot for a Debian/Ubuntu release.
# Output: ./radiobot_<version>-1~<distro>_amd64.deb
#
# Usage:
#   ./build-deb.sh              interactive distro picker
#   ./build-deb.sh <distro>     build one target non-interactively
#   ./build-deb.sh all          build all targets
#
# Distros: bookworm (Debian 12), trixie (Debian 13),
#          jammy (Ubuntu 22.04), noble (Ubuntu 24.04)

cd "$(dirname "$0")"

VERSION="${VERSION:-5.0.0}"
ORDER=(bookworm trixie jammy noble)
declare -A BASE=(
    [bookworm]=debian:bookworm
    [trixie]=debian:trixie
    [jammy]=ubuntu:22.04
    [noble]=ubuntu:24.04
)

usage() {
    echo "Usage: $0 [$(IFS='|'; echo "${ORDER[*]}")|all]" >&2
}

pick() {
    if [ -t 0 ] && [ -t 1 ] && command -v whiptail >/dev/null 2>&1; then
        whiptail --title "RadioBot .deb build" --menu \
            "Target distribution:" 16 60 5 \
            bookworm "Debian 12 (Bookworm)" \
            trixie   "Debian 13 (Trixie)" \
            jammy    "Ubuntu 22.04 LTS (Jammy)" \
            noble    "Ubuntu 24.04 LTS (Noble)" \
            all      "All of the above" 3>&1 1>&2 2>&3
    elif [ -t 0 ]; then
        local d
        select d in "${ORDER[@]}" all; do
            [ -n "$d" ] && { echo "$d"; return 0; }
        done
    else
        usage
        return 1
    fi
}

choice="${1:-}"
case "$choice" in
    -h|--help) usage; exit 0 ;;
    "")        choice=$(pick) || exit 1 ;;
esac

targets=()
if [ "$choice" = "all" ]; then
    targets=("${ORDER[@]}")
elif [ -n "${BASE[$choice]:-}" ]; then
    targets=("$choice")
else
    echo "Unknown distro: $choice" >&2
    usage
    exit 1
fi

mkdir -p artifacts

for d in "${targets[@]}"; do
    deb="radiobot_${VERSION}-1~${d}_amd64.deb"
    echo "=== Building $deb (${BASE[$d]}) ==="
    docker build -f Dockerfile.deb \
        --build-arg BASE_IMAGE="${BASE[$d]}" \
        --build-arg DISTRO_TAG="$d" \
        --build-arg VERSION="$VERSION" \
        -t "radiobot-deb-$d" .
    docker run --rm -v "$(pwd)/artifacts:/out" "radiobot-deb-$d"
    cp "artifacts/$deb" .
    echo "Package built: ./$deb"
done
