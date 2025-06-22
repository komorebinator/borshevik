#!/usr/bin/env bash
set -oue pipefail

LIST_FILE="/usr/share/app-choice-subscription/flatpaks.txt"
STATE_DIR="/var/lib/app-choice-subscription"
STATE_FILE="$STATE_DIR/flatpaks-installed.txt"

# Ensure state directory and file exist
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# Ensure flathub is available
if ! flatpak remote-list | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Read package list and install missing ones not previously installed by this script
while read -r app; do
    [ -z "$app" ] && continue

    # Skip if it was installed earlier by this script, then removed manually
    if grep -Fxq "$app" "$STATE_FILE"; then
        echo "Skip $app"
        continue
    fi

    # Skip if already installed manually or in system image
    if flatpak list --app | grep -q "$app"; then
        echo "$app" >>"$STATE_FILE"
        echo "$app is already installed, adding to skip list"
        continue
    fi

    echo "Installing missing flatpak: $app"
    if flatpak install -y --noninteractive flathub "$app"; then
        echo "✅ Installed: $app"
        echo "$app" >>"$STATE_FILE"
    fi
done <"$LIST_FILE"
