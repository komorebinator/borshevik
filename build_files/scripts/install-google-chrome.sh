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

echo "Adding google-chrome yum repo"
cat << EOF > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
skip_if_unavailable=True
gpgcheck=0
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
enabled=1
EOF

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

#sudo sed -i 's|^Exec=/usr/bin/google-chrome-stable %U$|Exec=/usr/bin/google-chrome-stable --enable-features=TouchpadOverscrollHistoryNavigation --ozone-platform=wayland %U|' \
#  /usr/share/applications/google-chrome.desktop
sudo sed -i 's|^exec -a "\$0" "\$HERE/chrome" "\$@"$|exec -a "\$0" "\$HERE/chrome" --ozone-platform=wayland --enable-features=TouchpadOverscrollHistoryNavigation "\$@"|' /opt/google/chrome/google-chrome

rm /usr/share/applications/com.google.Chrome.desktop