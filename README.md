# Dev Setup

Dotfiles and config for a quick dev environment, managed with **GNU Stow**. Includes Zsh (Oh My Zsh), Tmux, Neovim (LazyVim), **Go**, and **lazygit**.

## Layout (Stow packages)

| Package | Contents |
|---------|----------|
| `zsh/`  | `.zshrc` — Oh My Zsh, zsh-autosuggestions, PATH for Go and lazygit |
| `tmux/` | `.tmux.conf` — vi keys, mouse, prefix `C-a`, pane resize H/J/K/L |
| `nvim/` | `.config/nvim/` — LazyVim (init.lua, plugins, keymaps, options) |

## Quick start (after cloning)

From the repo root:

```bash
./install.sh
```

This will:

1. **Install apt packages**: `stow`, `git`, `zsh`, `tmux`, `neovim`, `curl`, etc.
2. **Install Oh My Zsh** and the `zsh-autosuggestions` plugin (if not present).
3. **Install latest Go** from [go.dev](https://go.dev/dl/) to `/usr/local/go`.
4. **Install latest lazygit** from [GitHub releases](https://github.com/jesseduffield/lazygit/releases) to `~/.local/bin`.
5. **Run Stow** to symlink `zsh`, `tmux`, and `nvim` into your home directory.

Then start a new shell or run `source ~/.zshrc`.

## Install options

```bash
./install.sh --help
```

- `--no-tools` — Skip installing packages; only run `stow` to link dotfiles (use when tools are already installed).

## Stow commands

Link all packages (same as what `install.sh` does):

```bash
stow -t ~ zsh tmux nvim
```

Link or unlink a single package:

```bash
stow -t ~ zsh          # link zsh
stow -t ~ -D zsh       # unlink zsh
```

## Requirements

- Linux (script uses `apt`; adapt for other distros or macOS if needed).
- Bash for `install.sh`.

## Manual setup (no script)

1. Install: `stow`, `zsh`, `tmux`, `neovim`, [Go](https://go.dev/dl/), [lazygit](https://github.com/jesseduffield/lazygit/releases), Oh My Zsh, and `zsh-autosuggestions`.
2. From this repo: `stow -t ~ zsh tmux nvim`.
