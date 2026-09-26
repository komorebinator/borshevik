ARG FEDORA_MAJOR_VERSION=44

FROM scratch AS ctx

COPY build_files/scripts /build_scripts/

FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION} AS borshevik-base

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

COPY cosign.pub /etc/pki/containers/cosign.pub

# ---------------------------------------------------------------------------
# TEMPORARY WORKAROUND (added 2026-09) - amdgpu HDMI 4:2:0 regression in 7.2
#
# Fedora's 7.2 kernels carry upstream commit 7e5760f084d0, which made YCbCr
# 4:2:0 conditional on a debugfs override. Displays whose 4K@60 exists only as
# 4:2:0 (4K TVs with HDMI 1.4-class inputs) then get RGB they cannot accept and
# show nothing at all. Fixed upstream in 7.3 by rewrite; not backported to 7.2.x.
#
# Until then the kernel comes from the coreos-stable akmods flavour instead of
# the base image - still a stock Fedora kernel, just a few releases behind.
#
# TO REVERT (all three together):
#   1. delete this COPY line
#   2. delete the install-kernel.sh call from build_files/scripts/build-base.sh
#      and the script itself
#   3. restore the akmods-nvidia-open tag below to main-${FEDORA_MAJOR_VERSION}
# ---------------------------------------------------------------------------
COPY --from=ghcr.io/ublue-os/akmods:coreos-stable-${FEDORA_MAJOR_VERSION} / /tmp/akmods-kernel

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build-base.sh && \
    ostree container commit

FROM borshevik-base AS borshevik-base-nvidia

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

# TEMPORARY (2026-09): flavour must match the kernel install-kernel.sh installs,
# these modules are built against one exact kernel version. Original line kept
# for the revert - see the workaround block in the borshevik-base stage above:
# COPY --from=ghcr.io/ublue-os/akmods-nvidia-open:main-${FEDORA_MAJOR_VERSION} / /tmp/akmods-nvidia
COPY --from=ghcr.io/ublue-os/akmods-nvidia-open:coreos-stable-${FEDORA_MAJOR_VERSION} / /tmp/akmods-nvidia

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build-base-nvidia.sh && \
    ostree container commit

FROM ghcr.io/komorebinator/borshevik-base:latest AS borshevik

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

COPY build_files/root/ /

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build-addons.sh && \
    ostree container commit

FROM ghcr.io/komorebinator/borshevik-base-nvidia:latest AS borshevik-nvidia

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

COPY build_files/root/ /

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build-addons.sh && \
    ostree container commit