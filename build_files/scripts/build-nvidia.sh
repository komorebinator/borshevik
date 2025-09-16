#!/usr/bin/env bash
set -oue pipefail

#KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"

# Add RPM Fusion repositories
#dnf5 install -y \
  #https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  #https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install NVIDIA driver packages
#rpm-ostree install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings kernel-devel kernel-headers
#akmods --force --kernels "$KVER"

curl -o /etc/yum.repos.d/fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo

rpm-ostree install nvidia-driver nvidia-settings

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
akmods --akmod nvidia --kernels "$KVER" --force
