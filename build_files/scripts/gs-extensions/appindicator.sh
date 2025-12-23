#!/usr/bin/env bash

set -ouex pipefail

meson . /tmp/g-s-appindicators-build --prefix=/usr
ninja -C /tmp/g-s-appindicators-build install