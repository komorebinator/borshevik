#!/usr/bin/env bash
set -euo pipefail

#dnf -y remove --no-autoremove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

NVVARS="/tmp/akmods-nvidia/rpms/kmods/nvidia-vars"
source "$NVVARS"
ver="${NVIDIA_AKMOD_VERSION}"

# Install drivers
#rpm-ostree -y install /tmp/akmods-nvidia/rpms/ublue-os/ublue-os-nvidia*.rpm
# enable negativo and container toolkit repo
#sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
#sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo
echo "Enable negativo17 repo"
curl -fsSL "https://negativo17.org/repos/fedora-nvidia.repo" -o "/etc/yum.repos.d/negativo17-fedora-nvidia.repo"

echo "Replace kernel"
rpm-ostree --experimental override replace /tmp/akmods-nvidia/kernel-rpms/kernel-*.rpm

echo "Install kmod ${ver}"
rpm-ostree -y install /tmp/akmods-nvidia/rpms/kmods/kmod-nvidia*.rpm \
  "nvidia-kmod-common-${ver}"* \
  "nvidia-modprobe-${ver}"*

echo "Install userspace ${ver}"
rpm-ostree -y install \
  "nvidia-driver-${ver}*" \
  "nvidia-driver-libs-${ver}*" \
  "nvidia-settings-${ver}*" \
  "nvidia-driver-cuda-${ver}*" \
  libva-nvidia-driver
#  nvidia-container-toolkit