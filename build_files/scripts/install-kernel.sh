#!/usr/bin/env bash
set -euo pipefail

# Replaces the kernel inherited from the base image with the one in uBlue's
# akmods cache, at AKMODS_TAG in the Containerfile - the tag the NVIDIA modules
# are taken at too. So that tag alone decides the kernel, and the modules come
# from the same uBlue build as it: the base image's kernel and uBlue's rolling
# akmods tags are built apart and can for a while name different kernels, and
# modules built for one kernel do not load on another. Which kernel that is,
# and why it is held, is said at AKMODS_TAG.

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
