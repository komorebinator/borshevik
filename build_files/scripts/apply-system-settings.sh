#!/bin/bash
set -oue pipefail

# Create override file to set default GNOME favorites (dock icons)
cat <<EOF >/usr/share/glib-2.0/schemas/99-chrome-favorite.gschema.override
[org.gnome.shell]
favorite-apps=['google-chrome.desktop', 'org.telegram.desktop.desktop', 'org.gnome.Nautilus.desktop','org.gnome.Calendar.desktop','org.gnome.World.Secrets.desktop','com.usebottles.bottles.desktop','com.valvesoftware.Steam.desktop','org.gnome.Software.desktop']
EOF

# Compile schemas so GNOME picks up the new defaults
glib-compile-schemas /usr/share/glib-2.0/schemas

# Lookup for extensions to enabled
EXT_DIRS=(/usr/share/gnome-shell/extensions/*)
LIST=""
for d in "${EXT_DIRS[@]}"; do
    NAME=$(basename "$d")
    LIST="$LIST,'$NAME'"
done
LIST="[${LIST#,}]"

# Enable extensions by default
mkdir -p /etc/dconf/db/local.d
cat <<EOF >/etc/dconf/db/local.d/00-extensions
[org/gnome/shell]
enabled-extensions=$LIST
EOF
dconf update

systemctl enable app-choice-subscription.service
systemctl enable setup-kargs.service
