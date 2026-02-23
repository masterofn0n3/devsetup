#!/usr/bin/env bash
# Dev setup: install tools (Stow, Go, lazygit, etc.) and deploy dotfiles via GNU Stow.
# Run from the repo root after cloning.
# Idempotent: safe to run multiple times; backs up existing dotfiles once, then re-stows.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"
INSTALL_TOOLS=true
STOW_PACKAGES="zsh tmux nvim"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --no-tools    Skip installing packages; only run stow to link dotfiles
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tools) INSTALL_TOOLS=false ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# --- Package install (Debian/Ubuntu) ---
install_apt_packages() {
  if ! command -v apt-get &>/dev/null; then
    echo "apt-get not found; skipping. Use --no-tools and install stow manually."
    return
  fi
  echo "Installing apt packages..."
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    git zsh tmux neovim ca-certificates curl wget xz-utils
  if ! command -v stow &>/dev/null; then
    sudo apt-get install -y --no-install-recommends stow
  fi
}

# --- Oh My Zsh + zsh-autosuggestions ---
install_oh_my_zsh() {
  if [[ -d "$HOME_DIR/.oh-my-zsh" ]]; then
    echo "Oh My Zsh already installed."
  else
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi
  local custom_plugins="$HOME_DIR/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  if [[ ! -d "$custom_plugins" ]]; then
    echo "Installing zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins"
  else
    echo "zsh-autosuggestions already installed."
  fi
}

# --- Latest Go from go.dev ---
install_go() {
  if command -v go &>/dev/null; then
    echo "Go already installed: $(go version)"
    return
  fi
  echo "Installing latest Go..."
  local go_version
  go_version="$(curl -sL https://go.dev/VERSION?m=text)"
  [[ -n "$go_version" ]] || { echo "Failed to get Go version"; return 1; }
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)       echo "Unsupported arch: $arch"; return 1 ;;
  esac
  local tarball="${go_version}.linux-${arch}.tar.gz"
  local url="https://go.dev/dl/${tarball}"
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL -o "$tmpdir/$tarball" "$url"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmpdir/$tarball"
  rm -rf "$tmpdir"
  echo "Installed $go_version to /usr/local/go"
}

# --- Latest lazygit from GitHub releases ---
install_lazygit() {
  if command -v lazygit &>/dev/null; then
    echo "lazygit already installed: $(lazygit --version 2>/dev/null || true)"
    return
  fi
  echo "Installing latest lazygit..."
  mkdir -p "$HOME_DIR/.local/bin"
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)       echo "Unsupported arch: $arch"; return 1 ;;
  esac
  local latest
  latest="$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest)"
  local tag
  tag="$(echo "$latest" | grep -oP '"tag_name":\s*"\K[^"]+')"
  [[ -n "$tag" ]] || { echo "Failed to get lazygit release tag"; return 1; }
  local version="${tag#v}"
  local url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${version}_Linux_${arch}.tar.gz"
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL -o "$tmpdir/lazygit.tar.gz" "$url"
  tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir"
  mv "$tmpdir/lazygit" "$HOME_DIR/.local/bin/lazygit"
  chmod +x "$HOME_DIR/.local/bin/lazygit"
  rm -rf "$tmpdir"
  echo "Installed lazygit $tag to $HOME_DIR/.local/bin"
}

# --- Stow dotfiles into $HOME ---
# Backup existing file/dir if it exists and is not already our symlink (idempotency).
backup_if_not_our_link() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return
  fi
  if [[ -L "$path" ]]; then
    local dest
    dest="$(readlink -f "$path" 2>/dev/null || readlink "$path")"
    if [[ "$dest" == "$REPO_ROOT"/* ]]; then
      return
    fi
  fi
  local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
  echo "  Backup existing: $path -> $backup"
  mv "$path" "$backup"
}

run_stow() {
  if ! command -v stow &>/dev/null; then
    echo "GNU Stow not found. Install it (e.g. apt install stow) and run: stow -t \$HOME zsh tmux nvim"
    return 1
  fi
  echo "Preparing dotfiles (backup existing if needed)..."
  backup_if_not_our_link "$HOME_DIR/.zshrc"
  backup_if_not_our_link "$HOME_DIR/.tmux.conf"
  backup_if_not_our_link "$HOME_DIR/.config/nvim"
  echo "Linking dotfiles with stow -t $HOME_DIR $STOW_PACKAGES ..."
  cd "$REPO_ROOT"
  # Unstow first so re-runs and repo moves are idempotent (links point to current repo).
  stow -t "$HOME_DIR" -D $STOW_PACKAGES 2>/dev/null || true
  stow -t "$HOME_DIR" -v $STOW_PACKAGES
  echo "Stow done."
}

# --- Main ---
main() {
  echo "Dev setup: $REPO_ROOT -> $HOME_DIR"
  if [[ "$INSTALL_TOOLS" == true ]]; then
    install_apt_packages
    install_oh_my_zsh
    install_go
    install_lazygit
  fi
  run_stow
  echo "Done. Start a new shell or run: source ~/.zshrc"
}

main
