#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/output-directory" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "${script_dir}/.." && pwd)"
destination_parent="$(dirname "$1")"
mkdir -p "${destination_parent}"
destination="$(cd "${destination_parent}" && pwd)/$(basename "$1")"

mkdir -p "${destination}"

rsync -a \
  --delete \
  --exclude '.build/' \
  --exclude '.swiftpm/' \
  --exclude '.DS_Store' \
  --exclude '.accessibility-preflight/' \
  --exclude 'DerivedData/' \
  --exclude '*.xcresult' \
  "${package_root}/Package.swift" \
  "${package_root}/README.md" \
  "${package_root}/LICENSE" \
  "${package_root}/.gitignore" \
  "${package_root}/.codex-plugin" \
  "${package_root}/Sources" \
  "${package_root}/Tests" \
  "${package_root}/Harnesses" \
  "${package_root}/Templates" \
  "${package_root}/skills" \
  "${package_root}/scripts" \
  "${package_root}/docs" \
  "${destination}/"

echo "Exported standalone package to ${destination}"
echo "Next:"
echo "  1. Create a new git repo in ${destination}"
echo "  2. Confirm plugin metadata points at https://github.com/getmodus/accessibility-preflight"
echo "  3. Run: cd ${destination} && swift test"
