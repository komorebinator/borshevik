#!/usr/bin/env bash
# Enables every GNOME Shell extension the image ships, once per extension per user.
#
# The image's default enabled-extensions is only a system-db default: once a user toggles any
# extension, their own list takes over and the default is never read again, so an extension
# added to the image later would stay off. Each system extension is offered once and recorded,
# so switching one off afterwards is respected.
set -uo pipefail

EXT_DIR=/usr/share/gnome-shell/extensions
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/borshevik/offered-extensions"

mkdir -p "$(dirname "$STATE")"
touch "$STATE"

failed=0
for dir in "$EXT_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    uuid="$(basename "$dir")"
    grep -qxF "$uuid" "$STATE" && continue

    # The shell updates enabled-extensions and clears disabled-extensions itself.
    if gnome-extensions enable "$uuid"; then
        echo "$uuid" >> "$STATE"
        echo "enabled $uuid"
    else
        echo "could not enable $uuid; will retry at next login" >&2
        failed=1
    fi
done

exit "$failed"
