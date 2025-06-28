#!/usr/bin/env bash

set -ouex pipefail

meson setup build --prefix=/usr
meson install -C build
