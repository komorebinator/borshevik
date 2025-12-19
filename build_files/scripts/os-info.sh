#!/usr/bin/env bash

set -euo pipefail

cat <<EOF >> /usr/lib/os-release

VERSION="${BUILD_DATE}"
PLATFORM_ID="platform:f${FEDORA_MAJOR_VERSION}"
VERSION_ID="${FEDORA_MAJOR_VERSION}"
VARIANT_ID="${IMAGE_NAME}"
EOF