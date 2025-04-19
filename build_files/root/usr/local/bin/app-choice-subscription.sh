#!/usr/bin/env bash
set -oue pipefail

LIST_FILE="/usr/share/app-choice-subscription/flatpaks.txt"

# Ensure flathub is available
if ! flatpak remote-list | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Read package list and install missing
while read -r app; do
    [ -z "$app" ] && continue
    if ! flatpak list --app | grep -q "$app"; then
        echo "Installing missing flatpak: $app"
        flatpak install -y --noninteractive flathub "$app"
    fi
done < "$LIST_FILE"