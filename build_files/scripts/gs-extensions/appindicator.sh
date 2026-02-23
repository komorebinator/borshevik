#!/usr/bin/env bash

set -ouex pipefail

meson setup _build . --prefix=/usr
meson compile -C _build
meson install -C _build
