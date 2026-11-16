ARG FEDORA_MAJOR_VERSION=44
ARG AKMODS_TAG=main-${FEDORA_MAJOR_VERSION}
ARG PACKAGES_TAG=${FEDORA_MAJOR_VERSION}-main

FROM scratch AS ctx

COPY build_files/scripts /build_scripts/

FROM ghcr.io/komorebinator/borshevik-packages:${PACKAGES_TAG} AS packages

FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION} AS borshevik-base

ARG IMAGE_NAME
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION
ARG AKMODS_TAG
ARG BUILD_DATE

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_NAME

COPY cosign.pub /etc/pki/containers/cosign.pub

COPY --from=ghcr.io/ublue-os/akmods:${AKMODS_TAG} / /tmp/akmods-kernel

RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    --mount=type=bind,from=packages,source=/rpms,target=/tmp/borshevik-rpms \
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