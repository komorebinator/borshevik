#!/usr/bin/env bash
set -euo pipefail

NEEDED_ARGS=("preempt=full")
if rpm -q kmod-nvidia >/dev/null 2>&1; then
    NEEDED_ARGS+=("nvidia-drm.modeset=1" "modprobe.blacklist=nouveau")
fi

CURRENT_KARGS=$(</proc/cmdline)
MISSING_ARGS=()

for arg in "${NEEDED_ARGS[@]}"; do
    if [[ "$CURRENT_KARGS" != *"$arg"* ]]; then
        MISSING_ARGS+=("$arg")
    fi
done

# --- Nothing to do ---
if [ "${#MISSING_ARGS[@]}" -eq 0 ]; then
    echo "Nothing to do"
    exit 0
fi

plymouth display-message --text="Setting kernel arguments, please wait"

# --- Apply all missing args ---
echo "Adding missing kernel args: ${MISSING_ARGS[*]}"
rpm-ostree kargs --append-if-missing "${MISSING_ARGS[@]}"

echo "Rebooting"
systemctl reboot
