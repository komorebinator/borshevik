ARG FEDORA_MAJOR_VERSION=42

# Stage for build scripts (these will be mounted, not persisted)
FROM scratch AS ctx

# Copy all build scripts into /build_scripts
COPY build_files/scripts /build_scripts/

# Base image (Borshevik) based on uBlue-Silverblue
FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_MAJOR_VERSION} AS borshevik

ARG IMAGE_NAME=borshevik
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_TAG

# Apply the overlay (etc/, usr/, etc.) from build_files/root
COPY build_files/root/ /
COPY cosign.pub /etc/pki/containers/cosign.pub

# Run the build script by mounting it ephemeral (not persisting in image)
RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
    /build_scripts/build.sh && \
    ostree container commit

# NVIDIA variant: run the NVIDIA-specific build script in similar manner
FROM borshevik AS borshevik-nvidia

ARG IMAGE_NAME=borshevik-nvidia
ARG IMAGE_TAG=latest
ARG FEDORA_MAJOR_VERSION

LABEL org.opencontainers.image.title=$IMAGE_NAME
LABEL org.opencontainers.image.version=$IMAGE_TAG

#RUN --mount=type=bind,from=ctx,source=/build_scripts,target=/build_scripts \
#    /build_scripts/build-nvidia.sh && \
#    ostree container commit

COPY --from=ghcr.io/ublue-os/akmods-nvidia:main-${FEDORA_MAJOR_VERSION} / /tmp/akmods-nvidia
RUN find /tmp/akmods-nvidia
## optionally install remove old and install new kernel
# dnf -y remove --no-autoremove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
## install ublue support package and desired kmod(s)
RUN dnf install /tmp/akmods-nvidia/rpms/ublue-os/ublue-os-nvidia*.rpm
RUN dnf install /tmp/akmods-nvidia/rpms/kmods/kmod-nvidia*.rpm

# Linting stage to validate the container
FROM borshevik-nvidia AS lint
RUN bootc container lint
