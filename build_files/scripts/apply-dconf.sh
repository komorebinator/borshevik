#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dconf compile /usr/share/gdm/greeter-dconf-defaults "$SCRIPT_DIR/dconf/gdm.d"
cp -a "$SCRIPT_DIR/dconf/local.d/." /etc/dconf/db/local.d/

echo "→ Enable extensions by default"
EXT_DIRS=(/usr/share/gnome-shell/extensions/*)
LIST=""
for d in "${EXT_DIRS[@]}"; do
    NAME=$(basename "$d")
    LIST="$LIST,'$NAME'"
done
LIST="[${LIST#,}]"

cat <<EOF >/etc/dconf/db/local.d/00-extensions
[org/gnome/shell]
enabled-extensions=$LIST
EOF

dconf update
