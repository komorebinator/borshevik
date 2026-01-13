#!/bin/bash

set -ouex pipefail

echo "Remove redundant PRMs"
rpm-ostree override remove firefox firefox-langpacks toolbox gnome-classic-session nvtop

echo "Removing GNOME Shell extension RPMs"
mapfile -t EXT_PKGS < <(rpm -qa --qf '%{NAME}\n' 'gnome-shell-extension-*' | sort -u)

if ((${#EXT_PKGS[@]})); then
  rpm-ostree override remove "${EXT_PKGS[@]}"
else
  echo "No gnome-shell-extension-* RPMs installed, skipping."
fi

echo "Remove Gnome Software DKMS helper"
rm /usr/lib64/gnome-software/plugins-*/libgs_plugin_dkms.so
rm /usr/libexec/gnome-software-dkms-helper
rm /usr/share/polkit-1/actions/org.gnome.software.dkms-helper.policy

echo "Disable Fedora flapak service"
systemctl disable flatpak-add-fedora-repos.service

echo "Cleaned up"
df -h