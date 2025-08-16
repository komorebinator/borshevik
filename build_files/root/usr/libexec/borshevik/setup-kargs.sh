#!/usr/bin/env bash
set -euo pipefail

NEEDED_ARGS=("preempt=full")
REMOVE_ARGS=()

# Parse current kernel command line into array
read -ra CMDLINE_ARGS <<<"$(</proc/cmdline)"

# Check for NVIDIA driver
if rpm -q nvidia-driver >/dev/null 2>&1; then
    NEEDED_ARGS+=("nvidia-drm.modeset=1" "modprobe.blacklist=nouveau" "modprobe.blacklist=nova_core" "rd.driver.blacklist=nova_core")
fi 

# Check which required args are missing
MISSING_ARGS=()
for needed in "${NEEDED_ARGS[@]}"; do
    found=0
    for existing in "${CMDLINE_ARGS[@]}"; do
        if [[ "$existing" == "$needed" ]]; then
            found=1
            break
        fi
    done
    [[ "$found" -eq 0 ]] && MISSING_ARGS+=("$needed")
done

# If nothing needs to be added or removed, exit early
if [ ${#MISSING_ARGS[@]} -eq 0 ] && [ ${#REMOVE_ARGS[@]} -eq 0 ]; then
    echo "Nothing to do"
    exit 0
fi

plymouth display-message --text="Setting kernel arguments, please wait"

# Consolidate into one rpm-ostree call
if [ ${#MISSING_ARGS[@]} -gt 0 ] || [ ${#REMOVE_ARGS[@]} -gt 0 ]; then
    echo "Modifying kernel args: add [${MISSING_ARGS[*]}], remove [${REMOVE_ARGS[*]}]"
    RPMFLAGS=()
    for arg in "${MISSING_ARGS[@]}"; do
        RPMFLAGS+=(--append="${arg}")
    done
    for arg in "${REMOVE_ARGS[@]}"; do
        RPMFLAGS+=(--delete="${arg}")
    done
    echo "Executing: rpm-ostree kargs ${RPMFLAGS[*]}"
    rpm-ostree kargs "${RPMFLAGS[@]}"
fi

plymouth display-message --text="Rebooting"

echo "Rebooting"
systemctl reboot
