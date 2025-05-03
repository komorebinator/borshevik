# shared build context
FROM scratch AS ctx
COPY build_files /

# === BASE IMAGE (Borshevik) ===
FROM ghcr.io/ublue-os/silverblue-main:latest AS borshevik

ARG IMAGE_NAME=komorebi-os
ARG IMAGE_TAG=main
LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_TAG

COPY --from=ctx / /ctx
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit

# === NVIDIA VARIANT ===
FROM borshevik AS borshevik-nvidia

ARG IMAGE_NAME=komorebi-os-nvidia
ARG IMAGE_TAG=nvidia
LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_TAG

COPY --from=ctx / /ctx
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build-nvidia.sh && \
    ostree container commit

# === LINTING ===
FROM borshevik-nvidia AS lint
RUN bootc container lint
