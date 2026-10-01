#!/usr/bin/env bash
# The new-extensions scenario's checks, run inside the test VM as root after
# tester's login and the image checks. See @Services#extension-autoenable#vm-scenario
# in spec/. prepare.sh emptied tester's extension lists before the login.
set -u

user=tester
failed=0
ok()   { echo "ok new-extensions-$1"; }
fail() { echo "FAIL new-extensions-$1: $2"; failed=1; }

uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL new-extensions-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
as_user() {
    runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

shipped="$(for d in /usr/share/gnome-shell/extensions/*/; do basename "$d"; done | sort)"
count="$(wc -l <<<"$shipped")"

# a gsettings string list as one uuid per line
as_lines() { python3 -c 'import ast, sys; [print(x) for x in ast.literal_eval(sys.stdin.read().replace("@as ", ""))]'; }
enabled="$(as_user gsettings get org.gnome.shell enabled-extensions | as_lines)"
disabled="$(as_user gsettings get org.gnome.shell disabled-extensions | as_lines)"

# 1. every shipped extension is enabled
missing="$(comm -23 <(echo "$shipped") <(echo "$enabled" | sort -u) | tr '\n' ' ')"
[[ -z "$missing" ]] && ok "all-enabled ($count extensions)" || fail all-enabled "not enabled: $missing"

# 2. and none twice
twice="$(echo "$enabled" | sort | uniq -d | tr '\n' ' ')"
[[ -z "$twice" ]] && ok none-twice || fail none-twice "listed twice: $twice"

# 3. nothing was switched off on the way
[[ -z "$disabled" ]] && ok none-disabled || fail none-disabled "disabled-extensions: $(echo "$disabled" | tr '\n' ' ')"

# 4. every shipped extension is recorded as offered, once
state="$home/.local/state/borshevik/offered-extensions"
if [[ -f "$state" ]]; then
    missing="$(comm -23 <(echo "$shipped") <(sort -u "$state") | tr '\n' ' ')"
    twice="$(sort "$state" | uniq -d | tr '\n' ' ')"
    if [[ -z "$missing" && -z "$twice" ]]; then
        ok offered
    else
        fail offered "not recorded: ${missing:-none}; recorded twice: ${twice:-none}"
    fi
else
    fail offered "no $state"
fi

# 5. it was the service, in this login, that enabled each of them
logged="$(journalctl -b _UID="$uid" --user-unit borshevik-enable-new-extensions.service -o cat 2>/dev/null |
    sed -n 's/^enabled //p' | sort -u)"
missing="$(comm -23 <(echo "$shipped") <(echo "$logged") | tr '\n' ' ')"
[[ -z "$missing" ]] && ok service-enabled-them || fail service-enabled-them "the service did not log enabling: $missing"

if [[ "$failed" -eq 0 ]]; then
    echo "all checks pass"
fi
exit "$failed"
