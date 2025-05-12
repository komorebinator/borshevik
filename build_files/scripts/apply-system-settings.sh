#!/bin/bash
set -oue pipefail

# Create override file to set default GNOME favorites (dock icons)
cat <<EOF >/usr/share/glib-2.0/schemas/99-chrome-favorite.gschema.override
[org.gnome.shell]
favorite-apps=['google-chrome.desktop', 'org.telegram.desktop.desktop', 'org.gnome.Nautilus.desktop','org.gnome.Calendar.desktop','org.gnome.World.Secrets.desktop','com.usebottles.bottles.desktop','com.valvesoftware.Steam.desktop','org.gnome.Software.desktop']
EOF

glib-compile-schemas /usr/share/glib-2.0/schemas

systemctl enable app-choice-subscription.service
systemctl enable setup-kargs.service
