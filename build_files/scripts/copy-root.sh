#!/bin/bash
set -oue pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../root"

# Fix invalid /usr/local if needed
if [ -e /usr/local ] && [ ! -d /usr/local ]; then
    echo "Fixing /usr/local (was not a directory)"
    rm -f /usr/local
    mkdir -p /usr/local
fi

# Copy everything
cp -r "${ROOT_DIR}/." /