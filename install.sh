#!/usr/bin/env bash
# Dev setup: install tools (Stow, Go, lazygit, gh, etc.) and deploy dotfiles via GNU Stow.
# Run from the repo root after cloning.
# Idempotent: safe to run multiple times; backs up existing dotfiles once, then re-stows.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"
INSTALL_TOOLS=true
STOW_PACKAGES="zsh tmux nvim"
TMUX_PREFIX="" # "local" = C-b, "remote" = C-a; set by --tmux-prefix or prompt
GIT_USER_EMAIL="anhdt1911.work@gmail.com"
GIT_USER_NAME="Anh"
DISTRO_FAMILY=unknown # set by detect_distro: "debian", "arch", or "unknown"

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
  --no-tools) INSTALL_TOOLS=false ;;
  --tmux-prefix)
    shift
    [[ $# -gt 0 ]] || {
      echo "Missing argument for --tmux-prefix"
      usage
      exit 1
    }
    if [[ "$1" == "local" || "$1" == "remote" ]]; then
      TMUX_PREFIX="$1"
    else
      echo "Unknown --tmux-prefix: $1 (use 'local' or 'remote')"
      usage
      exit 1
    fi
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# --- Distro detection ---
# Sets DISTRO_FAMILY to "debian", "arch", or "unknown" based on /etc/os-release
# (with a fallback to checking for apt-get / pacman on PATH).
detect_distro() {
  local id_like="" id=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi
  case " $id $id_like " in
  *" debian "* | *" ubuntu "*) DISTRO_FAMILY=debian ;;
  *" arch "*) DISTRO_FAMILY=arch ;;
  *)
    if command -v apt-get &>/dev/null; then
      DISTRO_FAMILY=debian
    elif command -v pacman &>/dev/null; then
      DISTRO_FAMILY=arch
    else
      DISTRO_FAMILY=unknown
    fi
    ;;
  esac
  echo "Detected distro family: $DISTRO_FAMILY"
}

# --- Package install (Debian/Ubuntu) ---
install_apt_packages() {
  echo "Installing apt packages..."
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    git zsh tmux ca-certificates curl wget xz-utils
  if ! command -v stow &>/dev/null; then
    sudo apt-get install -y --no-install-recommends stow
  fi
}

configure_git_identity() {
  if ! command -v git &>/dev/null; then
    echo "git not found; skipping global user.email / user.name."
    return
  fi
  local answer use_default email_input name_input
  if [[ -t 0 ]]; then
    read -r -p "Configure global git identity now? [y/N] " answer
    case "${answer,,}" in
    y | yes)
      read -r -p "Use default git identity \"$GIT_USER_NAME\" <$GIT_USER_EMAIL>? [Y/n] " use_default
      case "${use_default,,}" in
      n | no)
        read -r -p "Enter git user.email: " email_input
        read -r -p "Enter git user.name: " name_input
        if [[ -z "$email_input" || -z "$name_input" ]]; then
          echo "Email/name cannot be empty; skipping git global user.email / user.name."
          return
        fi
        GIT_USER_EMAIL="$email_input"
        GIT_USER_NAME="$name_input"
        ;;
      *)
        ;;
      esac
      ;;
    *)
      echo "Skipping git global user.email / user.name."
      return
      ;;
    esac
  else
    echo "No TTY: using default git identity $GIT_USER_NAME <$GIT_USER_EMAIL>."
  fi
  git config --global user.email "$GIT_USER_EMAIL"
  git config --global user.name "$GIT_USER_NAME"
  echo "Git identity set: $GIT_USER_NAME <$GIT_USER_EMAIL>"
}

set_default_shell_to_zsh() {
  if ! command -v zsh &>/dev/null; then
    echo "zsh not found; skipping default shell update."
    return
  fi

  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="${SHELL:-}"

  if [[ "$current_shell" == "$zsh_path" ]]; then
    echo "Default shell is already zsh: $zsh_path"
    return
  fi

  echo "Setting default shell to zsh: $zsh_path"
  if chsh -s "$zsh_path" "$USER"; then
    echo "Default shell updated to zsh."
  else
    echo "Failed to update default shell automatically. Run manually: chsh -s $zsh_path $USER"
  fi
}
# --- Package install (Arch Linux) ---
install_pacman_packages() {
  echo "Installing pacman packages..."
  sudo pacman -Sy --needed --noconfirm \
    git zsh tmux ca-certificates curl wget xz
  if ! command -v stow &>/dev/null; then
    sudo pacman -S --needed --noconfirm stow
  fi
}

# --- Package install dispatcher ---
install_base_packages() {
  case "$DISTRO_FAMILY" in
  debian) install_apt_packages ;;
  arch) install_pacman_packages ;;
  *)
    echo "Unsupported distro (no apt-get or pacman found); skipping package install."
    echo "Install manually: git zsh tmux ca-certificates curl wget xz stow"
    ;;
  esac
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
  go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
  [[ -n "$go_version" ]] || {
    echo "Failed to get Go version"
    return 1
  }
  local arch
  arch="$(uname -m)"
  case "$arch" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "Unsupported arch: $arch"
    return 1
    ;;
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
  x86_64) arch=x86_64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "Unsupported arch: $arch"
    return 1
    ;;
  esac
  local latest
  latest="$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest)"
  local tag
  tag="$(echo "$latest" | grep -oP '"tag_name":\s*"\K[^"]+')"
  [[ -n "$tag" ]] || {
    echo "Failed to get lazygit release tag"
    return 1
  }
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

# --- Latest GitHub CLI (gh) from GitHub releases ---
install_gh_cli() {
  if command -v gh &>/dev/null; then
    echo "gh already installed: $(gh --version 2>/dev/null | head -n1 || true)"
    return
  fi
  echo "Installing latest GitHub CLI (gh)..."
  mkdir -p "$HOME_DIR/.local/bin"
  local arch
  arch="$(uname -m)"
  case "$arch" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "Unsupported arch: $arch"
    return 1
    ;;
  esac
  local latest tag version url tmpdir
  latest="$(curl -s https://api.github.com/repos/cli/cli/releases/latest)"
  tag="$(echo "$latest" | grep -oP '"tag_name":\s*"\K[^"]+')"
  [[ -n "$tag" ]] || {
    echo "Failed to get gh release tag"
    return 1
  }
  version="${tag#v}"
  url="https://github.com/cli/cli/releases/download/${tag}/gh_${version}_linux_${arch}.tar.gz"
  tmpdir="$(mktemp -d)"
  curl -fsSL -o "$tmpdir/gh.tar.gz" "$url"
  tar -xzf "$tmpdir/gh.tar.gz" -C "$tmpdir"
  mv "$tmpdir/gh_${version}_linux_${arch}/bin/gh" "$HOME_DIR/.local/bin/gh"
  chmod +x "$HOME_DIR/.local/bin/gh"
  rm -rf "$tmpdir"
  echo "Installed gh $tag to $HOME_DIR/.local/bin"
}

# --- Tmux Plugin Manager (TPM) + plugins (tmux-resurrect, tmux-continuum) ---
install_tmux_tpm() {
  local tpm_dir="$HOME_DIR/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    echo "TPM (Tmux Plugin Manager) already installed."
    return
  fi
  echo "Installing TPM (Tmux Plugin Manager)..."
  mkdir -p "$(dirname "$tpm_dir")"
  git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir"
  echo "TPM installed. Start tmux and press prefix+I to install plugins (tmux-resurrect, tmux-continuum)."
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
      *)
        echo "Defaulting to remote (Ctrl+A)."
        TMUX_PREFIX=remote
        ;;
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
    "$template" >"$out"
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
    echo "GNU Stow not found. Install it (apt install stow / pacman -S stow) and run: stow -t \$HOME zsh tmux nvim"
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
  detect_distro
  if [[ "$INSTALL_TOOLS" == true ]]; then
    install_base_packages
    install_nvim
    install_oh_my_zsh
    install_go
    install_lazygit
    install_gh_cli
  fi
  set_default_shell_to_zsh
  configure_git_identity
  run_stow
  install_tmux_tpm
  if tmux list-sessions &>/dev/null; then
    tmux source-file "$HOME_DIR/.tmux.conf" && echo "Reloaded tmux config in running server."
  fi
  echo "Done. Starting zsh..."
  exec zsh
}

main
