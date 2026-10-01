#!/usr/bin/env bash
set -euo pipefail

# ###########################################################################
# TEMPORARY WORKAROUND - added 2026-09, delete when no longer needed.
#
# This script exists only to keep Borshevik off Fedora's 7.2 kernels. It is not
# a design decision about kernel policy; without the regression below, Borshevik
# takes whatever kernel the @UniversalBlueGnome base image ships.
#
# REMOVE WHEN: Fedora ships a kernel carrying the fix - 7.3.x, or a 7.2.x that
# reverts upstream commit 7e5760f084d0. Verify either way: set a 4:2:0-only
# 4K@60 mode on such a TV and see whether a picture appears, or read the
# drm_mode_is_420_only branch in drivers/gpu/drm/amd/display/ and check it no
# longer demands force_yuv_pixel_format.
#
# TO REVERT: delete this script, its call in build-base.sh, the COPY of
# ghcr.io/ublue-os/akmods and the HELD_KERNEL ARGs in the Containerfile, and
# restore the akmods-nvidia-open tag there to main-<FEDORA_MAJOR_VERSION>.
# ###########################################################################

# Replaces the kernel inherited from the base image with a 7.1 kernel from
# uBlue's akmods cache, at the tag pinned to HELD_KERNEL in the Containerfile:
# the stock Fedora kernel, held on the last series without the regression.
#
# Why: taking Fedora's newest kernel unreviewed every night is how the amdgpu
# HDMI regression in 7.2 reached users. Upstream commit 7e5760f084d0 made
# YCbCr 4:2:0 conditional on a debugfs override, so a 4K TV whose 4K@60 exists
# only as 4:2:0 gets RGB it cannot accept - no picture at all, no error logged.
# Fixed upstream in 7.3 by rewrite, with no backport to 7.2.x (still none in
# 7.2.8, checked 2026-10-01).
#
# Pinned to one version, never a rolling tag: this first followed coreos-stable,
# and when Fedora CoreOS moved to 7.2.5 the build quietly installed a 7.2 kernel
# with the very regression this script exists for.
#
# The NVIDIA akmods image is taken at the same HELD_KERNEL tag: its modules are
# built against one exact kernel version.

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

# Replace exactly the kernel subpackages this image already has: rpm-ostree
# refuses a partial replacement, and a package installed here but absent from
# the cache would abort the whole transaction anyway.
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

echo "Replacing kernel with:"
printf '  %s\n' "${REPLACE[@]##*/}"
rpm-ostree override replace "${REPLACE[@]}"

echo "Kernel now installed:"
rpm -q kernel kernel-core
