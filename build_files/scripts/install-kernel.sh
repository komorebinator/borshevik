#!/usr/bin/env bash
set -euo pipefail

# Replaces the kernel inherited from the base image with the one in uBlue's
# akmods cache, at AKMODS_TAG in the Containerfile - the tag the NVIDIA modules
# are taken at too. So that tag alone decides the kernel, and the modules come
# from the same uBlue build as it: the base image's kernel and uBlue's rolling
# akmods tags are built apart and can for a while name different kernels, and
# modules built for one kernel do not load on another.

SEARCH_DIR="/tmp/akmods-kernel"

if [[ ! -d "$SEARCH_DIR" ]]; then
    echo "Missing ${SEARCH_DIR} - the COPY --from=akmods line is gone from the Containerfile" >&2
    exit 1
fi

mapfile -t AVAILABLE < <(find "$SEARCH_DIR" -name 'kernel*.rpm' | sort)
if ((${#AVAILABLE[@]} == 0)); then
    echo "No kernel RPMs under ${SEARCH_DIR}" >&2
    exit 1
fi
echo "Kernel RPMs offered by the akmods image:"
printf '  %s\n' "${AVAILABLE[@]##*/}"

# Swap exactly the kernel subpackages this image already has, and only once the
# cache is known to hold every one of them, so a missing one never leaves the
# image with half a kernel.
mapfile -t INSTALLED < <(rpm -qa --qf '%{NAME}\n' | grep -E '^kernel(-core|-modules(-core|-extra)?)?$' | sort -u)
echo "Kernel subpackages installed in the base image: ${INSTALLED[*]}"

REPLACE=()
for pkg in "${INSTALLED[@]}"; do
    match="$(find "$SEARCH_DIR" -name "${pkg}-[0-9]*.rpm" | head -1)"
    if [[ -z "$match" ]]; then
        echo "No replacement for ${pkg} in the akmods cache - refusing a partial swap" >&2
        exit 1
    fi
    REPLACE+=("$match")
done

# Erase and install, as Bluefin does: rpm-ostree override replace refuses the
# very version installed, which the base image and the cache often share
mapfile -t OLD_KVERS < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
echo "Erasing the base image's kernel ${OLD_KVERS[*]}"
rpm --erase --nodeps "${INSTALLED[@]}"
# What no package owns stays behind, the base image's initramfs among it
for kver in "${OLD_KVERS[@]}"; do
    rm -rf "/usr/lib/modules/${kver}"
done

echo "Installing kernel:"
printf '  %s\n' "${REPLACE[@]##*/}"
dnf5 -y install "${REPLACE[@]}"

mapfile -t KERNELS < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
WANTED="$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$(find "$SEARCH_DIR" -name 'kernel-core-[0-9]*.rpm' | head -1)")"
mapfile -t MODULE_DIRS < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ ${#KERNELS[@]} -ne 1 || "${KERNELS[0]}" != "$WANTED" || ${#MODULE_DIRS[@]} -ne 1 || "${MODULE_DIRS[0]}" != "$WANTED" ]]; then
    echo "Expected kernel ${WANTED} alone; installed: ${KERNELS[*]}; /usr/lib/modules: ${MODULE_DIRS[*]}" >&2
    exit 1
fi
echo "Kernel now installed: ${WANTED}"
