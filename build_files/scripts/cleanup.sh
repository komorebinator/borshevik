#!/bin/bash

set -ouex pipefail

rpm-ostree override remove firefox firefox-langpacks toolbox gnome-classic-session gnome-shell-extension-* nvtop

systemctl disable flatpak-add-fedora-repos.service
