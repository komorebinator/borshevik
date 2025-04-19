# Get the absolute path to the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Root folder is one level up from script directory
ROOT_DIR="${SCRIPT_DIR}/../root"

# Copy everything (including hidden files and empty dirs)
cp -r "${ROOT_DIR}/." /