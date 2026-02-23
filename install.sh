#!/usr/bin/env bash
# Dev setup: install tools (Stow, Go, lazygit, etc.) and deploy dotfiles via GNU Stow.
# Run from the repo root after cloning.
# Idempotent: safe to run multiple times; backs up existing dotfiles once, then re-stows.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"
INSTALL_TOOLS=true
STOW_PACKAGES="zsh tmux nvim"
TMUX_PREFIX=""   # "local" = C-b, "remote" = C-a; set by --tmux-prefix or prompt

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --no-tools       Skip installing packages; only run stow to link dotfiles
  --tmux-prefix P  Tmux prefix: 'local' (Ctrl+B) or 'remote' (Ctrl+A).
                   If omitted, you will be prompted when stow runs.
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tools)       INSTALL_TOOLS=false ;;
    --tmux-prefix)
      shift
      [[ $# -gt 0 ]] || { echo "Missing argument for --tmux-prefix"; usage; exit 1; }
      if [[ "$1" == "local" || "$1" == "remote" ]]; then
        TMUX_PREFIX="$1"
      else
        echo "Unknown --tmux-prefix: $1 (use 'local' or 'remote')"; usage; exit 1
      fi
      ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "Unknown option: $1"; usage; exit 1 ;;
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
    git zsh tmux ca-certificates curl wget xz-utils
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

# --- Latest Neovim from GitHub (required for LazyVim; apt version is often too old) ---
install_nvim() {
  echo "Installing latest Neovim from GitHub..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL -o "$tmpdir/nvim-linux-x86_64.tar.gz" \
    https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
  sudo rm -rf /opt/nvim-linux-x86_64
  sudo tar -C /opt -xzf "$tmpdir/nvim-linux-x86_64.tar.gz"
  rm -rf "$tmpdir"
  if [[ ":$PATH:" != *":/opt/nvim-linux-x86_64/bin:"* ]]; then
    echo "  Add to PATH: export PATH=\"\$PATH:/opt/nvim-linux-x86_64/bin\" (e.g. in ~/.zshrc)"
  fi
  echo "Installed Neovim to /opt/nvim-linux-x86_64: $(/opt/nvim-linux-x86_64/bin/nvim --version | head -n1)"
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
# Generate .tmux.conf from template with chosen prefix (local = C-b, remote = C-a).
# Prompts every time unless --tmux-prefix is passed.
ensure_tmux_config() {
  local template="$REPO_ROOT/tmux/.tmux.conf.template"
  local out="$REPO_ROOT/tmux/.tmux.conf"
  if [[ -z "$TMUX_PREFIX" ]]; then
    if [[ -t 0 ]]; then
      echo "Tmux prefix: (1) local = Ctrl+B, (2) remote = Ctrl+A"
      read -r -p "Choose [1/2]: " choice
      case "$choice" in
        1) TMUX_PREFIX=local ;;
        2) TMUX_PREFIX=remote ;;
        *) echo "Defaulting to remote (Ctrl+A)."; TMUX_PREFIX=remote ;;
      esac
    else
      echo "No TTY: defaulting tmux prefix to remote (Ctrl+A). Use --tmux-prefix local for Ctrl+B."
      TMUX_PREFIX=remote
    fi
  fi
  local prefix_key unbind_key
  if [[ "$TMUX_PREFIX" == "local" ]]; then
    prefix_key="C-b"
    unbind_key="C-a"
  else
    prefix_key="C-a"
    unbind_key="C-b"
  fi
  sed -e "s/{{PREFIX_KEY}}/$prefix_key/g" -e "s/{{UNBIND_KEY}}/$unbind_key/g" \
    "$template" > "$out"
  echo "Tmux prefix set to $TMUX_PREFIX ($prefix_key)."
}

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
  ensure_tmux_config
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
    install_nvim
    install_oh_my_zsh
    install_go
    install_lazygit
  fi
  run_stow
  if tmux list-sessions &>/dev/null; then
    tmux source-file "$HOME_DIR/.tmux.conf" && echo "Reloaded tmux config in running server."
  fi
  echo "Done. Start a new shell or run: source ~/.zshrc"
}

main
