#!/bin/bash

set -ouex pipefail
rpm-ostree --experimental override replace --from repo=fedora --from repo=updates gnome-software
rpm-ostree install -y htop mc gnome-tweaks pwgen openssl distrobox gnome-disk-utility zsh gnome-shell-extension-gsconnect nautilus-python patch gnome-themes-extra meson ninja-build gcc pkgconf-pkg-config make cmake glib2-devel sassc translate-shell util-linux gnome-software-rpm-ostree PackageKit xcb-util-cursor xcb-util-cursor-devel python3-nautilus
