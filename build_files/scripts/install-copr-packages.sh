#!/bin/bash
dnf5 -y copr enable komorebithrows/borshevik

rpm-ostree install -y borshevik-control-center