#!/usr/bin/env bash
# The app-folders scenario's checks, run inside the test VM as root after
# tester's first login and the image checks. See
# @ShellCustomizations#defaults#vm-scenario in spec/.
set -u

user=tester
uid="$(id -u "$user" 2>/dev/null)" || { echo "FAIL app-folders-setup: no user $user"; exit 1; }
home="$(getent passwd "$user" | cut -d: -f6)"

runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" python3 - <<'PY'
import ast, glob, os, subprocess, sys
from configparser import ConfigParser

failed = False
def ok(name): print(f"ok app-folders-{name}")
def fail(name, why):
    global failed
    print(f"FAIL app-folders-{name}: {why}"); failed = True

def strv(text):
    text = text.strip()
    return [] if text in ("@as []", "") else list(ast.literal_eval(text))

def gget(schema, key):
    return subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True).stdout

# 1. tester's folder list is the image's: GNOME Shell writes its own one at a
#    login that finds the key empty, and an account's own list hides the image's
mine = strv(gget("org.gnome.desktop.app-folders", "folder-children"))
image = strv(subprocess.run(["dconf", "read", "-d", "/org/gnome/desktop/app-folders/folder-children"],
                            capture_output=True, text=True).stdout)
if mine and mine == image:
    ok(f"image-list ({len(mine)} folders)")
else:
    fail("image-list", f"tester has {mine}, the image sets {image}")

# the launchers GNOME shows in the grid
dirs = ["/usr/share/applications", "/usr/local/share/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
        os.path.expanduser("~/.local/share/applications")]
shown = {}
for d in dirs:
    for path in glob.glob(f"{d}/*.desktop"):
        cp = ConfigParser(interpolation=None, strict=False)
        try:
            cp.read(path, encoding="utf-8")
            e = cp["Desktop Entry"]
        except Exception:
            continue
        if e.get("NoDisplay", "false") == "true" or e.get("Hidden", "false") == "true":
            continue
        only = [x for x in e.get("OnlyShowIn", "").split(";") if x]
        if only and "GNOME" not in only:
            continue
        if "GNOME" in e.get("NotShowIn", "").split(";"):
            continue
        shown[os.path.basename(path)] = {x for x in e.get("Categories", "").split(";") if x}

# 2. every folder it names is defined, and what each holds here
for fid in mine:
    schema = f"org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/{fid}/"
    name = ast.literal_eval(gget(schema, "name").strip() or "''")
    if not name:
        fail(f"defined-{fid}", "no name")
        continue
    apps = set(strv(gget(schema, "apps")))
    cats = set(strv(gget(schema, "categories")))
    excluded = set(strv(gget(schema, "excluded-apps")))
    held = sorted(a for a, c in shown.items() if a not in excluded and (a in apps or c & cats))
    ok(f"defined-{fid} ({name}): {len(held)} apps here{': ' + ' '.join(held) if held else ', so hidden'}")

print("all checks pass" if not failed else "some checks failed")
sys.exit(1 if failed else 0)
PY
result=$?

# Opens the app grid for the scenario's screenshot: Escape, for the welcome
# dialog GNOME Shell shows at a first login, then Super+A, on a virtual
# keyboard, since GNOME Shell takes no such request over D-Bus from an
# ordinary client.
python3 - <<'PY' || echo "note: could not open the app grid for the screenshot"
import fcntl, os, struct, time
EV_SYN, EV_KEY, KEY_ESC, KEY_LEFTMETA, KEY_A = 0, 1, 1, 125, 30
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
for key in (KEY_ESC, KEY_LEFTMETA, KEY_A):
    fcntl.ioctl(fd, UI_SET_KEYBIT, key)
# struct uinput_user_dev: name, input_id (bus, vendor, product, version),
# ff_effects_max, then four absolute-axis arrays of 64 ints
os.write(fd, struct.pack("80sHHHHI", b"borshevik-test-keyboard", 0x06, 1, 1, 1, 0) + bytes(4 * 64 * 4))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(2)  # for libinput to add the device to the seat
def emit(kind, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, kind, code, value))
def press(*codes):
    for code, value in [(c, 1) for c in codes] + [(c, 0) for c in reversed(codes)]:
        emit(EV_KEY, code, value)
        emit(EV_SYN, 0, 0)
        time.sleep(0.1)
press(KEY_ESC)
time.sleep(2)  # for the dialog to close
press(KEY_LEFTMETA, KEY_A)
time.sleep(0.5)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
PY
sleep 3
exit "$result"
