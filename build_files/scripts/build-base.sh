#!/bin/bash

set -ouex pipefail

/build_scripts/configure-repos.sh
/build_scripts/install-kernel.sh
# TEMPORARY (2026-10): ca-certificates ahead of Fedora stable - see install-ca-certificates.sh
/build_scripts/install-ca-certificates.sh
/build_scripts/install-rpm-packages.sh
/build_scripts/install-google-chrome.sh
/build_scripts/install-steam.sh
/build_scripts/cleanup.sh

systemctl enable podman.socket
