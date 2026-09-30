#!/usr/bin/env bash
# Checks run inside the test VM, as root, after tester's login. See @BorshevikWorkflow#image-checks
# in spec/. Reads the running system and this boot's journal; changes nothing.
set -u

expected="${1:?usage: image-checks.sh <expected image digest>}"
user=tester
failed=0
ok()   { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; failed=1; }

uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL setup: no user $user"; exit 1; }
as_user() {
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# 1. the image under test is what booted, and it came in signed
image="$(rpm-ostree status --json | python3 -c '
import json, sys
b = [d for d in json.load(sys.stdin)["deployments"] if d.get("booted")][0]
print(b.get("container-image-reference-digest", ""), b.get("container-image-reference", ""))')"
digest="${image%% *}"; ref="${image#* }"
if [[ "$digest" == "$expected" && "$ref" == ostree-image-signed:* ]]; then
    ok image
else
    fail image "booted $digest from $ref, expected $expected, signed"
fi

# 2. no failed system units
units="$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
[[ -z "$units" ]] && ok system-units || fail system-units "$units"

# 3. nothing crashed this boot
dumps="$(coredumpctl -F COREDUMP_EXE --since "$(uptime -s)" --no-pager 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
[[ -z "$dumps" ]] && ok coredumps || fail coredumps "$dumps"

# 4. tester got in on the first try
sessions="$(journalctl -b -o cat _COMM=systemd-logind | grep -c "New session .* of user '$user' with class 'user'")"
aborts="$(journalctl -b -o cat | grep -c 'A graphical session is already running')"
if [[ "$sessions" -eq 1 && "$aborts" -eq 0 ]]; then
    ok login
else
    fail login "$sessions graphical sessions for $user, $aborts 'already running' aborts"
fi

# 5. GNOME Shell runs for tester
pgrep -u "$user" -x gnome-shell >/dev/null && ok shell || fail shell "no gnome-shell process for $user"

# 6. no failed units in tester's user manager
units="$(as_user systemctl --user --failed --no-legend --plain 2>&1 | awk '{print $1}' | tr '\n' ' ')"
[[ -z "$units" ]] && ok user-units || fail user-units "$units"

# 7. every extension the image ships is running
bad=""
for dir in /usr/share/gnome-shell/extensions/*/; do
    uuid="$(basename "$dir")"
    state="$(as_user gnome-extensions info "$uuid" 2>/dev/null | sed -n 's/^ *State: //p')"
    [[ "$state" == ACTIVE ]] || bad+="$uuid=${state:-unknown} "
done
[[ -z "$bad" ]] && ok extensions || fail extensions "$bad"

# 8. no extension reported an error
errors="$(journalctl -b -o cat _UID="$uid" _COMM=gnome-shell 2>/dev/null |
    grep -E 'Extension [^ ]+: .*[Ee]rror|Extension point conflict|JS ERROR' |
    cut -c1-160 | sort -u | head -5 | tr '\n' ';')"
[[ -z "$errors" ]] && ok extension-errors || fail extension-errors "$errors"

# 9. the extension service ran, successfully, only once GNOME Shell was up
unit=borshevik-enable-new-extensions.service
result="$(as_user systemctl --user show "$unit" -p Result --value)"
started="$(as_user systemctl --user show "$unit" -p ExecMainStartTimestampMonotonic --value)"
target="$(as_user systemctl --user show gnome-session@gnome.target -p ActiveEnterTimestampMonotonic --value)"
if [[ "$result" == success && "${started:-0}" -gt 0 && "${target:-0}" -gt 0 && "$started" -ge "$target" ]]; then
    ok enable-new-extensions
else
    fail enable-new-extensions "result=$result started=$started gnome-session@gnome.target active at $target"
fi

# 10. Blur my Shell leaves popups alone by default
blur="$(as_user gsettings --schemadir /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas \
    get org.gnome.shell.extensions.blur-my-shell.popup blur 2>&1)"
[[ "$blur" == false ]] && ok blur-popups || fail blur-popups "popup blur is $blur"

if [[ "$failed" -eq 0 ]]; then
    echo "all checks pass"
fi
exit "$failed"
