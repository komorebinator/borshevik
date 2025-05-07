#!/usr/bin/env bash
set -euo pipefail

# Custom installer for GSConnect GNOME Shell extension.
# Copies extension source into the system extensions directory,
# installs GSettings schemas both locally (in the extension folder)
# and system-wide (for GSettings to find them),
# and installs Nautilus integration script.

# Constants
dest="/usr/share/gnome-shell/extensions"
system_schemas_dir="/usr/local/share/glib-2.0/schemas"
nautilus_ext_dir="/usr/share/nautilus-python/extensions"

# Ensure required commands
for cmd in jq rsync glib-compile-schemas; do
    command -v "$cmd" >/dev/null || {
        echo "Error: $cmd is required" >&2
        exit 1
    }
done

# Working directory is the extension source (metadata.json present here)
# Extract UUID from metadata.json
uuid=$(jq -r '.uuid' metadata.json)
if [[ -z "$uuid" || "$uuid" == "null" ]]; then
    echo "Error: cannot determine UUID from metadata.json" >&2
    exit 1
fi

echo "Installing GSConnect extension ($uuid)..."

# Copy extension into GNOME Shell extensions directory
mkdir -p "$dest/$uuid"
rsync -a --delete --exclude ".git" . "$dest/$uuid/"
echo "→ Copied files to $dest/$uuid"

# Compile local schemas
echo "→ Compiling local schemas in extension directory..."
glib-compile-schemas "$dest/$uuid/schemas"

# Install system-wide schemas
echo "→ Installing system-wide schemas..."
mkdir -p "$system_schemas_dir"
rsync -a "schemas/" "$system_schemas_dir/"
glib-compile-schemas "$system_schemas_dir"
echo "→ System schemas installed and compiled."

# Install Nautilus integration script
echo "→ Installing Nautilus extension script..."
mkdir -p "$nautilus_ext_dir"
rsync -a "nautilus-gsconnect.py" "$nautilus_ext_dir/"
echo "→ Nautilus integration installed."

echo "✔ GSConnect installed successfully with schemas and Nautilus integration."
