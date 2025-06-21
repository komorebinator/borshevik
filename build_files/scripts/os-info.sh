#!/usr/bin/env bash

set -euo pipefail

if [ -n "${IMAGE_TAG:-}" ]; then
    sed -i "s|^VERSION=.*|VERSION=\"${IMAGE_TAG}\"|" /usr/lib/os-release
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"Borshevik (${IMAGE_TAG})\"|" /usr/lib/os-release
    sed -i "s|^VERSION_ID=.*|VERSION_ID=\"${FEDORA_MAJOR_VERSION}\"|" /usr/lib/os-release
    sed -i "s|^VARIANT_ID=.*|VARIANT_ID=\"${IMAGE_NAME}\"|" /usr/lib/os-release
fi
