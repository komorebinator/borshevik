#!/bin/bash
set -ouex pipefail

sed -i 's/^\s*enabled\s*=.*/enabled=0/' \
  /etc/yum.repos.d/fedora.repo \
  /etc/yum.repos.d/fedora-updates.repo \
  /etc/yum.repos.d/fedora-updates-archive.repo

rpm-ostree -y install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

rpm-ostree -y install steam steam-devices

sed -i 's/^\s*enabled\s*=.*/enabled=1/' \
  /etc/yum.repos.d/fedora.repo \
  /etc/yum.repos.d/fedora-updates.repo \
  /etc/yum.repos.d/fedora-updates-archive.repo