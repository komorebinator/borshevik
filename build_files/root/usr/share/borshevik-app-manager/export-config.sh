#!/usr/bin/env bash
# Prints this computer's configuration for the Borshevik App Manager's Import,
# and copies it to the clipboard unless run with --print. Runs on Borshevik
# (the App Manager runs it) and on any other Linux (pasted into a terminal).
# See @AppManagerApp#export-script in spec/.
#
#   export-config.sh [--print] [applications] [modules]

# The categories to export when none are given as arguments; the App Manager
# writes the chosen ones here when it hands this script over to be pasted.
CATEGORIES="applications modules"

print_only=
args=()
for arg in "$@"; do
    case "$arg" in
        --print) print_only=1 ;;
        *) args+=("$arg") ;;
    esac
done
if [[ ${#args[@]} -gt 0 ]]; then
    CATEGORIES="${args[*]}"
fi

wants() { # category
    [[ " $CATEGORIES " == *" $1 "* ]]
}

# Ids of the form Flathub uses, so the JSON below needs no escaping.
is_app_id() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z_][A-Za-z0-9_-]*)+$ ]]
}

json_list() { # indent, items... - one item a line, so a long list stays readable
    local indent="$1" out="" item
    shift
    if [[ $# -eq 0 ]]; then
        printf '[]'
        return
    fi
    for item in "$@"; do
        out+="${out:+,}"$'\n'"${indent}  \"${item}\""
    done
    printf '[%s\n%s]' "$out" "$indent"
}

flathub_apps() {
    command -v flatpak >/dev/null 2>&1 || return 0
    local id origin
    while read -r id origin; do
        if [[ "$origin" == flathub ]] && is_app_id "$id"; then
            echo "$id"
        fi
    done < <(flatpak list --app --columns=application,origin 2>/dev/null)
}

installed_modules() {
    if [[ -f /var/lib/borshevik/waydroid-installed ]] \
        || { command -v waydroid >/dev/null 2>&1 && [[ -f /var/lib/waydroid/images/system.img ]]; }; then
        echo android
    fi
}

config() {
    local fields=() apps=() modules=()
    fields+=('  "borshevik-config": 1')
    if wants applications; then
        mapfile -t apps < <(flathub_apps | sort -u)
        fields+=("  \"applications\": {"$'\n'"    \"flatpak\": $(json_list "    " "${apps[@]}")"$'\n'"  }")
    fi
    if wants modules; then
        mapfile -t modules < <(installed_modules)
        fields+=("  \"modules\": $(json_list "  " "${modules[@]}")")
    fi
    local out="" field
    for field in "${fields[@]}"; do
        out+="${out:+,$'\n'}${field}"
    done
    printf '{\n%s\n}\n' "$out"
}

text="$(config)"
printf '%s\n' "$text"
if [[ -n "$print_only" ]]; then
    exit 0
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s\n' "$text" | wl-copy && copied=wl-copy
elif command -v xclip >/dev/null 2>&1; then
    printf '%s\n' "$text" | xclip -selection clipboard && copied=xclip
elif command -v xsel >/dev/null 2>&1; then
    printf '%s\n' "$text" | xsel --clipboard --input && copied=xsel
fi
if [[ -n "${copied:-}" ]]; then
    echo "The configuration above is on the clipboard: paste it into Import in the Borshevik App Manager." >&2
else
    echo "Could not copy to the clipboard (no wl-copy, xclip or xsel): copy the configuration above by hand." >&2
fi
