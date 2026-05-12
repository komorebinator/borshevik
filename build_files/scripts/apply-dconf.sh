#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Apply gdm.d dconf"
mkdir -p /etc/dconf/db/gdm.d
cp "$SCRIPT_DIR/dconf/gdm.d/gdm" /etc/dconf/db/gdm.d/00-borshevik

mkdir -p /etc/dconf/profile
printf 'user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n' > /etc/dconf/profile/gdm

echo "→ Apply local.d dconf"
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
