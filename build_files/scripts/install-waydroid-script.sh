#!/usr/bin/env bash
set -euo pipefail

# Puts casualsnek/waydroid_script into the image, with its Python requirements
# in a virtual environment beside it. borshevik-waydroid runs it as root to
# install the ARM translation layer into Android — at a pinned
# commit, so the version users run is the one that was tested, and nothing is
# cloned or pip-installed on a user's machine. The script holds no Android
# binaries itself; what it installs it downloads when run.

WAYDROID_SCRIPT_COMMIT="48dbfaf34a6ddbe78688c530f9ba1c26522aafb2"
DEST_DIR="/usr/lib/borshevik/waydroid_script"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "Fetching waydroid_script ${WAYDROID_SCRIPT_COMMIT}"
curl -fL --retry 3 --retry-delay 2 \
    -o "${WORKDIR}/waydroid_script.tar.gz" \
    "https://github.com/casualsnek/waydroid_script/archive/${WAYDROID_SCRIPT_COMMIT}.tar.gz"

mkdir -p "$DEST_DIR"
tar xzf "${WORKDIR}/waydroid_script.tar.gz" -C "$DEST_DIR" --strip-components=1

python3 -m venv "${DEST_DIR}/venv"
"${DEST_DIR}/venv/bin/pip" install --no-cache-dir -r "${DEST_DIR}/requirements.txt"

echo "waydroid_script ${WAYDROID_SCRIPT_COMMIT} → ${DEST_DIR}"
