#!/bin/bash

set -ouex pipefail

/build_scripts/os-info.sh
/build_scripts/install-rpm-packages.sh
/build_scripts/install-google-chrome.sh
/build_scripts/install-steam.sh
/build_scripts/cleanup.sh

systemctl enable podman.socket
