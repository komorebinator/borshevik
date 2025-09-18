#!/usr/bin/env bash
set -oue pipefail

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
PRIV="/etc/pki/akmods/private/akmods-borshevik.priv"
CERT="/etc/pki/akmods/certs/akmods-borshevik.der"

# Add RPM Fusion repositories
#dnf5 install -y \
  #https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  #https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install NVIDIA driver packages
#rpm-ostree install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings kernel-devel kernel-headers
#akmods --force --kernels "$KVER"

# install nvidia-driver from negativo repo
curl -o /etc/yum.repos.d/fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo
rpm-ostree install nvidia-driver nvidia-settings
akmods --akmod nvidia --kernels "$KVER" --force

# unpack and sign modules
for m in /usr/lib/modules/$KVER/extra/nvidia/*.ko.xz; do
  [[ -e "$m" ]] || continue

  unxz "$m"
  KO="${m%.xz}"
  echo "Signing: $KO"
  /usr/src/kernels/$KVER/scripts/sign-file sha256 "$PRIV" "$CERT" "$KO"
  xz -z -C crc32 -6 "$KO"
done

# sign check
modinfo -F signer /usr/lib/modules/$KVER/extra/nvidia/nvidia.ko.xz* || true

systemctl enable setup-borshevik-mok.service