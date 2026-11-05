#!/usr/bin/env bash
# The menu-grab scenario's checks, run inside the test VM as root after tester's
# login and the image checks: the gnome-shell crash the mutter patch fixes, brought
# about the way a user meets it. See
# @ImageBuild#build-borshevik-packages#mutter-implicit-grab#vm-scenario in spec/.
set -u

user=tester
uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL menu-grab-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"
as_user() {
    runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" WAYLAND_DISPLAY=wayland-0 "$@"
}
work="$(mktemp -d)"
log="$home/.cache/menu-grab-wayland.log"
cleanup() { pkill -u "$user" -x nautilus; rm -rf "$work" "$log"; }
trap cleanup EXIT

# An absolute pointer, like QEMU's tablet, and a keyboard, made through uinput:
# nothing inside the guest can move QEMU's own pointer. Commands, in order:
# move X Y | down [left|right] | up [left|right] | key NAME[+NAME...] | sleep S
cat >"$work/input.py" <<'PY'
import fcntl, os, struct, sys, time

EV_SYN, EV_KEY, EV_ABS, ABS_X, ABS_Y, AMAX = 0, 1, 3, 0, 1, 32767
BTN = {"left": 0x110, "right": 0x111, "middle": 0x112}
KEYS = {"super": 125, "esc": 1, "up": 103}

def IOW(nr, size): return (1 << 30) | (size << 16) | (ord("U") << 8) | nr
UI_DEV_CREATE, UI_DEV_DESTROY = (ord("U") << 8) | 1, (ord("U") << 8) | 2
UI_DEV_SETUP, UI_ABS_SETUP = IOW(3, 92), IOW(4, 28)
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = IOW(100, 4), IOW(101, 4), IOW(103, 4)

def device(name, keys, absolute):
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for k in keys:
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    if absolute:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
        for axis in (ABS_X, ABS_Y):
            fcntl.ioctl(fd, UI_SET_ABSBIT, axis)
            fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack("HxxiiiiII", axis, 0, 0, AMAX, 0, 0, 0))
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x06, 0x1234, 0x5678, 1, name.encode(), 0))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd

def emit(fd, *events):
    for t, c, v in events + ((EV_SYN, 0, 0),):
        os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))

w, h = map(int, sys.argv[1].split("x"))
args = sys.argv[2:]
ptr = device("Borshevik test pointer", BTN.values(), True)
kbd = device("Borshevik test keyboard", range(1, 256), False)
time.sleep(1.5)  # for libinput and GNOME to take both devices up
i = 0
while i < len(args):
    a = args[i]
    if a == "move":
        x, y = int(args[i + 1]), int(args[i + 2]); i += 2
        emit(ptr, (EV_ABS, ABS_X, x * AMAX // (w - 1)), (EV_ABS, ABS_Y, y * AMAX // (h - 1)))
    elif a in ("down", "up"):
        b = "left"
        if i + 1 < len(args) and args[i + 1] in BTN:
            b = args[i + 1]; i += 1
        emit(ptr, (EV_KEY, BTN[b], 1 if a == "down" else 0))
    elif a == "key":
        names = args[i + 1].split("+"); i += 1
        for n in names:
            emit(kbd, (EV_KEY, KEYS[n], 1))
        for n in reversed(names):
            emit(kbd, (EV_KEY, KEYS[n], 0))
    elif a == "sleep":
        time.sleep(float(args[i + 1])); i += 1
    else:
        sys.exit(f"unknown command {a}")
    time.sleep(0.05)
    i += 1
time.sleep(0.3)
for fd in (ptr, kbd):
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)
PY

# The screen in logical pixels: the current mode of the primary monitor over its scale
read -r W H < <(as_user gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState |
    python3 -c '
import re, sys
s = sys.stdin.read()
mode = re.search(r"\(\x27[^\x27]+\x27, (\d+), (\d+), [\d.]+, [\d.]+, \[[^\]]*\], \{[^}]*\x27is-current\x27: <true>", s)
lm = re.search(r"\[\((-?\d+), (-?\d+), ([\d.]+), uint32 \d+, true", s)
scale = float(lm.group(3)) if lm else 1.0
if mode:
    print(int(int(mode.group(1)) / scale), int(int(mode.group(2)) / scale))')
[[ -n "${H:-}" ]] || { echo "FAIL menu-grab-setup: no current mode in Mutter's DisplayConfig"; exit 1; }
input() { python3 "$work/input.py" "${W}x$H" "$@"; }
waitfor() { # pattern seconds: until Nautilus's log has a matching line
    local _
    for _ in $(seq $(($2 * 5))); do grep -qE "$1" "$log" && return 0; sleep 0.2; done
    return 1
}

# Nautilus, with its Wayland requests about popups logged, in a maximized window
pkill -u "$user" -x nautilus; sleep 1
runuser -u "$user" -- sh -c ": >'$log'"
as_user sh -c 'WAYLAND_DEBUG=1 nautilus --new-window 2>&1 |
    grep --line-buffered -E "xdg_popup|xdg_wm_base#[0-9]+\.get_xdg_surface" >"$0"' "$log" &
waitfor 'get_xdg_surface' 30 || { echo "FAIL menu-grab-setup: Nautilus opened no window"; exit 1; }
sleep 3
input key super+up sleep 1.5

# Its context menu, which takes a Wayland popup grab
opened=""
for try in 1 2 3; do
    input move $((W / 2 - 40)) $((H * 2 / 3 - 40)) sleep 0.3 move $((W / 2)) $((H * 2 / 3)) down right sleep 0.12 up right
    if waitfor 'xdg_popup#[0-9]+\.grab' 5; then opened=yes; break; fi
    input key esc sleep 1
done
[[ -n "$opened" ]] || { echo "FAIL menu-grab-setup: Nautilus opened no menu after 3 right clicks"; exit 1; }
sleep 1

# The press on Nautilus's own window, which closes the menu while the button is down,
# then the overview's grab on the whole stage before the release
shell="$(pgrep -u "$user" -x gnome-shell)"
since="$(date '+%Y-%m-%d %H:%M:%S')"
input move $((W / 4 + 50)) $((H / 2 + 50)) sleep 0.3 move $((W / 4)) $((H / 2)) down sleep 0.6 key super sleep 1 up sleep 3

failed=0
if grep -qE 'xdg_popup#[0-9]+\.destroy' "$log"; then
    echo "ok menu-grab-menu (opened with a grab, closed by Nautilus on the press)"
else
    echo "FAIL menu-grab-menu: Nautilus did not close its menu on the press, so the case was not reached"; failed=1
fi
now="$(pgrep -u "$user" -x gnome-shell)"
abort="$(journalctl --since "$since" -o cat _COMM=gnome-shell | grep -m1 -E 'clutter-[a-z-]+\.c:[0-9]+')"
if [[ -n "$shell" && "$now" == "$shell" && -z "$abort" ]]; then
    echo "ok menu-grab-shell (gnome-shell $shell survived)"
else
    echo "FAIL menu-grab-shell: gnome-shell was $shell, now ${now:-gone}${abort:+; $abort}"; failed=1
fi
[[ -z "$now" ]] || input key esc

[[ "$failed" -eq 0 ]] && echo "all checks pass"
exit "$failed"
