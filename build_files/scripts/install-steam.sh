#!/bin/bash
set -ouex pipefail

# dnf5, not rpm-ostree: Steam's 32-bit libraries must be the very version of
# their 64-bit twins in the base image, and the base can lag Fedora's updates,
# whose repository keeps only the newest build (openssl-libs, SDL3 and others
# behind in 2026-10). rpm-ostree never upgrades a package of the base, so it
# cannot resolve that; dnf5 brings the 64-bit ones up to the updates' version.
#
# Without vendor changes: a package of the base may be upgraded only by its own
# vendor's build. Left free, dnf5 took fedora-multimedia's libheif, of a higher
# epoch, which brought dozens of 32-bit codecs and replaced the base's
# libheif-ffmpeg and noopenh264.
dnf5 -y --setopt=allow_vendor_change=False install steam steam-devices
