#!/usr/bin/env bash
# Runs a Borshevik image in a throwaway VM and checks it with nobody at the screen.
# See @BorshevikWorkflow#test-image-in-vm in spec/. Runs on the host; needs ssh, skopeo, python3,
# podman through run0 (for `base` only) and the GNOME Boxes flatpak's qemu and firmware.
set -euo pipefail

usage() {
    echo "usage: $0 setup [image]          make the test machine's base disk (default image: :latest)" >&2
    echo "       $0 run [--keep] [--scenarios auto|all|none|<name>[,<name>...]] [image]" >&2
    echo "                                  try an image (default: :latest); --scenarios picks" >&2
    echo "                                  the tests/scenarios to run with the checks" >&2
    echo "                                  (default auto: those whose paths this branch changes" >&2
    echo "                                  against origin/main)" >&2
    exit 2
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/borshevik-vm"
key="$cache/id_ed25519"
base="$cache/base.qcow2"
mkdir -p "$cache"

die() { echo "$*" >&2; exit 1; }
boxes() { flatpak run --filesystem="$cache" --command="$1" org.gnome.Boxes "${@:2}"; }

ensure_key() {
    [[ -f "$key" ]] || ssh-keygen -q -t ed25519 -N "" -C "borshevik test VMs" -f "$key"
}

cmd_setup() {
    local image="${1:-ghcr.io/komorebinator/borshevik:latest}"
    local build="$cache/base-build"
    local policy="$repo_root/build_files/root/etc/containers/policy.json"
    ensure_key
    rm -rf "$build"
    mkdir -p "$build"
    cat >"$build/config.toml" <<EOF
[[customizations.user]]
name = "root"
key = "$(cat "$key.pub")"

[customizations.kernel]
append = "systemd.wants=sshd.service"

[[customizations.filesystem]]
mountpoint = "/"
minsize = "40 GiB"
EOF
    echo "building the base disk from $image; this asks for your password once and takes a while"
    # The builder's working store goes next to its output, under the invoking user's home:
    # root's own /var is where root's container storage lives, and too small for both.
    mkdir -p "$build/store"
    run0 sh -c "set -e
        trap \"podman rmi '$image' quay.io/centos-bootc/bootc-image-builder:latest >/dev/null 2>&1 || true
              chown -R $(id -u):$(id -g) '$build'\" EXIT
        podman pull '$image'
        podman pull --signature-policy '$policy' quay.io/centos-bootc/bootc-image-builder:latest
        podman run --rm --privileged --security-opt label=type:unconfined_t \
            -v '$build/config.toml':/config.toml:ro -v '$build':/output -v '$build/store':/store \
            -v /var/lib/containers/storage:/var/lib/containers/storage \
            quay.io/centos-bootc/bootc-image-builder:latest \
            --type qcow2 --rootfs btrfs '$image'"
    [[ -f "$build/qcow2/disk.qcow2" ]] || die "the builder produced no disk"
    mv "$build/qcow2/disk.qcow2" "$base"
    rm -rf "$build"
    echo "base disk: $base"
}

# --- run -------------------------------------------------------------------------------

qmp() { # command...
    python3 - "$dir/qmp.sock" "$@" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
f = s.makefile("rw")
f.readline()
f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush(); f.readline()
cmd = {"execute": sys.argv[2]}
if len(sys.argv) > 3:
    cmd["arguments"] = json.loads(sys.argv[3])
f.write(json.dumps(cmd) + "\n"); f.flush()
while True:
    r = json.loads(f.readline())
    if "return" in r or "error" in r:
        print(json.dumps(r)); break
PY
}

guest_once() {
    ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=yes -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=30 \
        root@127.0.0.1 "$@"
}

# Retries when ssh itself fails (255): the forwarded port resets a connection now and then
# right after boot. Only for commands that are safe to run twice.
guest() {
    local rc
    for _ in 1 2 3 4 5; do
        guest_once "$@" && return 0 || rc=$?
        [[ "$rc" -ne 255 ]] && return "$rc"
        sleep 3
    done
    return 255
}

wait_ssh() { # previous boot id, or empty
    local old="$1" id
    for _ in $(seq 60); do
        kill -0 "$qemu_pid" 2>/dev/null || die "the VM stopped"
        id="$(guest cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
        [[ -n "$id" && "$id" != "$old" ]] && return 0
        sleep 5
    done
    die "no SSH from the VM after five minutes"
}

settle() { # wait for a boot to finish, following any reboot that happens meanwhile
    local id now
    for _ in 1 2 3; do
        id="$(guest cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
        guest "timeout 300 systemctl is-system-running --wait >/dev/null" || true
        now="$(guest cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
        [[ -n "$id" && "$now" == "$id" ]] && return 0
        wait_ssh "$id"   # it rebooted, e.g. setup-kargs on a base's first boot
    done
    die "the VM keeps rebooting"
}

reboot_guest() {
    local id
    id="$(guest cat /proc/sys/kernel/random/boot_id)"
    guest_once systemctl reboot || true
    wait_ssh "$id"
    settle
}

power_off() {
    [[ -n "${qemu_pid:-}" ]] || return 0
    qmp quit >/dev/null 2>&1 || true
    wait "$qemu_pid" 2>/dev/null || true
}

screenshot() { # [name], default screen
    local name="${1:-screen}"
    qmp screendump "{\"filename\": \"$dir/$name.ppm\"}" >/dev/null
    python3 - "$dir/$name.ppm" "$dir/$name.png" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
fields, pos = [], 0
while len(fields) < 4:  # P6, width, height, maxval, skipping comments
    while data[pos:pos+1].isspace(): pos += 1
    if data[pos:pos+1] == b"#":
        pos = data.index(b"\n", pos); continue
    end = pos
    while not data[end:end+1].isspace(): end += 1
    fields.append(data[pos:end]); pos = end
pos += 1
w, h = int(fields[1]), int(fields[2])
rows = b"".join(b"\0" + data[pos + y*w*3: pos + (y+1)*w*3] for y in range(h))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
open(sys.argv[2], "wb").write(png)
PY
    rm -f "$dir/$name.ppm"
}

# --- scenarios -----------------------------------------------------------------------

scenarios_dir="$repo_root/tests/scenarios"

all_scenarios() {
    local d
    for d in "$scenarios_dir"/*/; do
        [[ -f "$d/guest.sh" ]] && basename "$d"
    done
}

# The first file this branch changes against origin/main that a scenario's paths match.
scenario_trigger() { # name
    local specs=() line
    while IFS= read -r line; do
        line="${line%%#*}"; line="${line//[[:space:]]/}"
        [[ -n "$line" ]] && specs+=(":(glob)$line")
    done <"$scenarios_dir/$1/paths"
    [[ "${#specs[@]}" -gt 0 ]] || return 0
    git -C "$repo_root" diff --name-only origin/main...HEAD -- "${specs[@]}" | head -n1
}

# Prints the selected scenarios, one per line, and why each was picked on stderr.
select_scenarios() { # auto | all | none | name[,name...]
    local choice="$1" name file
    case "$choice" in
        none) return 0 ;;
        all) all_scenarios ;;
        auto)
            git -C "$repo_root" fetch -q origin main || die "cannot fetch origin/main to pick scenarios"
            for name in $(all_scenarios); do
                file="$(scenario_trigger "$name")"
                if [[ -n "$file" ]]; then
                    echo "scenario $name: this branch changes $file" >&2
                    echo "$name"
                fi
            done ;;
        *)
            for name in ${choice//,/ }; do
                [[ -f "$scenarios_dir/$name/guest.sh" ]] || die "no scenario '$name' in tests/scenarios"
                echo "$name"
            done ;;
    esac
}

cmd_run() {
    local keep=0 scenarios_choice=auto
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --keep) keep=1 ;;
            --scenarios) [[ -n "${2:-}" ]] || usage; scenarios_choice="$2"; shift ;;
            *) usage ;;
        esac
        shift
    done
    # picked before the machine starts, so an unknown name costs nothing
    local scenarios
    scenarios="$(select_scenarios "$scenarios_choice")"
    [[ -n "$scenarios" ]] || echo "no scenarios selected"
    local image="${1:-ghcr.io/komorebinator/borshevik:latest}"
    [[ -f "$base" ]] || die "no base disk; run: $0 setup"
    ensure_key

    dir="$cache/runs/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir"
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
    local digest
    digest="$(skopeo inspect --format '{{.Digest}}' "docker://$image")"
    echo "trying $image ($digest) in $dir"

    boxes qemu-img create -q -f qcow2 -b "$base" -F qcow2 "$dir/disk.qcow2"
    boxes cp /app/share/qemu/edk2-i386-vars.fd "$dir/vars.fd"
    boxes qemu-system-x86_64 \
        -name "borshevik-test-vm" \
        -enable-kvm -machine q35 -cpu host -smp 4 -m 6144 \
        -drive if=pflash,format=raw,readonly=on,file=/app/share/qemu/edk2-x86_64-code.fd \
        -drive "if=pflash,format=raw,file=$dir/vars.fd" \
        -drive "file=$dir/disk.qcow2,if=virtio" \
        -device virtio-vga -display none \
        -spice "unix=on,addr=$dir/spice.sock,disable-ticketing=on" \
        -qmp "unix:$dir/qmp.sock,server=on,wait=off" \
        -device qemu-xhci -device usb-tablet \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22" \
        -serial "file:$dir/serial.log" >"$dir/qemu.log" 2>&1 &
    qemu_pid=$!
    [[ "$keep" -eq 1 ]] || trap power_off EXIT

    wait_ssh ""
    settle
    local booted
    booted="$(guest "rpm-ostree status --json" | python3 -c '
import json, sys
b = [d for d in json.load(sys.stdin)["deployments"] if d.get("booted")][0]
print(b.get("container-image-reference-digest", ""), b.get("container-image-reference", ""))')"
    # a base straight from bootc-image-builder boots ostree-unverified-registry:
    if [[ "$booted" != "$digest ostree-image-signed:docker://$image" ]]; then
        echo "rebasing to $image"
        guest_once "rpm-ostree rebase ostree-image-signed:docker://$image" >"$dir/rebase.log" 2>&1 \
            || die "rebase failed; see $dir/rebase.log"
    fi

    # tester is logged in by GDM itself, with GDM held back 70 s after boot: a user's first
    # login, late enough that the user manager's boot-relative timers fire at once
    guest 'set -e
        id tester >/dev/null 2>&1 || useradd -m -c Tester tester
        echo tester:borshevik-test | chpasswd
        # like the accounts the author tries images with: App Manager already done
        home="$(getent passwd tester | cut -d: -f6)"
        runuser -u tester -- mkdir -p "$home/.local/state/borshevik"
        runuser -u tester -- touch "$home/.local/state/borshevik/app-manager-first-run.done"
        conf=/etc/gdm/custom.conf
        touch "$conf"
        grep -q "^\[daemon\]" "$conf" || printf "[daemon]\n" >>"$conf"
        sed -i "/^TimedLogin/d; /^AutomaticLogin/d; /^InitialSetupEnable/d" "$conf"
        sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=tester\nInitialSetupEnable=false" "$conf"
        mkdir -p /etc/systemd/system/gdm.service.d
        printf "[Service]\nExecStartPre=/usr/bin/sleep 70\nTimeoutStartSec=150\n" >/etc/systemd/system/gdm.service.d/zz-test-late-login.conf'
    # a scenario whose case is a state tester's login must start from sets it up now
    local name
    for name in $scenarios; do
        [[ -f "$scenarios_dir/$name/prepare.sh" ]] || continue
        echo "preparing scenario $name"
        guest_once "bash -s" <"$scenarios_dir/$name/prepare.sh" >"$dir/prepare-$name.log" 2>&1 \
            || die "scenario $name's prepare.sh failed; see $dir/prepare-$name.log"
    done
    reboot_guest

    echo "waiting for tester's session"
    local up=0
    for _ in $(seq 60); do
        if guest 'loginctl list-sessions --no-legend | grep -q " tester " && pgrep -u tester -x gnome-shell >/dev/null'; then
            up=1; break
        fi
        sleep 5
    done
    [[ "$up" -eq 1 ]] || echo "tester has no session after five minutes; checking anyway"
    sleep 30

    local result
    set +e
    guest_once "bash -s -- $digest" <"$repo_root/tests/image-checks.sh" | tee "$dir/report.txt"
    result="${PIPESTATUS[0]}"
    set -e
    screenshot
    echo "screenshot: $dir/screen.png"

    # Scenarios come after the checks, so nothing they install or change can affect them.
    local rc
    for name in $scenarios; do
        echo "== scenario $name" | tee -a "$dir/report.txt"
        set +e
        guest_once "bash -s" <"$scenarios_dir/$name/guest.sh" | tee -a "$dir/report.txt"
        rc="${PIPESTATUS[0]}"
        set -e
        [[ "$rc" -eq 0 ]] || result=1
        screenshot "screen-$name"
        echo "screenshot: $dir/screen-$name.png"
        mkdir -p "$dir/scenario-$name"
        guest "tar -C /var/tmp/scenario-$name -cf - . 2>/dev/null" | tar -xf - -C "$dir/scenario-$name" 2>/dev/null || true
    done

    if [[ "$keep" -eq 1 ]]; then
        echo "left running: ssh -o IdentitiesOnly=yes -i $key -p $port root@127.0.0.1"
        echo "              flatpak run --filesystem=$cache --command=spicy org.gnome.Boxes --uri=spice+unix://$dir/spice.sock"
    else
        power_off
        trap - EXIT
        rm -f "$dir/disk.qcow2" "$dir/vars.fd" "$dir/spice.sock" "$dir/qmp.sock"
    fi
    return "$result"
}

case "${1:-}" in
    setup) shift; cmd_setup "$@" ;;
    run)  shift; cmd_run "$@" ;;
    *)    usage ;;
esac
