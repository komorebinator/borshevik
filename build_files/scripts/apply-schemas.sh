#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_SRC="$SCRIPT_DIR/schemas"
SCHEMA_DST="/usr/share/glib-2.0/schemas"

mkdir -p "$SCHEMA_DST"

if compgen -G "$SCHEMA_SRC"/* >/dev/null; then
  echo "→ Copying schemas from $SCHEMA_SRC → $SCHEMA_DST"
  cp -a "$SCHEMA_SRC"/* "$SCHEMA_DST"/
else
  echo "⚠️ No schema files found in $SCHEMA_SRC, nothing to do."
fi

echo "→ Compiling GSettings schemas"
glib-compile-schemas "$SCHEMA_DST"
echo "✅ Schemas installed and compiled."
