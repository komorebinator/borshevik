ARG FEDORA_MAJOR_VERSION=44
# The one tag both akmods caches are taken at: the kernel (install-kernel.sh)
# and the NVIDIA modules, so both come from the same uBlue build and the tag
# alone decides the kernel. main-${FEDORA_MAJOR_VERSION} follows uBlue's newest
# stock Fedora kernel; main-${FEDORA_MAJOR_VERSION}-<kernel version> holds one.
# Never a coreos-stable tag: following it once brought in the 7.2 kernel the
# hold below exists to keep out.
#
# HELD on 7.1 (since 2026-10-01): Fedora's 7.2 kernels carry upstream commit
# 7e5760f084d0, which made YCbCr 4:2:0 conditional on a debugfs override, so
# displays whose 4K@60 exists only as 4:2:0 (4K TVs with HDMI 1.4-class inputs)
# get RGB they cannot accept and show nothing at all. Fixed upstream in 7.3 by
# rewrite; no 7.2.x backport (checked up to 7.2.12 on 2026-10-21). Back to
# main-${FEDORA_MAJOR_VERSION} once Fedora ships 7.3 for this release.
ARG AKMODS_TAG=main-${FEDORA_MAJOR_VERSION}-7.1.13-200.fc44

FROM scratch AS ctx

COPY build_files/scripts /build_scripts/

FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION} AS borshevik-base

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG AKMODS_TAG
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

COPY cosign.pub /etc/pki/containers/cosign.pub

# The kernel install-kernel.sh puts in place of the base image's
COPY --from=ghcr.io/ublue-os/akmods:${AKMODS_TAG} / /tmp/akmods-kernel

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build-base.sh && \
    ostree container commit

FROM borshevik-base AS borshevik-base-nvidia

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG AKMODS_TAG
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

# The same tag as the kernel: these modules are built against one exact kernel
COPY --from=ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_TAG} / /tmp/akmods-nvidia

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