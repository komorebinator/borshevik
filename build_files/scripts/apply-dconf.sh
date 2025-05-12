#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dconf compile /usr/share/gdm/greeter-dconf-defaults "$SCRIPT_DIR/dconf/gdm.d"
mkdir -p /etc/dconf/db/local.d

echo "→ Installing user-default INI files"
cp -r "$SCRIPT_DIR"/dconf/local.d/. /etc/dconf/db/local.d/ 2>/dev/null || true

dconf update
echo "✅ DConf update complete"
