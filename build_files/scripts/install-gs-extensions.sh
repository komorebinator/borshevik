#!/usr/bin/env bash
# install-gs-extensions.sh
# Hard‑coded GNOME Shell extensions downloader for image builds.
# Run as root in Docker/Containerfile; no arguments required.

set -euo pipefail

# ---------------------------------------------------------------------------
# List the UUIDs of the extensions you want in the final image.
# One per line, quotes optional, comments not allowed inside the array.
# ---------------------------------------------------------------------------
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
  # add more UUIDs here …
)

# ---------------------------------------------------------------------------
DEST_DIR="/usr/share/gnome-shell/extensions"
SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"

mkdir -p "$DEST_DIR"
echo ">>> Installing GNOME extensions system‑wide …"

for uuid in "${EXTENSIONS[@]}"; do
  target_dir="${DEST_DIR}/${uuid}"

  if [[ -d "$target_dir" ]]; then
    echo " • $uuid already present, skipping"
    continue
  fi

  # Query the official JSON endpoint for a download URL
  dl_url=$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${SHELL_MAJOR}" |
    grep -oP '"download_url":"\K[^"]+') || {
      echo " !! Unable to resolve $uuid, aborting"
      exit 1
    }

  echo " • Fetching $uuid"
  tmp_zip="$(mktemp)"
  curl -fsSL "https://extensions.gnome.org${dl_url}" -o "$tmp_zip"

  unzip -q "$tmp_zip" -d "$target_dir"
  rm -f "$tmp_zip"

  # Normalise permissions (directories 755, files 644)
  find "$target_dir" -type d -exec chmod 755 {} +
  find "$target_dir" -type f -exec chmod 644 {} +
done

echo ">>> All requested extensions are installed."
