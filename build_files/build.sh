#!/bin/bash

set -ouex pipefail

/ctx/scripts/cleanup.sh
/ctx/scripts/enable-google-chrome.sh
/ctx/scripts/user-settings.sh


systemctl enable podman.socket
