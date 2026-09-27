#!/usr/bin/env bash
# Installs one ISO of a build-iso run into a fresh VM, for the author to try.
# See @BorshevikWorkflow#try-iso in spec/. Runs on the host; needs gh and the
# GNOME Boxes flatpak, whose qemu and UEFI firmware it uses.
set -euo pipefail

repo=komorebinator/borshevik
usage() { echo "usage: $0 [--boot] <run id | latest> <borshevik | borshevik-nvidia>" >&2; exit 2; }

boot_only=0
if [ "${1:-}" = "--boot" ]; then boot_only=1; shift; fi
[ $# -eq 2 ] || usage
run_id=$1
variant=$2
case "$variant" in borshevik|borshevik-nvidia) ;; *) usage ;; esac

command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
flatpak info org.gnome.Boxes >/dev/null 2>&1 || { echo "the GNOME Boxes flatpak (org.gnome.Boxes) is not installed" >&2; exit 1; }

if [ "$run_id" = latest ]; then
    run_id=$(gh run list -R "$repo" -w build-iso.yml -s success -L 1 --json databaseId -q '.[0].databaseId')
    [ -n "$run_id" ] || { echo "no successful build-iso run found" >&2; exit 1; }
    echo "latest successful build-iso run: $run_id"
fi

dir="${XDG_CACHE_HOME:-$HOME/.cache}/borshevik-iso/$run_id/$variant"
mkdir -p "$dir"
cd "$dir"

qemu() { flatpak run --filesystem="$dir" --command="$1" org.gnome.Boxes "${@:2}"; }

iso=$(ls -- *.iso 2>/dev/null | head -1 || true)
if [ -z "$iso" ]; then
    echo "downloading the $variant ISO of run $run_id..."
    gh run download "$run_id" -R "$repo" --pattern "$variant-stable-*" -D "$dir/download"
    find "$dir/download" -type f -exec mv -t "$dir" {} +
    rm -rf "$dir/download"
    iso=$(ls -- *.iso | head -1)
fi
sha256sum -c "$iso-CHECKSUM"

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
