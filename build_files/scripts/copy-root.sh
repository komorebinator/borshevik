#!/bin/bash
set -oue pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../root"

# If /usr/local exists and is NOT a directory, forcibly remove it
if [ -e /usr/local ] && [ ! -d /usr/local ]; then
    echo "⚠️  /usr/local exists but is not a directory. Removing it."
    rm -rf /usr/local
fi

# Ensure /usr/local exists
mkdir -p /usr/local

# Copy everything from root/ into /
cp -r "${ROOT_DIR}/." /