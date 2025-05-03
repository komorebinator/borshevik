#!/usr/bin/env bash
set -oue pipefail

# Install NVIDIA drivers and control panel
rpm-ostree install \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-settings