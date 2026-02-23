#!/usr/bin/env bash
set -euo pipefail

# Installs v2rayA (web-UI proxy client) and v2ray core from the official
# zhullyb/v2rayA COPR repository.
#
# v2rayA is a stateful service (systemctl enable v2raya handled in
# enable-services.sh). The web UI runs at http://localhost:2017.
#
# Prerequisites (present in the uBlue build container):
#   curl, rpm-ostree, FEDORA_MAJOR_VERSION env var

COPR_REPO_URL="https://copr.fedorainfracloud.org/coprs/zhullyb/v2rayA/repo/fedora-${FEDORA_MAJOR_VERSION}/zhullyb-v2rayA-fedora-${FEDORA_MAJOR_VERSION}.repo"
REPO_FILE="/etc/yum.repos.d/zhullyb-v2rayA.repo"

echo "Adding zhullyb/v2rayA COPR repo for Fedora ${FEDORA_MAJOR_VERSION}"
curl -fsSL --retry 3 "$COPR_REPO_URL" -o "$REPO_FILE"

echo "Installing v2raya and v2ray"
rpm-ostree install -y v2raya v2ray

echo "Done. v2rayA installed."
