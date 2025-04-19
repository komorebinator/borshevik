#!/bin/bash

set -ouex pipefail

/ctx/scripts/cleanup.sh
/ctx/scripts/install-google-chrome.sh
/ctx/scripts/install-rpm-packages.sh
/ctx/scripts/install-flatpaks.sh
/ctx/scripts/user-settings.sh


systemctl enable podman.socket
