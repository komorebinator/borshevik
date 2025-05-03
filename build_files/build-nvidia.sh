#!/usr/bin/env bash
set -oue pipefail

# Install NVIDIA drivers and control panel
rpm-ostree install \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-settings

# Add required kernel arguments for Wayland and NVIDIA support
rpm-ostree kargs \
    --append-if-missing=nvidia_drm.modeset=1 \
    --append-if-missing=module_blacklist=nouveau