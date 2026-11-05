#!/bin/bash
# Install from a cloned or extracted copy of this repository. No sudo required.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash install.sh [--no-shell]

Installs Claude FFF, Node.js/npm (if needed), and Claude Code (if needed).
Default app directory: ~/.local/share/claude-fff
Default command directory: ~/.local/bin
Override with CLAUDE_FFF_INSTALL_DIR and CLAUDE_FFF_BIN_DIR (absolute paths).
--no-shell  Do not add the command directory to shell startup files.
EOF
}
update_shell=1
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --no-shell) update_shell=0 ;;
  '') ;;
  *) usage >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 1; }

fail() { echo "Error: $*" >&2; exit 1; }
case "$(uname -s)" in
  Darwin) platform=darwin ;;
  Linux) platform=linux ;;
  *) fail 'Use macOS, Linux, or Windows through WSL.' ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=x64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) fail 'Only x64 and ARM64 are supported.' ;;
esac
for dependency in curl tar; do
  command -v "$dependency" >/dev/null || fail "Install $dependency with your system package manager, then rerun this installer."
done

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_dir=${CLAUDE_FFF_INSTALL_DIR:-"$HOME/.local/share/claude-fff"}
bin_dir=${CLAUDE_FFF_BIN_DIR:-"$HOME/.local/bin"}
[[ "$install_dir" = /* && "$bin_dir" = /* ]] || fail 'Installation paths must be absolute.'
mkdir -p "$install_dir" "$bin_dir"
install_dir=$(cd -- "$install_dir" && pwd)
bin_dir=$(cd -- "$bin_dir" && pwd)
[[ ! -e "$bin_dir/claude-fff" ]] || grep -q '^# Managed by claude-fff installer$' "$bin_dir/claude-fff" || fail "$bin_dir/claude-fff already exists and is not managed by this installer."

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-fff-install.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Keep a private runtime if the system Node/npm is missing or too old.
export PATH="$install_dir/runtime/bin:$HOME/.local/bin:$PATH"
if ! command -v node >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' || ! command -v npm >/dev/null; then
  echo 'Installing Node.js 24 LTS and npm...'
  base_url=https://nodejs.org/dist/latest-v24.x
  curl --fail --silent --show-error --location "$base_url/SHASUMS256.txt" -o "$temp_dir/SHASUMS256.txt"
  archive=$(awk -v suffix="-$platform-$arch.tar.gz" 'index($2, suffix) == length($2) - length(suffix) + 1 { print $2 }' "$temp_dir/SHASUMS256.txt")
  [[ -n "$archive" && "$archive" != *$'\n'* && "$archive" != */* ]] || fail 'Could not identify the Node.js download.'
  curl --fail --silent --show-error --location "$base_url/$archive" -o "$temp_dir/$archive"
  expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$temp_dir/SHASUMS256.txt")
  if command -v shasum >/dev/null; then
    actual=$(shasum -a 256 "$temp_dir/$archive"); actual=${actual%% *}
  elif command -v sha256sum >/dev/null; then
    actual=$(sha256sum "$temp_dir/$archive"); actual=${actual%% *}
  else
    fail 'Install shasum or sha256sum to verify the Node.js download.'
  fi
  [[ "$actual" = "$expected" ]] || fail 'Node.js checksum verification failed.'
  mkdir "$temp_dir/runtime"
  tar -xzf "$temp_dir/$archive" -C "$temp_dir/runtime" --strip-components=1
  "$temp_dir/runtime/bin/node" --version
  mkdir -p "$install_dir/runtime"
  cp -R "$temp_dir/runtime/." "$install_dir/runtime/"
  hash -r
fi
node_path=$(command -v node)

if ! command -v claude >/dev/null; then
  echo 'Installing Claude Code using the official native installer...'
  curl --fail --silent --show-error --location https://claude.ai/install.sh -o "$temp_dir/install-claude.sh"
  bash "$temp_dir/install-claude.sh" stable
  hash -r
fi
command -v claude >/dev/null || fail 'Claude Code was not found after installation.'
claude_dir=$(dirname -- "$(command -v claude)")

echo "Installing Claude FFF in $install_dir..."
if [[ "$source_dir" != "$install_dir" ]]; then
  for file in package.json server.mjs claude-fff.sh README.md install.sh; do
    cp "$source_dir/$file" "$install_dir/$file"
  done
  if [[ -f "$source_dir/package-lock.json" ]]; then
    cp "$source_dir/package-lock.json" "$install_dir/package-lock.json"
  fi
fi
if [[ -f "$install_dir/package-lock.json" ]]; then
  (cd -- "$install_dir" && npm ci --no-audit --no-fund)
else
  (cd -- "$install_dir" && npm install --no-audit --no-fund)
fi
(cd -- "$install_dir" && node --input-type=module -e 'import { FileFinder } from "@ff-labs/fff-node"; if (!FileFinder) process.exit(1)')
chmod +x "$install_dir/claude-fff.sh"

# Use a small wrapper rather than a symlink so the app can locate its server.
{
  printf '#!/bin/bash\n# Managed by claude-fff installer\n'
  printf 'export PATH=%q:%q:"$PATH"\n' "$(dirname -- "$node_path")" "$claude_dir"
  printf 'exec /bin/bash %q "$@"\n' "$install_dir/claude-fff.sh"
} > "$temp_dir/claude-fff"
chmod +x "$temp_dir/claude-fff"
cp "$temp_dir/claude-fff" "$bin_dir/claude-fff"

if [[ "$update_shell" = 1 ]]; then
  # Configure both supported shells, including login bash on macOS.
  for profile in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    path_line=$(printf 'export PATH=%q:"$PATH" # claude-fff PATH' "$bin_dir")
    if ! grep -qxF "$path_line" "$profile" 2>/dev/null; then
      [[ ! -e "$profile" ]] || cp -p "$profile" "$profile.claude-fff-backup-$(date +%Y%m%d%H%M%S)"
      if [[ -f "$profile" ]]; then
        sed '/# claude-fff PATH$/d' "$profile" > "$temp_dir/profile"
        cat "$temp_dir/profile" > "$profile"
      fi
      printf '\n%s\n' "$path_line" >> "$profile"
    fi
  done
fi
printf '\nInstalled! Open a new terminal, then run:\n  cd /path/to/project\n  claude-fff\n\nFor this terminal, run:\n  export PATH=%q:"$PATH"\n' "$bin_dir"
echo 'Claude Code will ask you to sign in if needed.'
