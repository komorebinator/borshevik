#!/usr/bin/env bash

set -ouex pipefail

meson setup _build . \
  --prefix=/usr \
  --libdir=/usr/lib64 \
  -Dgnome_shell_libdir=/usr/lib64 \
  -Dsession_bus_services_dir=/usr/share/dbus-1/services \
  -Dwebextension=false \
  -Dnautilus=true \
  -Dpost_install=false

meson compile -C .
meson install  -C .