#!/usr/bin/env bash

set -ouex pipefail

# Enable only the NVIDIA driver repo (assumes RPM Fusion repos are already present but disabled)
dnf5 config-manager setopt rpmfusion-nonfree-nvidia.enabled=1

# Install NVIDIA components
dnf install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-settings
