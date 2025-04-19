#!/bin/bash
set -oue pipefail

# Create override file to set default GNOME favorites (dock icons)
cat <<EOF > /usr/share/glib-2.0/schemas/99-chrome-favorite.gschema.override
[org.gnome.shell]
favorite-apps=['google-chrome.desktop', 'org.gnome.Nautilus.desktop']
EOF

# Compile schemas so GNOME picks up the new defaults
glib-compile-schemas /usr/share/glib-2.0/schemas

systemctl enable app-choice-subscription.service