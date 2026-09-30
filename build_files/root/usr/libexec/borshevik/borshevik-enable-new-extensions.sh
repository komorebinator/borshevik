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

new=()
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
    else
        new+=("$uuid")
    fi
done

[[ ${#new[@]} -eq 0 ]] && exit 0

# One write for all of them: the shell enables each newly listed extension once. Enabling them
# one by one with `gnome-extensions enable` raced in the shell and enabled some twice.
added="$(printf ", '%s'" "${new[@]}")"
if [[ "$enabled_list" == "@as []" || "$enabled_list" == "[]" ]]; then
    updated="[${added#, }]"
else
    updated="${enabled_list%]}$added]"
fi

if gsettings set org.gnome.shell enabled-extensions "$updated"; then
    for uuid in "${new[@]}"; do
        echo "$uuid" >> "$STATE"
        echo "enabled $uuid"
    done
else
    echo "could not enable ${new[*]}; will retry at next login" >&2
    exit 1
fi
