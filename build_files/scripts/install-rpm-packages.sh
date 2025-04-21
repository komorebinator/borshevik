#!/bin/bash

set -ouex pipefail

dnf copr enable pgdev/ghostty

rpm-ostree install -y htop mc gnome-tweaks pwgen openssl distrobox gnome-disk-utility zsh ghostty