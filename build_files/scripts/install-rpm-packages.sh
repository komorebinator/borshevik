#!/bin/bash

set -ouex pipefail

rpm-ostree install -y htop mc gnome-tweaks pwgen openssl distrobox gnome-disk-utility zsh gnome-shell-extension-gsconnect nautilus-gsconnect nautilus-python patch
