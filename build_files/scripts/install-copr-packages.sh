#!/bin/bash
dnf5 -y copr enable komorebithrows/borshevik

dnf upgrade -y gnome-control-center

dnf5 -y copr enable pgdev/ghostty

dnf install -y ghostty
