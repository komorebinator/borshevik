#!/usr/bin/env bash

set -ouex pipefail

meson setup build -Dtarget=system && meson install -C build
