#!/bin/bash

set -oue pipefail

# Create /opt directory
echo "Fixing /opt if it's not a dir..."
[ ! -d /opt ] && rm -f /opt
mkdir -p /opt
mkdir -p /usr/lib/opt/google

# Remove /opt/google, if not symlink
if [ -d /opt/google ] && [ ! -L /opt/google ]; then
    echo "Removing existing /opt/google directory"
    rm -rf /opt/google
fi

# Make symlink
ln -sfn /usr/lib/opt/google /opt/google

echo "Symlink created:"
ls -l /opt/google

# Part of an attempt to add Google Chrome in the usual way.
echo "Fixing google-chrome yum repo"
sed -i '/enabled/d' /etc/yum.repos.d/google-chrome.repo 
echo "enabled=1" >> /etc/yum.repos.d/google-chrome.repo

# This does not appear to be necessary, since at this point there are no
# Google keys in the RPM database.  Will be deleted soon.

# First, delete all old keys; see https://github.com/rpm-software-management/rpm/issues/2577
# echo "Fixing issues with Google GPG keys"
# set +oue
# rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE} %{PACKAGER}\n' | grep 'linux-packages-keymaster@google.com' | sed 's/ .*$//' | xargs
# GOOGLE_PUBKEYS_RPMS=$(rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE} %{PACKAGER}\n' | grep 'linux-packages-keymaster@google.com' | sed 's/ .*$//' | xargs)
# set -oue
# echo "Installed pubkeys RPMS are $GOOGLE_PUBKEYS_RPMS"
# if [ -n "$GOOGLE_PUBKEYS_RPMS" ]; then
#     echo "Removing pakcages $GOOGLE_PUBKEYS_RPMS"
#     rpm -e $GOOGLE_PUBKEYS_RPMS
# fi

# We need to download and install the Google signing keys separately, we can't trust
# rpm-ostree to do it cleanly from the yum repo directly.
# Possibly related to https://github.com/rpm-software-management/rpm/issues/2577

echo "Downloading Google Signing Key"
curl https://dl.google.com/linux/linux_signing_key.pub > /tmp/linux_signing_key.pub

rpm --import /tmp/linux_signing_key.pub

rpm-ostree install -y google-chrome-stable

# Make Chrome default
mkdir -p /etc/xdg

cat << EOF > /etc/xdg/mimeapps.list
[Default Applications]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
text/html=google-chrome.desktop
EOF

sed -i 's|^Exec=/usr/bin/google-chrome-stable %U$|Exec=/usr/bin/google-chrome-stable --enable-features=TouchpadOverscrollHistoryNavigation --ozone-platform=wayland %U|' \
  /usr/share/applications/google-chrome.desktop