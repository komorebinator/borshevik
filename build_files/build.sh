#!/bin/bash

set -ouex pipefail

/ctx/scripts/cleanup.sh
/ctx/scripts/enable-repositories.sh
/ctx/scripts/install-google-chrome.sh
/ctx/scripts/install-steam.sh
/ctx/scripts/user-settings.sh


systemctl enable podman.socket
