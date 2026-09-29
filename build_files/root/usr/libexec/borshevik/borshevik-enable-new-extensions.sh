#!/usr/bin/env bash
# Enables every GNOME Shell extension the image ships, once per extension per user.
#
# The image's default enabled-extensions is only a system-db default: once a user toggles any
# extension, their own list takes over and the default is never read again, so an extension
# added to the image later would stay off. Each system extension is offered once and recorded,
# and only enabled if neither of the user's lists names it, so switching one off is respected,
# whether that happened before this service existed or after.
set -uo pipefail

EXT_DIR=/usr/share/gnome-shell/extensions
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/borshevik/offered-extensions"

mkdir -p "$(dirname "$STATE")"
touch "$STATE"

# Printed as GVariant, e.g. ['a@b', 'c@d'] or @as [].
enabled_list="$(gsettings get org.gnome.shell enabled-extensions)"
disabled_list="$(gsettings get org.gnome.shell disabled-extensions)"

failed=0
for dir in "$EXT_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    uuid="$(basename "$dir")"
    grep -qxF "$uuid" "$STATE" && continue

    if grep -qF "'$uuid'" <<<"$enabled_list"; then
        echo "$uuid" >> "$STATE"
        echo "already enabled $uuid"
    elif grep -qF "'$uuid'" <<<"$disabled_list"; then
        # The shell puts an extension here when it is switched off.
        echo "$uuid" >> "$STATE"
        echo "kept disabled $uuid"
    # The shell updates enabled-extensions and clears disabled-extensions itself.
    elif gnome-extensions enable "$uuid"; then
        echo "$uuid" >> "$STATE"
        echo "enabled $uuid"
    else
        echo "could not enable $uuid; will retry at next login" >&2
        failed=1
    fi
done

exit "$failed"
