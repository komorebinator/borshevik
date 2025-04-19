#!/usr/bin/env bash
set -oue pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../root"

# Safety: remove /usr/local if it's a file or a broken symlink
if [ -e /usr/local ] && [ ! -d /usr/local ]; then
    echo "Fixing /usr/local — removing non-directory version"
    rm -rf /usr/local
fi

# Copy everything from root/ to /
rsync -a "${ROOT_DIR}/" /