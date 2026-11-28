#!/usr/bin/env bash
set -euo pipefail

# Installs the NVIDIA driver from the akmods-nvidia-open image's own RPMs: the
# prebuilt kernel modules and, from the same build, the whole userspace set.
# The userspace used to come from negativo17 by version, but the repository
# keeps only its newest driver, so an akmods tag pinned to an older kernel
# found its driver gone and the build failed. The cache always holds the
# matching set - this is how uBlue's own nvidia-install.sh installs it.

source "$(dirname "$(readlink -f "$0")")/libs/unsigned-rpms-lib.sh"
source "$(dirname "$(readlink -f "$0")")/libs/package-versions-lib.sh"

AKMODS="/tmp/akmods-nvidia"

echo "Akmods image"
find "$AKMODS"

source "$AKMODS/rpms/kmods/nvidia-vars"
full_ver="${NVIDIA_AKMOD_VERSION}"
ver="${full_ver%%-*}"

shopt -s nullglob
KMOD=("$AKMODS"/rpms/kmods/kmod-nvidia*.rpm)
USERSPACE=("$AKMODS"/rpms/nvidia/*.x86_64.rpm "$AKMODS"/rpms/nvidia/*.noarch.rpm "$AKMODS"/rpms/nvidia/*.i686.rpm)
ADDONS=("$AKMODS"/rpms/ublue-os/ublue-os-nvidia-addons-*.rpm)
shopt -u nullglob
if [[ ${#KMOD[@]} -eq 0 || ${#USERSPACE[@]} -eq 0 || ${#ADDONS[@]} -eq 0 ]]; then
    echo "The akmods image lacks the kmod, the userspace or the addons RPMs" >&2
    exit 1
fi

# The addons bring the repositories of what the cache lacks, both disabled:
# negativo17's, the only one with nvidia-driver-selinux, which the driver
# requires under SELinux, and NVIDIA's, with nvidia-container-toolkit. Enabled
# for the one transaction alone, so the image ships them off - the way uBlue's
# own nvidia-install.sh installs the driver. libva-nvidia-driver is Fedora's.
echo "Install ublue-os-nvidia-addons"
dnf5 -y install "${ADDONS[@]}"

# kmod-nvidia is not signed
echo "Install driver ${ver} from the akmods image, and nvidia-container-toolkit"
with_unsigned_rpms dnf5 -y --enablerepo=fedora-nvidia --enablerepo=nvidia-container-toolkit install \
    "${KMOD[@]}" "${USERSPACE[@]}" libva-nvidia-driver nvidia-container-toolkit

# The driver's 32-bit libraries can take 64-bit packages of the base up to the
# updates' version, as Steam's do; the rest of their source packages follow
align_package_versions

installed="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "$installed" != "$ver" ]]; then
    echo "nvidia-driver is ${installed}, but the kernel modules are built for ${ver}" >&2
    exit 1
fi
echo "NVIDIA driver ${ver}: modules and userspace match"

# The modules must be built for the one kernel the image ships, which comes from
# the akmods cache at the same AKMODS_TAG. kmod-nvidia requires that exact
# kernel, so a cache built for another one could have pulled a second kernel in
# from the repositories rather than fail.
mapfile -t KERNELS < <(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
if [[ ${#KERNELS[@]} -ne 1 ]]; then
    echo "Expected one kernel, found: ${KERNELS[*]}" >&2
    exit 1
fi
if ! find "/usr/lib/modules/${KERNELS[0]}" -name 'nvidia.ko*' | grep -q .; then
    echo "No NVIDIA module for kernel ${KERNELS[0]} - the akmods caches name different kernels" >&2
    exit 1
fi
echo "NVIDIA modules built for kernel ${KERNELS[0]}"

# Containers reach the GPU through CDI: the toolkit's units write the spec at
# boot and whenever the driver changes, and the addons' SELinux module lets a
# confined container open the GPU's device nodes
systemctl enable nvidia-cdi-refresh.service nvidia-cdi-refresh.path
semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp
