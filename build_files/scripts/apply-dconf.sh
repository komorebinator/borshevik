#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dconf compile /usr/share/gdm/greeter-dconf-defaults "$SCRIPT_DIR/dconf/gdm.d"

echo "→ Enable extensions by default"
EXT_DIRS=(/usr/share/gnome-shell/extensions/*)
LIST=""
for d in "${EXT_DIRS[@]}"; do
    NAME=$(basename "$d")
    LIST="$LIST,'$NAME'"
done
LIST="[${LIST#,}]"

mkdir -p /etc/dconf/db/local.d
cat <<EOF >/etc/dconf/db/local.d/00-extensions
[org/gnome/shell]
enabled-extensions=$LIST
EOF

echo "→ Installing additional user-default INI files"
for ini in "$SCRIPT_DIR"/dconf/local.d/*; do
    cp "$ini" /etc/dconf/db/local.d/$(basename "$ini")
done

dconf update
