#!/usr/bin/env bash
# Installs one ISO of a build-iso run, as borshevik.org serves it, into a fresh VM
# for the author to try. See @BorshevikWorkflow#try-iso in spec/. Runs on the host;
# needs gh, curl and the GNOME Boxes flatpak, whose qemu and UEFI firmware it uses.
set -euo pipefail

repo=komorebinator/borshevik
site=https://borshevik.org/iso
usage() { echo "usage: $0 [--boot] <run id | latest> <borshevik | borshevik-nvidia>" >&2; exit 2; }

boot_only=0
if [ "${1:-}" = "--boot" ]; then boot_only=1; shift; fi
[ $# -eq 2 ] || usage
run_id=$1
variant=$2
case "$variant" in borshevik|borshevik-nvidia) ;; *) usage ;; esac

command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is not installed" >&2; exit 1; }
flatpak info org.gnome.Boxes >/dev/null 2>&1 || { echo "the GNOME Boxes flatpak (org.gnome.Boxes) is not installed" >&2; exit 1; }

if [ "$run_id" = latest ]; then
    run_id=$(gh run list -R "$repo" -w build-iso.yml -s success -L 1 --json databaseId -q '.[0].databaseId')
    [ -n "$run_id" ] || { echo "no successful build-iso run found" >&2; exit 1; }
    echo "latest successful build-iso run: $run_id"
fi

dir="${XDG_CACHE_HOME:-$HOME/.cache}/borshevik-iso/$run_id/$variant"
mkdir -p "$dir"
cd "$dir"

iso=$(ls -- "$variant"-[0-9]*.iso 2>/dev/null | grep -E "^$variant-[0-9]{8}-[0-9]+\.iso$" || true)
if [ -z "$iso" ]; then
    names=$(gh run view "$run_id" -R "$repo" --log 2>/dev/null \
        | grep -oE "\b$variant-[0-9]{8}-[0-9]+\.iso\b" | sort -u || true)
    if [ "$(printf '%s' "$names" | grep -c .)" -ne 1 ]; then
        echo "expected exactly one $variant ISO name in the log of run $run_id, found: ${names:-none}" >&2
        echo "(a run from before unique ISO names has none)" >&2
        exit 1
    fi
    iso=$names
    echo "downloading $iso from borshevik.org..."
    if ! curl -fsS --retry 5 -o "$iso-CHECKSUM" "$site/$iso-CHECKSUM"; then
        echo "$site/$iso-CHECKSUM is not there: run publish-iso.yml for run $run_id first" >&2
        exit 1
    fi
    curl -fL --retry 5 --retry-all-errors -C - -o "$iso.part" "$site/$iso"
    mv "$iso.part" "$iso"
fi
sha256sum -c "$iso-CHECKSUM"

qemu() { flatpak run --filesystem="$dir" --command="$1" org.gnome.Boxes "${@:2}"; }

cdrom=()
if [ "$boot_only" -eq 1 ]; then
    [ -f disk.qcow2 ] || { echo "no installed disk in $dir; run without --boot first" >&2; exit 1; }
else
    rm -f disk.qcow2 vars.fd
    qemu qemu-img create -q -f qcow2 "$dir/disk.qcow2" 40G
    qemu cp /app/share/qemu/edk2-i386-vars.fd "$dir/vars.fd"
    cdrom=(-drive "file=$dir/$iso,media=cdrom,readonly=on")
fi

cat <<EOF

Trying $iso (run $run_id). Check that:
  1. the installer finishes$([ "$boot_only" -eq 1 ] && echo " (already done: booting the installed disk)")
  2. the installed system boots to GNOME and gets through first login
  3. \`rpm-ostree status\` shows ghcr.io/komorebinator/$variant:stable
Close the window when done. Boot the installed system again with: $0 --boot $run_id $variant

EOF

qemu qemu-system-x86_64 \
    -name "$iso" \
    -enable-kvm -machine q35 -cpu host -smp 4 -m 6144 \
    -drive if=pflash,format=raw,readonly=on,file=/app/share/qemu/edk2-x86_64-code.fd \
    -drive "if=pflash,format=raw,file=$dir/vars.fd" \
    -drive "file=$dir/disk.qcow2,if=virtio" \
    "${cdrom[@]}" \
    -device virtio-vga -display gtk \
    -device qemu-xhci -device usb-tablet \
    -nic user,model=virtio-net-pci
