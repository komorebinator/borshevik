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
CONFIG=/usr/share/borshevik/waydroid/config.json
CHANNEL=file:///var/lib/borshevik/waydroid-ota
BUSY=/run/borshevik/waydroid-busy
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

    if find /var/lib/waydroid/overlay -iname '*GmsCore*' -o -iname '*Phonesky*' 2>/dev/null | grep -q .; then
        fail "no-microg$s" "microG is in /var/lib/waydroid/overlay"
    else
        ok "no-microg$s"
    fi

    # waydroid.cfg follows Borshevik's channel and records the approved pair
    local problems
    problems="$(python3 - "$CONFIG" "$CHANNEL" <<'EOF'
import configparser, json, sys
images = json.load(open(sys.argv[1]))["images"]
channel = sys.argv[2]
cfg = configparser.ConfigParser()
cfg.read("/var/lib/waydroid/waydroid.cfg")
w = cfg["waydroid"]
want = {
    "system_ota": f"{channel}/system/lineage/waydroid_x86_64/{images['system']['romtype']}.json",
    "vendor_ota": f"{channel}/vendor/waydroid_x86_64/{images['vendor']['romtype']}.json",
    "system_datetime": str(images["system"]["datetime"]),
    "vendor_datetime": str(images["vendor"]["datetime"]),
}
print("; ".join(f"{k} is {w.get(k)!r}, not {v!r}" for k, v in want.items() if w.get(k) != v))
EOF
)"
    [[ -z "$problems" ]] && ok "approved-images$s" || fail "approved-images$s" "$problems"

    # config.json's properties in waydroid.cfg, from which Waydroid builds
    # Android's when a session starts
    problems=""
    while IFS='=' read -r key value; do
        grep -Eqx "${key//./\\.}[[:space:]]*=[[:space:]]*${value}" /var/lib/waydroid/waydroid.cfg \
            || problems+="${key}=${value} not in waydroid.cfg; "
    done < <(config_properties)
    [[ -z "$problems" ]] && ok "properties$s" || fail "properties$s" "$problems"

    [[ -f /var/lib/waydroid/overlay/system/etc/init/borshevik.rc && -f /var/lib/waydroid/overlay/system/etc/borshevik-defaults.sh ]] \
        && ok "first-boot$s" || fail "first-boot$s" "borshevik.rc or borshevik-defaults.sh missing from the overlay"

    [[ -s "$BUSY" ]] && fail "not-busy$s" "$BUSY still holds '$(cat "$BUSY")'" || ok "not-busy$s"
}

config_properties() {
    python3 -c 'import json, sys; [print(f"{k}={v}") for k, v in json.load(open(sys.argv[1]))["properties"].items()]' "$CONFIG"
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
if [[ "$(json "$res" "d.get('s', {}).get('installed') is True and d['s']['version'] == open('$STAMP').read().strip() and (d['image'] or {}).get('systemTime', 0) > 0 and (d['image'] or {}).get('vendorTime', 0) > 0 and d['update'].get('available') is False and isinstance(d['hardware'], bool)")" == True ]]; then
    ok image-manager-js
else
    fail image-manager-js "${res:-no output} $(head -c 300 "$logs/image-manager.err")"
fi

# --- 6. the App Manager's android.js, as tester -------------------------------
# An entry of its own rather than the live list's, which may hold no Android
# app: F-Droid's client, pinned. F-Droid moves old builds to its archive after
# a while; then pin the current one (its suggestedVersionCode, from
# https://f-droid.org/api/v1/packages/org.fdroid.fdroid).
res="$(gjs_as_user app-manager "
import * as a from 'file:///usr/share/borshevik-app-manager/android.js';
async function main() {
    const apps = [{
        type: 'android',
        id: 'org.fdroid.fdroid',
        name: 'F-Droid',
        url: 'https://f-droid.org/repo/org.fdroid.fdroid_1023052.apk',
        sha256: '985f5181d48bb6bafd54083a048b391271e0ab28385881cc41294fb01a222762'
    }].filter((e) => a.isValid(e));
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

# While a session runs: the GAPPS image's Google packages, and the ID to
# register the device with, once Android has had time to check in with Google.
android_session_checks() {
    local packages missing="" id rc
    for _ in $(seq 60); do
        [[ "$(as_user waydroid prop get sys.boot_completed 2>/dev/null)" == 1 ]] && break
        sleep 3
    done
    local problems="" key value got
    while IFS='=' read -r key value; do
        got="$(as_user waydroid prop get "$key" 2>/dev/null)"
        [[ "$got" == "$value" ]] || problems+="$key is '$got', not '$value'; "
    done < <(config_properties)
    [[ -z "$problems" ]] && ok android-properties || fail android-properties "$problems"

    # the first-boot service applies config.json's android_settings once
    for _ in $(seq 20); do
        [[ "$(as_user waydroid prop get persist.borshevik.defaults 2>/dev/null)" == 1 ]] && break
        sleep 3
    done
    problems=""
    while read -r namespace key value; do
        got="$(lxc-attach -P /var/lib/waydroid/lxc -n waydroid --clear-env -v PATH=/system/bin:/system/xbin \
            -- /system/bin/settings get "$namespace" "$key" 2>/dev/null | tr -d '\r')"
        [[ "$got" == "$value" ]] || problems+="$namespace $key is '$got', not '$value'; "
    done < <(python3 -c 'import json, sys
for ns, kv in json.load(open(sys.argv[1])).get("android_settings", {}).items():
    for k, v in kv.items(): print(ns, k, v)' "$CONFIG")
    [[ -z "$problems" ]] && ok android-settings || fail android-settings "$problems"

    # every package, not `waydroid app list`, which shows only those with a
    # launcher, and Google Play Services has none
    packages="$(lxc-attach -P /var/lib/waydroid/lxc -n waydroid --clear-env -v PATH=/system/bin:/system/xbin \
        -- /system/bin/pm list packages 2>/dev/null | tr -d '\r')"
    for p in com.google.android.gms com.google.android.gsf com.android.vending; do
        grep -qx "package:$p" <<<"$packages" || missing+="$p "
    done
    [[ -z "$missing" ]] && ok google-packages || fail google-packages "not in Android: $missing"

    local status
    for _ in $(seq 20); do
        status="$(env PKEXEC_UID="$uid" "$CONTROL" google 2>"$logs/google.err")"; rc=$?
        [[ "$rc" -eq 3 ]] || break
        sleep 6
    done
    id="$(sed -n 's/^android_id=//p' <<<"$status")"
    if [[ "$rc" -eq 0 && "$id" =~ ^[0-9]+$ ]] && grep -qx 'google_account=no' <<<"$status"; then
        ok "google ($id, no account)"
    elif [[ "$rc" -eq 3 ]]; then
        ok "google (not checked in with Google yet)"
    else
        fail google "exit $rc, printed '$status': $(head -c 300 "$logs/google.err")"
    fi
}

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
        android_session_checks
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
# refused while another operation holds the busy lock, having changed nothing
cfg_before="$(sha256sum /var/lib/waydroid/waydroid.cfg)"
flock "$BUSY" sleep 60 &
holder=$!
sleep 2
logged upgrade-busy "$CONTROL" upgrade; rc=$?
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [[ "$rc" -eq 4 && "$(sha256sum /var/lib/waydroid/waydroid.cfg)" == "$cfg_before" && -f "$STAMP" ]]; then
    ok upgrade-busy
else
    fail upgrade-busy "exit $rc (expected 4), waydroid.cfg $([[ "$(sha256sum /var/lib/waydroid/waydroid.cfg)" == "$cfg_before" ]] && echo unchanged || echo changed): $(tail_of upgrade-busy)"
fi

logged upgrade "$CONTROL" upgrade; rc=$?
version="$(cat "$STAMP" 2>/dev/null)"
if [[ "$rc" -eq 0 && "$version" =~ ^(11|13)$ ]]; then
    ok upgrade
else
    fail upgrade "exit $rc, stamp '$version': $(tail_of upgrade)"
fi

# as on a machine installed from another channel: a vendor build other than
# the approved one recorded; upgrade must bring the approved one back
approved_vendor="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["images"]["vendor"]["datetime"])' "$CONFIG")"
sed -i 's/^vendor_datetime = .*/vendor_datetime = 1790542319/' /var/lib/waydroid/waydroid.cfg
logged upgrade-back "$CONTROL" upgrade; rc=$?
recorded="$(sed -n 's/^vendor_datetime = //p' /var/lib/waydroid/waydroid.cfg)"
if [[ "$rc" -eq 0 && "$recorded" == "$approved_vendor" ]] && grep -q "vendor image is not the approved one" "$logs/upgrade-back.log"; then
    ok upgrade-to-approved
else
    fail upgrade-to-approved "exit $rc, vendor_datetime '$recorded', approved $approved_vendor: $(tail_of upgrade-back)"
fi

# --- 9. remove as the Image Manager does, for tester ------------------------------
logged remove env PKEXEC_UID="$uid" "$CONTROL" remove; rc=$?
problems=""
[[ "$rc" -eq 0 ]] || problems+="exit $rc: $(tail_of remove); "
[[ -e "$STAMP" ]] && problems+="stamp left; "
[[ -e /var/lib/waydroid ]] && problems+="/var/lib/waydroid left; "
[[ -e /var/lib/borshevik/waydroid-ota ]] && problems+="/var/lib/borshevik/waydroid-ota left; "
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
