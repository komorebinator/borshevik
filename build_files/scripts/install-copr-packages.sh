#!/bin/bash
dnf5 -y copr enable komorebithrows/borshevik

dnf upgrade -y gnome-control-center

if [[ "$(rpm -q --qf '%{EPOCH}' gnome-control-center)" != "1" ]]; then
    echo "Gnome control center was not upgraded" >&2
    exit 1
fi

rpm-ostree upgrade -y
dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-steam.repo
rpm-ostree install -y steam kernel-modules-extra
