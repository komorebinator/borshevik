#!/usr/bin/env bash
set -euo pipefail

DEST="/usr/share/gnome-shell/extensions"
TMP_DIR="$(mktemp -d)"

git clone --depth 1 https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator.git "$TMP_DIR/clipboard-indicator@tudmotu.com"
rsync -a --exclude=.git "$TMP_DIR/" "$DEST/"
rm -rf "$TMP_DIR"
