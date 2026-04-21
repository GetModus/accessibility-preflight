#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
bin_dir="${HOME}/.local/bin"
target="${bin_dir}/accessibility-preflight"
marker="# Installed by accessibility-preflight"
shim_path="$(mktemp "${TMPDIR:-/tmp}/accessibility-preflight.XXXXXX")"
trap 'rm -f "${shim_path}"' EXIT

mkdir -p "${bin_dir}"

cat >"${shim_path}" <<EOF
#!/usr/bin/env bash
# Installed by accessibility-preflight
set -euo pipefail

exec swift run --package-path "${repo_root}" accessibility-preflight "\$@"
EOF
chmod 0755 "${shim_path}"

if [[ -e "${target}" ]]; then
  if [[ -f "${target}" ]] && grep -qF "${marker}" "${target}" 2>/dev/null; then
    cp "${shim_path}" "${target}"
    chmod 0755 "${target}"
    echo "Updated ${target}"
    exit 0
  fi

  echo "Refusing to overwrite existing ${target}." >&2
  echo "Remove it manually or back it up, then rerun this installer." >&2
  exit 1
fi

cp "${shim_path}" "${target}"
chmod 0755 "${target}"
echo "Installed ${target}"
