#!/bin/bash

set -ouex pipefail

/build_scripts/os-info.sh
/build_scripts/cleanup.sh
/build_scripts/install-rpm-packages.sh
/build_scripts/install-gs-extensions.sh
/build_scripts/install-copr-packages.sh
/build_scripts/install-google-chrome.sh
/build_scripts/apply-schemas.sh
/build_scripts/apply-dconf.sh
/build_scripts/enable-services.sh
/build_scripts/rebuild-initramfs.sh

systemctl enable podman.socket
