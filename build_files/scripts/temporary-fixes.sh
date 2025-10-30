#!/bin/bash

set -ouex pipefail

jq '.["shell-version"] += ["49"]' /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/metadata.json \
| tee /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io/metadata.json > /dev/null
