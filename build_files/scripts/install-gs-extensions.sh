#!/usr/bin/env bash
# install-gs-extensions.sh
set -euo pipefail

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
get_shell_major() {
  if command -v rpm &>/dev/null && rpm -q gnome-shell &>/dev/null; then
    rpm -q --qf '%{VERSION}\n' gnome-shell | cut -d. -f1; return
  fi
  if command -v dpkg-query &>/dev/null && dpkg-query -W gnome-shell &>/dev/null; then
    dpkg-query -W -f='${Version}\n' gnome-shell | cut -d. -f1; return
  fi
  echo "Error: cannot detect gnome-shell version in build root." >&2
  exit 1
}

###############################################################################
DEST_DIR="/usr/share/gnome-shell/extensions"
SHELL_MAJOR="$(get_shell_major)"

mkdir -p "$DEST_DIR"
echo ">>> Installing GNOME extensions for Shell $SHELL_MAJOR …"

for uuid in "${EXTENSIONS[@]}"; do
  dir="${DEST_DIR}/${uuid}"
  [[ -d $dir ]] && { echo " • $uuid already present, skipping"; continue; }

  json=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}") ||
        { echo " !! $uuid: API request failed"; exit 1; }

  dl_url=$(echo "$json" |
           jq -r --arg v "$SHELL_MAJOR" '
             .releases[]
             | select(.shell_version_map | has($v))
             | .download_url
             ' | head -n1)

  [[ -n $dl_url ]] || {
    echo " !! $uuid: no release for GNOME $SHELL_MAJOR. Aborting." >&2
    exit 1
  }

  echo " • Fetching $uuid"
  tmp=$(mktemp)
  curl -fsSL "https://extensions.gnome.org${dl_url}" -o "$tmp"
  unzip -q "$tmp" -d "$dir"
  rm -f "$tmp"

  find "$dir" -type d -exec chmod 755 {} +
  find "$dir" -type f -exec chmod 644 {} +
done

echo ">>> All extensions installed successfully."
