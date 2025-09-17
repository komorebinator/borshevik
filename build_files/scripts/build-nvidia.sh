#!/usr/bin/env bash
set -oue pipefail

#KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"

# Add RPM Fusion repositories
#dnf5 install -y \
  #https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  #https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install NVIDIA driver packages
#rpm-ostree install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings kernel-devel kernel-headers
#akmods --force --kernels "$KVER"

curl -o /etc/yum.repos.d/fedora-nvidia.repo https://negativo17.org/repos/fedora-nvidia.repo

rpm-ostree install nvidia-driver nvidia-settings

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
PRIV="/etc/pki/akmods/private/akmods-borshevik.priv"
CERT="/etc/pki/akmods/certs/akmods-borshevik.der"
akmods --akmod nvidia --kernels "$KVER" --force


# sign nvidia modules (.ko and .ko.xz)
for m in /usr/lib/modules/$KVER/extra/nvidia/*.ko*; do
  [[ -e "$m" ]] || continue
  if [[ "$m" == *.xz ]]; then
    unxz -k "$m"; KO="${m%.xz}"
  else
    KO="$m"
  fi
  /usr/src/kernels/$KVER/scripts/sign-file sha256 "$PRIV" "$CERT" "$KO"
  [[ "$m" == *.xz ]] && xz -f "$KO"
done

# sign check
modinfo -F signer /usr/lib/modules/$KVER/extra/nvidia/nvidia.ko* || true

systemctl enable setup-borshevik-mok.service