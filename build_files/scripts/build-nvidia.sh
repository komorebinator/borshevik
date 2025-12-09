#!/usr/bin/env bash
set -euo pipefail

#dnf -y remove --no-autoremove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

NVVARS="/tmp/akmods-nvidia/rpms/kmods/nvidia-vars"
source "$NVVARS"
ver="${NVIDIA_AKMOD_VERSION}"
echo "Nvidia akmod version ${ver}"

# Install drivers
#rpm-ostree -y install /tmp/akmods-nvidia/rpms/ublue-os/ublue-os-nvidia*.rpm
# enable negativo and container toolkit repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
#sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo
# install kmods
rpm-ostree -y install /tmp/akmods-nvidia/rpms/kmods/kmod-nvidia*.rpm

# install userspace
rpm-ostree -y install \
  "nvidia-driver-${ver}*" \
  "nvidia-driver-libs-${ver}*" \
  "nvidia-settings-${ver}*" \
  "nvidia-driver-cuda-${ver}*" \
  libva-nvidia-driver
#  nvidia-container-toolkit


# disable negativo and container toolkit repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=0/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
#sed -i 's/^\s*enabled\s*=\s*0/enabled=0/' /etc/yum.repos.d/nvidia-container-toolkit.repo

echo "NVIDIA userspace ${ver} installed."
