#!/usr/bin/env bash
set -euo pipefail

NVVARS="/tmp/akmods-nvidia/rpms/kmods/nvidia-vars"
source "$NVVARS"
ver="${NVIDIA_AKMOD_VERSION}"
echo "Nvidia akmod version ${ver}"

#curl -fsSL --retry 5 -o /etc/yum.repos.d/negativo17-fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo
#curl -fsSL --retry 5 -o /etc/yum.repos.d/nvidia-container-toolkit.repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo

# Install drivers
rpm-ostree -y install /tmp/akmods-nvidia/rpms/ublue-os/ublue-os-nvidia*.rpm
# enable negativo and container toolkit repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo
# install kmods
rpm-ostree -y install /tmp/akmods-nvidia/rpms/kmods/kmod-nvidia*.rpm

# install userspace
rpm-ostree -y install \
  "nvidia-driver-${ver}*" \
  "nvidia-driver-libs-${ver}*" \
  "nvidia-settings-${ver}*" \
  "nvidia-driver-cuda-${ver}*" \
  nvidia-container-toolkit \
  libva-nvidia-driver

# disable negativo and container toolkit repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=0/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=0/' /etc/yum.repos.d/nvidia-container-toolkit.repo

echo "NVIDIA userspace ${ver} installed."
