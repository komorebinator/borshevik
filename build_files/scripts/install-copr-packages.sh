#!/bin/bash
dnf5 -y copr enable komorebithrows/borshevik

rpm-ostree override remove gnome-control-center
rpm-ostree install gnome-control-center

if [[ "$(rpm -q --qf '%{EPOCH}' gnome-control-center)" != "1" ]]; then
    echo "Gnome control center was not upgraded" >&2
    exit 1
fi

dnf -y install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

rpm-ostree install -y libva.i686 mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 vulkan-loader.i686
rpm-ostree install -y steam steam-devices