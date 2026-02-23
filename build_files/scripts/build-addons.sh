#!/bin/bash

set -ouex pipefail

/build_scripts/os-info.sh
/build_scripts/install-goxray.sh
/build_scripts/install-gs-extensions.sh
/build_scripts/apply-schemas.sh
/build_scripts/apply-dconf.sh
/build_scripts/enable-services.sh
/build_scripts/rebuild-initramfs.sh