#!/bin/bash

set -euo pipefail

NEEDED_ARGS=("preempt=full")
if rpm -q kmod-nvidia >/dev/null 2>&1; then
    NEEDED_ARGS+=("nvidia-drm.modeset=1" "modprobe.blacklist=nouveau")
fi

CURRENT_KARGS=$(bootctl status | awk '/options:/ {$1=""; print substr($0,2)}')
MISSING_ARGS=()

for arg in "${NEEDED_ARGS[@]}"; do
    if [[ "$CURRENT_KARGS" != *"$arg"* ]]; then
        MISSING_ARGS+=("$arg")
    fi
done

# --- Nothing to do ---
if [ "${#MISSING_ARGS[@]}" -eq 0 ]; then
    exit 0
    echo "Nothing to do";
fi

plymouth display-message --text="Setting kernel arguments, please wait"

# --- Apply all at once ---
echo "Adding missing kernel args: ${MISSING_ARGS[*]}"
rpm-ostree kargs --append-if-missing "${MISSING_ARGS[@]}"

# --- Reboot to apply ---
echo "Kernel arguments updated. Rebooting..."
plymouth display-message --text="Kernel arguments updated. Rebooting."
systemctl reboot
