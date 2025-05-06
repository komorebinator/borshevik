#!/usr/bin/env bash
set -euo pipefail

NEEDED_ARGS=("preempt=full")
REMOVE_ARGS=()

if rpm -q akmod-nvidia >/dev/null 2>&1; then
    NEEDED_ARGS+=("nvidia-drm.modeset=1" "modprobe.blacklist=nouveau")
else
    # If akmod-nvidia is not present, remove these args if present
    [[ $(</proc/cmdline) == *"nvidia-drm.modeset=1"* ]] && REMOVE_ARGS+=("nvidia-drm.modeset=1")
    [[ $(</proc/cmdline) == *"modprobe.blacklist=nouveau"* ]] && REMOVE_ARGS+=("modprobe.blacklist=nouveau")
fi

CURRENT_KARGS=$(</proc/cmdline)
MISSING_ARGS=()

for arg in "${NEEDED_ARGS[@]}"; do
    if [[ "$CURRENT_KARGS" != *"$arg"* ]]; then
        MISSING_ARGS+=("$arg")
    fi
done

if [ ${#MISSING_ARGS[@]} -eq 0 ] && [ ${#REMOVE_ARGS[@]} -eq 0 ]; then
    echo "Nothing to do"
    exit 0
fi

plymouth display-message --text="Setting kernel arguments, please wait"

if [ ${#MISSING_ARGS[@]} -gt 0 ]; then
    echo "Adding missing kernel args: ${MISSING_ARGS[*]}"
    rpm-ostree kargs --append-if-missing "${MISSING_ARGS[@]}"
fi

if [ ${#REMOVE_ARGS[@]} -gt 0 ]; then
    echo "Removing kernel args: ${REMOVE_ARGS[*]}"
    rpm-ostree kargs --delete "${REMOVE_ARGS[@]}"
fi

plymouth display-message --text="Rebooting"
echo "Rebooting"
systemctl reboot
