#!/usr/bin/env bash

set -ouex pipefail

# Enable only the NVIDIA driver repo (assumes RPM Fusion repos are already present but disabled)
dnf config-manager --set-enabled rpmfusion-nonfree-nvidia-driver

# Install NVIDIA components
dnf install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-settings
