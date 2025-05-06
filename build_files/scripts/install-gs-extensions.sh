#!/usr/bin/env bash
# install-gs-extensions.sh
# Run as root during image build (no arguments).

set -euo pipefail

###############################################################################
# Extension list
###############################################################################
EXTENSIONS=(
  "clipboard-indicator@tudmotu.com"
  "Battery-Health-Charging@maniacx.github.com"
  "blur-my-shell@aunetx"
  "caffeine@patapon.info"
  "weatheroclock@CleoMenezesJr.github.io"
  "pip-on-top@rafostar.github.com"
  "status-area-horizontal-spacing@mathematical.coffee.gmail.com"
  "primary_input_on_lockscreen@sagidayan.com"
  "batterytime@typeof.pw"
  "notification-timeout@chlumskyvaclav.gmail.com"
  "Bluetooth-Battery-Meter@maniacx.github.com"
  "gsconnect@andyholmes.github.io"
)

###############################################################################
# Helper: determine GNOME Shell major version from the package DB
###############################################################################
get_shell_major() {
  if command -v rpm &>/dev/null && rpm -q gnome-shell &>/dev/null; then
    rpm -q --qf '%{VERSION}\n' gnome-shell | cut -d. -f1
    return
  fi
  if command -v dpkg-query &>/dev/null && dpkg-query -W gnome-shell &>/dev/null; then
    dpkg-query -W -f='${Version}\n' gnome-shell | cut -d. -f1
    return
  fi
  echo "Error: unable to detect gnome-shell package version in build root." >&2
  exit 1
}

###############################################################################
# Main
###############################################################################
DEST_DIR="/usr/share/gnome-shell/extensions"
SHELL_MAJOR="$(get_shell_major)"

mkdir -p "${DEST_DIR}"
echo ">>> Installing GNOME extensions for Shell ${SHELL_MAJOR} …"

for uuid in "${EXTENSIONS[@]}"; do
  target_dir="${DEST_DIR}/${uuid}"
  if [[ -d "${target_dir}" ]]; then
    echo " • ${uuid} already present, skipping"
    continue
  fi

  dl_url=$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_MAJOR}" |
    grep -oP '"download_url":"\K[^"]+' || true)

  if [[ -z "${dl_url}" ]]; then
    echo " !! ${uuid}: no release for GNOME ${SHELL_MAJOR}. Aborting." >&2
    exit 1
  fi

  echo " • Fetching ${uuid}"
  tmp_zip="$(mktemp)"
  curl -fsSL "https://extensions.gnome.org${dl_url}" -o "${tmp_zip}"

  unzip -q "${tmp_zip}" -d "${target_dir}"
  rm -f "${tmp_zip}"

  # Set permissions: dirs 755, files 644
  find "${target_dir}" -type d -exec chmod 755 {} +
  find "${target_dir}" -type f -exec chmod 644 {} +
done

echo ">>> All extensions installed successfully."
