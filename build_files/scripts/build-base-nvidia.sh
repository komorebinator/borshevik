#!/usr/bin/env bash
set -euo pipefail

echo "Akmods image"
find /tmp/akmods-nvidia

NVVARS="/tmp/akmods-nvidia/rpms/kmods/nvidia-vars"
source "$NVVARS"
full_ver="${NVIDIA_AKMOD_VERSION}"
ver="${full_ver%%-*}"  

echo "Enable negativo17 repo"
curl -fsSL "https://negativo17.org/repos/fedora-nvidia.repo" -o "/etc/yum.repos.d/negativo17-fedora-nvidia.repo"

echo "Install kmod ${ver}"
rpm-ostree -y install /tmp/akmods-nvidia/rpms/kmods/kmod-nvidia*.rpm \
  "nvidia-kmod-common-${ver}"* \
  "nvidia-modprobe-${ver}"*

echo "Install userspace ${ver}"
rpm-ostree -y install \
  "nvidia-driver-${ver}*" \
  "nvidia-driver-libs-${ver}*" \
  "nvidia-driver-libs-${ver}*.i686" \
  "nvidia-settings-${ver}*" \
  "nvidia-driver-cuda-${ver}*" \
  "nvidia-driver-cuda-libs-${ver}*.i686" \
  libva-nvidia-driver