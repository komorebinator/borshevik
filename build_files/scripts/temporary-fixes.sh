#!/bin/bash

set -ouex pipefail

sudo sed -i 's/"shell-version": \[ "46", "47", "48" \]/"shell-version": [ "46", "47", "48", "49" ]/' /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/metadata.json