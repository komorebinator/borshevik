#!/usr/bin/env bash

set -ouex pipefail

meson setup build -Ddatadir=/usr/share -Dtarget=system -Dlocaledir=/usr/share/locale && meson install -C build
