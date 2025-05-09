#!/bin/bash

set -ouex pipefail

./cleanup.sh
./install-gs-extensions.sh
./install-copr-packages.sh
./install-google-chrome.sh
./install-rpm-packages.sh
./apply-system-settings.sh

systemctl enable podman.socket
