#!/usr/bin/env bash
# The android scenario, run inside the test VM as root after tester's login.
# See @WaydroidApp#vm-scenario in spec/. Unlike image-checks it changes the
# system: it installs Android, removes it and installs it again, downloading a
# few GB on the way. Logs of the long steps go to /var/tmp/scenario-android/,
# which test-image-in-vm copies into the run directory.
set -u

user=tester
failed=0
ok()   { echo "ok android-$1"; }
fail() { echo "FAIL android-$1: $2"; failed=1; }

CONTROL=/usr/libexec/borshevik/borshevik-waydroid
MODULES=/usr/libexec/borshevik/borshevik-modules
STAMP=/var/lib/borshevik/waydroid-installed
ENTRY=/usr/local/share/applications/borshevik-android.desktop
TIMER=borshevik-waydroid-update.timer
SERVICE=borshevik-waydroid-update.service
CONTAINER=waydroid-container.service
logs=/var/tmp/scenario-android
mkdir -p "$logs"

uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL android-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
as_user() {
    runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland "$@"
}

# runs a long command, keeping its output in a log; prints the tail on failure
logged() { # name, command...
    local name="$1"; shift
    "$@" >"$logs/$name.log" 2>&1
    local rc=$?
    echo "$rc" >"$logs/$name.rc"
    return "$rc"
}
tail_of() { tail -n 8 "$logs/$1.log" | tr '\n' ' ' | cut -c1-600; }

session_running() { as_user waydroid status 2>/dev/null | grep -Eq '^Session:[[:space:]]*RUNNING'; }

wait_session() { # seconds
    for _ in $(seq $(($1 / 3))); do
        session_running && return 0
        sleep 3
    done
    return 1
}

# runs a JS snippet under gjs in tester's session, with a main loop so the
# modules' asynchronous Gio calls complete; prints the snippet's JSON result
gjs_as_user() { # name, module-body (must define: async function main())
    local file="$logs/$1.mjs"
    cat >"$file" <<EOF
import GLib from 'gi://GLib';
$2
const loop = new GLib.MainLoop(null, false);
let out = null;
main().then((r) => { out = r; })
    .catch((e) => { out = { error: String(e), stack: String(e?.stack ?? '') }; })
    .finally(() => loop.quit());
loop.run();
print(JSON.stringify(out));
EOF
    chmod 0644 "$file"
    as_user timeout 1800 gjs -m "$file" 2>"$logs/$1.err"
}

# The result is the last line of the snippet's output that is a JSON object:
# processes the modules start, such as `waydroid session start`, write to the
# same output (`[gbinder] Service manager /dev/binder has appeared`).
json() { # output, python expression over d
    python3 -c '
import json, sys
line = [l for l in sys.argv[1].splitlines() if l.startswith("{")][-1]
d = json.loads(line)
print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null
}

expected_bridge() {
    case "$(sed -n 's/^vendor_id[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n1)" in
        GenuineIntel) echo libhoudini.so ;;
        *)            echo libndk_translation.so ;;
    esac
}

# what an install must leave behind; used after both installs
check_installed() { # suffix
    local s="$1" version bridge
    version="$(cat "$STAMP" 2>/dev/null)"
    [[ "$version" =~ ^(11|13)$ ]] && ok "stamp$s" || fail "stamp$s" "stamp holds '${version}'"

    [[ "$(systemctl is-enabled "$CONTAINER" 2>&1)" == enabled && "$(systemctl is-active "$CONTAINER")" == active ]] \
        && ok "container$s" || fail "container$s" "$CONTAINER is $(systemctl is-enabled "$CONTAINER" 2>&1)/$(systemctl is-active "$CONTAINER")"

    [[ "$(systemctl is-enabled "$TIMER" 2>&1)" == enabled ]] \
        && ok "timer$s" || fail "timer$s" "$TIMER is $(systemctl is-enabled "$TIMER" 2>&1)"

    if firewall-cmd --permanent --zone=trusted --list-interfaces 2>/dev/null | grep -qw waydroid0; then
        ok "firewall$s"
    else
        fail "firewall$s" "waydroid0 is not in the permanent trusted zone"
    fi

    [[ -f "$ENTRY" ]] && ok "entry$s" || fail "entry$s" "no $ENTRY"

    bridge="$(cat /var/lib/waydroid/waydroid.cfg /var/lib/waydroid/waydroid_base.prop 2>/dev/null |
        sed -n 's/^ro\.dalvik\.vm\.native\.bridge[[:space:]]*=[[:space:]]*//p' | tail -n1)"
    [[ "$bridge" == "$(expected_bridge)" ]] && ok "translation$s" \
        || fail "translation$s" "native bridge is '$bridge', expected $(expected_bridge) for this CPU"

    # the machine's virtio GPU cannot render Android in hardware: install must
    # have switched it to software rendering, or Android never boots here
    if [[ "$("$CONTROL" rendering)" == software ]]; then
        local gralloc egl
        gralloc="$(sed -n 's/^ro\.hardware\.gralloc[[:space:]]*=[[:space:]]*//p' /var/lib/waydroid/waydroid.cfg | tail -n1)"
        egl="$(sed -n 's/^ro\.hardware\.egl[[:space:]]*=[[:space:]]*//p' /var/lib/waydroid/waydroid.cfg | tail -n1)"
        [[ "$gralloc" == default && "$egl" == swiftshader ]] && ok "software-rendering$s" \
            || fail "software-rendering$s" "rendering is software, but waydroid.cfg has gralloc='$gralloc' egl='$egl'"
    fi

    if find /var/lib/waydroid/overlay -iname '*GmsCore*' 2>/dev/null | grep -q .; then
        ok "microg$s"
    else
        fail "microg$s" "no GmsCore in /var/lib/waydroid/overlay"
    fi
}

# --- 1. a machine without Android -------------------------------------------
problems=""
[[ -e "$STAMP" ]] && problems+="stamp exists; "
[[ "$(systemctl is-enabled "$TIMER" 2>&1)" == disabled ]] || problems+="$TIMER is $(systemctl is-enabled "$TIMER" 2>&1); "
systemctl is-active -q "$TIMER" && problems+="$TIMER is active; "
[[ "$(systemctl is-enabled "$CONTAINER" 2>&1)" == disabled ]] || problems+="$CONTAINER is $(systemctl is-enabled "$CONTAINER" 2>&1); "
systemctl is-active -q "$CONTAINER" && problems+="$CONTAINER is active; "
[[ -e "$ENTRY" ]] && problems+="$ENTRY exists; "
grep -qx 'NoDisplay=true' /usr/share/applications/Waydroid.desktop || problems+="the package's Waydroid entry is not hidden; "
[[ -z "$problems" ]] && ok clean || fail clean "$problems"

if out="$(/usr/lib/borshevik/waydroid_script/venv/bin/python3 -c 'import tqdm, requests, InquirerPy' 2>&1)"; then
    ok waydroid-script
else
    fail waydroid-script "$out"
fi

rendering="$(as_user "$CONTROL" rendering 2>&1)"
[[ "$rendering" == hardware || "$rendering" == software ]] && ok "rendering ($rendering, as $user)" \
    || fail rendering "answered '$rendering'"

# --- 2. the dispatcher refuses what is not in its table ---------------------
out="$("$MODULES" prepare bogus 2>&1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" != *"::module"* && ! -e "$STAMP" ]]; then
    ok modules-refuse
else
    fail modules-refuse "exit $rc: $out"
fi

# --- 3. install as the App Manager does --------------------------------------
logged prepare "$MODULES" prepare android; rc=$?
if [[ "$rc" -eq 0 ]] && grep -qx '::module android' "$logs/prepare.log" \
    && grep -qx '::result android ok' "$logs/prepare.log"; then
    ok modules-prepare
else
    fail modules-prepare "exit $rc: $(tail_of prepare)"
fi

# --- 4. what the install left -------------------------------------------------
check_installed ""

# --- 5. the Image Manager's waydroid.js --------------------------------------
res="$(gjs_as_user image-manager "
import * as w from 'file:///usr/share/borshevik-image-manager/waydroid.js';
async function main() {
    const s = w.isInstalled();
    const image = w.readImage();
    const update = await w.checkForUpdate(image);
    const hardware = await w.hasHardwareRendering();
    return { s, image, update, hardware };
}")"
if [[ "$(json "$res" "d.get('s', {}).get('installed') is True and d['s']['version'] == open('$STAMP').read().strip() and (d['image'] or {}).get('systemTime', 0) > 0 and isinstance(d['update'].get('available'), bool) and isinstance(d['hardware'], bool)")" == True ]]; then
    ok "image-manager-js (update available: $(json "$res" "d['update']['available']"))"
else
    fail image-manager-js "${res:-no output} $(head -c 300 "$logs/image-manager.err")"
fi

# --- 6. the App Manager's android.js, as tester -------------------------------
res="$(gjs_as_user app-manager "
import { fetchJson } from 'file:///usr/share/borshevik-app-manager/net.js';
import * as a from 'file:///usr/share/borshevik-app-manager/android.js';
async function main() {
    const list = await fetchJson('https://borshevik.org/share/applications-v2.json');
    const apps = list.flatMap((c) => c.apps ?? []).filter((e) => e?.type === 'android' && a.isValid(e));
    const first = await a.installApps(apps, () => {}, null);
    const second = await a.installApps(apps, () => {}, null);
    return { ids: apps.map((e) => e.id), ready: a.isReady(), first, second };
}")"
if [[ "$(json "$res" "len(d['ids']) > 0 and d['ready'] and not d['first']['failed'] and len(d['first']['installed']) + len(d['first']['alreadyInstalled']) == len(d['ids'])")" == True ]]; then
    ok "app-manager-install ($(json "$res" "', '.join(d['ids'])"))"
else
    fail app-manager-install "${res:-no output} $(head -c 300 "$logs/app-manager.err")"
fi
if [[ "$(json "$res" "len(d['second']['alreadyInstalled']) == len(d['ids']) and not d['second']['installed'] and not d['second']['failed']")" == True ]]; then
    ok app-manager-already-installed
else
    fail app-manager-already-installed "second run: $(json "$res" "d.get('second')")"
fi
session_running && fail app-manager-session "the session android.js started is still running" \
    || ok app-manager-session

# --- 7. the update service's conditions ---------------------------------------
# Each ExecCondition of the unit is run on its own, so the session condition is
# tested whatever the machine's connection makes of the metered one.
mapfile -t conditions < <(systemctl cat "$SERVICE" | sed -n 's/^ExecCondition=//p')
metered="$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager \
    org.freedesktop.NetworkManager Metered 2>/dev/null | cut -c 3-)"
if [[ "${#conditions[@]}" -eq 2 ]]; then
    eval "${conditions[0]}"; rc=$?
    if [[ ( "$metered" == 2 || "$metered" == 4 ) && "$rc" -eq 0 ]] || [[ "$metered" != 2 && "$metered" != 4 && "$rc" -ne 0 ]]; then
        ok "update-metered (Metered=$metered, condition exit $rc)"
    else
        fail update-metered "Metered=$metered but the condition exited $rc"
    fi

    as_user setsid waydroid session start >"$logs/session.log" 2>&1 < /dev/null &
    if wait_session 180; then
        eval "${conditions[1]}" && fail update-session-skip "the condition lets an upgrade run during a session" \
            || ok update-session-skip
    else
        fail update-session-skip "no session after three minutes: $(tail -n 3 "$logs/session.log" | tr '\n' ' ')"
    fi
    as_user waydroid session stop >/dev/null 2>&1
    for _ in $(seq 20); do session_running || break; sleep 3; done
    sleep 5
    eval "${conditions[1]}" && ok update-session-idle || fail update-session-idle "the condition refuses with no session"
else
    fail update-conditions "expected two ExecCondition lines, found ${#conditions[@]}"
fi

since="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl start "$SERVICE"; rc=$?
result="$(systemctl show "$SERVICE" -p Result --value)"
skipped="$(journalctl -u "$SERVICE" --since "$since" -o cat | grep -c "exec-condition")"
if [[ "$rc" -eq 0 && "$result" == success ]]; then
    ok "update-service ($([[ "$skipped" -gt 0 ]] && echo skipped by a condition || echo ran))"
else
    fail update-service "start exit $rc, Result=$result"
fi

# --- 8. upgrade ------------------------------------------------------------------
logged upgrade "$CONTROL" upgrade; rc=$?
version="$(cat "$STAMP" 2>/dev/null)"
if [[ "$rc" -eq 0 && "$version" =~ ^(11|13)$ ]]; then
    ok upgrade
else
    fail upgrade "exit $rc, stamp '$version': $(tail_of upgrade)"
fi

# --- 9. remove as the Image Manager does, for tester ------------------------------
logged remove env PKEXEC_UID="$uid" "$CONTROL" remove; rc=$?
problems=""
[[ "$rc" -eq 0 ]] || problems+="exit $rc: $(tail_of remove); "
[[ -e "$STAMP" ]] && problems+="stamp left; "
[[ -e /var/lib/waydroid ]] && problems+="/var/lib/waydroid left; "
[[ -e "$ENTRY" ]] && problems+="$ENTRY left; "
[[ "$(systemctl is-enabled "$TIMER" 2>&1)" == disabled ]] || problems+="$TIMER still $(systemctl is-enabled "$TIMER" 2>&1); "
[[ "$(systemctl is-enabled "$CONTAINER" 2>&1)" == disabled ]] || problems+="$CONTAINER still $(systemctl is-enabled "$CONTAINER" 2>&1); "
systemctl is-active -q "$CONTAINER" && problems+="$CONTAINER still active; "
firewall-cmd --permanent --zone=trusted --list-interfaces 2>/dev/null | grep -qw waydroid0 && problems+="waydroid0 still trusted; "
[[ -e "$home/.local/share/waydroid" ]] && problems+="$user's ~/.local/share/waydroid left; "
ls "$home"/.local/share/applications/waydroid.*.desktop >/dev/null 2>&1 && problems+="$user's Android app launchers left; "
[[ -z "$problems" ]] && ok remove || fail remove "$problems"

# --- 10. install again, as the Image Manager does -----------------------------
logged install "$CONTROL" install; rc=$?
[[ "$rc" -eq 0 ]] && ok reinstall || fail reinstall "exit $rc: $(tail_of install)"
check_installed "-again"

# --- 11. nothing failed along the way ------------------------------------------
units="$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
[[ -z "$units" ]] && ok system-units || fail system-units "$units"

# Leave Android's interface open for the screenshot taken after the scenario.
as_user setsid waydroid show-full-ui >"$logs/full-ui.log" 2>&1 < /dev/null &
sleep 60

if [[ "$failed" -eq 0 ]]; then
    echo "all checks pass"
fi
exit "$failed"
