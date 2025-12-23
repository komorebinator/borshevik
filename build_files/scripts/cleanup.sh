#!/bin/bash

set -ouex pipefail

rpm-ostree override remove firefox firefox-langpacks toolbox gnome-classic-session nvtop

echo "Removing Gnome Shell extension rpms";
mapfile -t EXT_PKGS < <(rpm -qa --qf '%{NAME}\n' 'gnome-shell-extension-*' | sort -u)

if ((${#EXT_PKGS[@]})); then
  echo "Removing GNOME Shell extension RPMs:"
  printf '  %s\n' "${EXT_PKGS[@]}"
  rpm-ostree override remove "${EXT_PKGS[@]}"
else
  echo "No gnome-shell-extension-* RPMs installed, skipping."
fi

systemctl disable flatpak-add-fedora-repos.service
