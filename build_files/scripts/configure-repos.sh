#!/usr/bin/env bash
set -euo pipefail

# Runs before the base layer's first package transaction; what it changes stays
# in the image.

# Cisco's openh264: nothing is installed from it, and it broke builds. A server
# behind codecs.fedoraproject.org that GitHub's runners resolve to answers 404
# for its metadata, and rpm-ostree fails every transaction on it, ignoring the
# repository's skip_if_unavailable. The openh264 packages the base ships stay.
OPENH264_REPO=/etc/yum.repos.d/fedora-cisco-openh264.repo
if [[ -f "$OPENH264_REPO" ]]; then
    sed -i '/^\[fedora-cisco-openh264\]$/,/^\[/ s/^enabled=1$/enabled=0/' "$OPENH264_REPO"
fi
