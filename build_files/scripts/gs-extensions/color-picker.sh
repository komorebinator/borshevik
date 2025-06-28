#!/usr/bin/env bash

set -ouex pipefail

meson setup --prefix=/usr -Dtarget=system build
meson install -C build
