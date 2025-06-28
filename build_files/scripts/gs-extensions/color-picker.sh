#!/usr/bin/env bash

set -ouex pipefail

meson setup -Ddatadir=/usr/share -Dtarget=system -Dlocaledir=/usr/share/locale build && meson install -C build
