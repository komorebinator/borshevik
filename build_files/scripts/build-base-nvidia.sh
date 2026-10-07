#!/usr/bin/env bash
set -euo pipefail

# Installs the NVIDIA driver from the akmods-nvidia-open image's own RPMs: the
# prebuilt kernel modules and, from the same build, the whole userspace set.
# The userspace used to come from negativo17 by version, but the repository
# keeps only its newest driver, so an akmods tag pinned to an older kernel
# found its driver gone and the build failed. The cache always holds the
# matching set - this is how uBlue's own nvidia-install.sh installs it.

AKMODS="/tmp/akmods-nvidia"

echo "Akmods image"
find "$AKMODS"

source "$AKMODS/rpms/kmods/nvidia-vars"
full_ver="${NVIDIA_AKMOD_VERSION}"
ver="${full_ver%%-*}"

shopt -s nullglob
KMOD=("$AKMODS"/rpms/kmods/kmod-nvidia*.rpm)
USERSPACE=("$AKMODS"/rpms/nvidia/*.x86_64.rpm "$AKMODS"/rpms/nvidia/*.noarch.rpm "$AKMODS"/rpms/nvidia/*.i686.rpm)
shopt -u nullglob
if [[ ${#KMOD[@]} -eq 0 || ${#USERSPACE[@]} -eq 0 ]]; then
    echo "The akmods image lacks the kmod or the userspace RPMs" >&2
    exit 1
fi

# libva-nvidia-driver follows no driver version, and is not in the cache
echo "Enable negativo17 repo"
curl -fsSL "https://negativo17.org/repos/fedora-nvidia.repo" -o "/etc/yum.repos.d/negativo17-fedora-nvidia.repo"

echo "Install driver ${ver} from the akmods image"
rpm-ostree -y install "${KMOD[@]}" "${USERSPACE[@]}" libva-nvidia-driver

installed="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "$installed" != "$ver" ]]; then
    echo "nvidia-driver is ${installed}, but the kernel modules are built for ${ver}" >&2
    exit 1
fi
echo "NVIDIA driver ${ver}: modules and userspace match"
