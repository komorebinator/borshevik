#!/usr/bin/env bash
# The first-login scenario's checks, run inside the test VM as root after tester's
# login and the image checks. See @Services#first-login-scenario in spec/.
# prepare.sh removed tester's App Manager first-run stamp before the login.
set -u

user=tester
failed=0
ok()   { echo "ok first-login-$1"; }
fail() { echo "FAIL first-login-$1: $2"; failed=1; }

uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL first-login-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
as_user() {
    runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# 1. the first run started only once GNOME Shell was up, and is still running
unit=borshevik-app-manager-first-run.service
state="$(as_user systemctl --user show "$unit" -p ActiveState --value)"
started="$(as_user systemctl --user show "$unit" -p ExecMainStartTimestampMonotonic --value)"
target="$(as_user systemctl --user show gnome-session@gnome.target -p ActiveEnterTimestampMonotonic --value)"
if [[ "$state" == activating && "${started:-0}" -gt 0 && "${target:-0}" -gt 0 && "$started" -ge "$target" ]]; then
    ok after-shell
else
    fail after-shell "state=$state started=$started gnome-session@gnome.target active at $target"
fi

# 2. the App Manager runs in tester's session
owned="$(as_user gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner org.borshevik.AppManager 2>&1)"
[[ "$owned" == "(true,)" ]] && ok app-manager-running || fail app-manager-running "org.borshevik.AppManager on tester's bus: $owned"

# 3. and, its window still open, has not been marked as done
stamp="$home/.local/state/borshevik/app-manager-first-run.done"
[[ ! -e "$stamp" ]] && ok no-stamp-yet || fail no-stamp-yet "$stamp exists with the App Manager still open"

if [[ "$failed" -eq 0 ]]; then
    echo "all checks pass"
fi
exit "$failed"
