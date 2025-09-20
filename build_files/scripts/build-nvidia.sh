#!/usr/bin/env bash
set -euo pipefail

# ЖЁСТКИЙ путь к nvidia-vars из слоёв akmods:
# (у тебя kmods и ublue-os лежат под /tmp/akmods-nvidia/rpms/)
NVVARS="/tmp/akmods-nvidia/rpms/kmods/nvidia-vars"
source "$NVVARS"  # даёт NVIDIA_AKMOD_VERSION (и др.)
ver="${NVIDIA_AKMOD_VERSION}"

# enable negativo and container toolkit repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/negativo17-fedora-nvidia.repo
sed -i 's/^\s*enabled\s*=\s*0/enabled=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo

#curl -fsSL --retry 5 -o /etc/yum.repos.d/negativo17-fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo
#curl -fsSL --retry 5 -o /etc/yum.repos.d/nvidia-container-toolkit.repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo

# Install drivers
dnf -y install \
  "nvidia-driver-${ver}*" \
  "nvidia-driver-libs-${ver}*" \
  "nvidia-settings-${ver}*" \
  "nvidia-driver-cuda-${ver}*" \
  nvidia-container-toolkit \
  libva-nvidia-driver

# Отключаем репы обратно
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/negativo17-fedora-nvidia.repo || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/nvidia-container-toolkit.repo || true

# Санити-проверка версии
inst_ver="$(rpm -q --qf '%{VERSION}\n' nvidia-driver | head -n1 || true)"
[[ "$inst_ver" == "$ver" ]] || { echo "nvidia-driver ${inst_ver} != ${ver}"; exit 3; }

echo "NVIDIA userspace ${ver} installed."
