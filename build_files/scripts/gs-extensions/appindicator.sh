#!/usr/bin/env bash

set -ouex pipefail

meson . /tmp/g-s-appindicators-build
ninja -C /tmp/g-s-appindicators-build install