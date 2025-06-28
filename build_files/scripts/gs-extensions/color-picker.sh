#!/usr/bin/env bash

set -ouex pipefail

meson setup build && meson install -C build
