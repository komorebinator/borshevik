#!/usr/bin/env bash
set -euo pipefail

# Expect $PWD to be the root of the repo (blur-my-shell@aunetx)
echo "Installing Blur My Shell…"

# 1) Extract the UUID from metadata.json
UUID=$(jq -r .uuid metadata.json)
DEST="/usr/share/gnome-shell/extensions/$UUID"

# 2) Copy only the necessary files and directories
rm -rf "$DEST"
mkdir -p "$DEST"

# Files/folders to copy: metadata.json plus all resource directories
rsync -a \
    metadata.json \
    devices/ icons/ lib/ resources/ preferences/ tool/ ui/ po/ \
    "$DEST/"

# 3) Compile GSettings schemas if they exist
if [[ -d "$DEST/schemas" ]]; then
    echo "Compiling GSettings schemas…"
fi

echo "✔ Blur My Shell installed at $DEST"
