#!/bin/bash

set -ouex pipefail

/build_scripts/cleanup.sh
/build_scripts/install-gs-extensions.sh
/build_scripts/install-copr-packages.sh
/build_scripts/install-google-chrome.sh
/build_scripts/install-rpm-packages.sh
/build_scripts/apply-system-settings.sh
/build_scripts/apply-dconf.sh

systemctl enable podman.socket
