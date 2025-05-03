#!/usr/bin/env bash
set -euo pipefail

FLAG_FILE="/var/lib/app-choice-subscription/reset-kargs.done"

# Skip if already run
[ -f "$FLAG_FILE" ] && exit 0

# Apply base kargs
rpm-ostree kargs --append-if-missing preempt=full

# NVIDIA-specific
if rpm -q kmod-nvidia > /dev/null 2>&1; then
    rpm-ostree kargs --append-if-missing nvidia-drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1
fi

# Set done flag
mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"

# Reboot to apply
systemctl reboot
