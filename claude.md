# Claude Instructions — SRE Initial Setup

## Project Overview

This repository contains `sre-setup.sh`, a non-interactive bootstrap script that provisions developer/SRE machines on **macOS**, **Ubuntu**, and **Fedora**. It sets up all common SRE tooling in a single run.

## Repository Structure

```
SRE-Initial-Setup/
├── sre-setup.sh   # Main bootstrap script
├── README.md      # User-facing documentation
└── claude.md      # This file — AI assistant context
```

## Script Conventions

- Written in **Bash** (`#!/usr/bin/env bash`) with `set -euo pipefail`
- Every tool installer follows this pattern:
  1. Section header via `log_section "Tool Name"`
  2. Skip if already installed (`command_exists`)
  3. Branch on `$OS` → `macos` | `linux`
  4. On Linux, branch on `$PKG_MANAGER` → `apt` | `dnf`
  5. Confirm success via `log_success`
- Failures are collected in `FAILED_INSTALLATIONS[]` and printed at the end — the script does **not** abort on individual tool failures
- Helper functions: `log_info`, `log_success`, `log_warn`, `log_error`, `log_section`, `command_exists`

## Installed Tools (as of last update)

| Tool | macOS | Ubuntu | Fedora |
|---|---|---|---|
| Git | brew | apt | dnf |
| GitHub CLI (`gh`) | brew | apt (keyring repo) | dnf (gh repo) |
| Ansible | brew | apt (PPA) | dnf |
| tfenv + Terraform | brew | git clone | git clone |
| pipenv | brew | pip / pipx | pip / pipx |
| kubectl | brew | apt (k8s repo) | dnf (k8s repo) |
| kubectx + kubens | brew | GitHub release binary | GitHub release binary |
| Visual Studio Code | brew cask | apt (MS repo) | dnf (MS repo) |
| Azure CLI | brew | apt (MS repo) | dnf (MS repo) |
| Docker + Compose v2 | brew cask | apt (Docker repo) | dnf (Docker repo) |
| Microsoft Edge | brew cask | apt (MS repo) | dnf (MS repo) |
| Claude Desktop | brew cask | _(web only)_ | _(web only)_ |
| Slack | brew cask | snap | snap / flatpak |
| Bitwarden | brew cask | snap / .deb | .rpm |
| TeamViewer | brew cask | .deb download | .rpm download |
| Remote Desktop | Windows App (brew) | Remmina (apt) | Remmina (dnf) |
| Spotify | brew cask | apt (Spotify repo) | snap / flatpak |
| Vim | brew | apt | dnf |
| Python debug tools | pip (user) | pip (user) | pip (user) |
| Linux system utils | — | apt | dnf |

### Python Debug Tools

`debugpy`, `ipdb`, `pdbpp`, `rich`, `icecream`, `py-spy`

### Linux System Utilities

`openssl`, `dnsutils` / `bind-utils`, `wget`, `telnet`, `zsh`

## VS Code Configuration

Beyond installing VS Code, the script also:

- **Installs extensions:** `anthropic.claude-code`, `PKief.material-icon-theme`, `azemoh.one-monokai`, `ms-vscode.powershell`, `ms-python.python`, `eamodio.gitlens`, `mhutchie.git-graph`
- **Writes `settings.json`** with icon theme, Git Graph, and formatter settings
- **Creates `~/Documents/projects.code-workspace`** with full workspace settings for all installed extensions

## Shell Setup

- **macOS**: default `zsh`, no changes
- **Linux**: installs Oh My Zsh, sets theme `apple`, plugins: `git docker kubectl terraform python ssh-agent`, changes default shell to `zsh`
- Completions added for: `kubectl`, `docker`, `gh`, `terraform`
- Slack autostart configured via LaunchAgent (macOS) or `.desktop` autostart entry (Linux)

## Key Functions

| Function | Purpose |
|---|---|
| `detect_os` | Sets `$OS`, `$DISTRO`, `$PKG_MANAGER` |
| `validate_sudo_once` | One-time sudo validation at start |
| `print_terminal_logo` | Prints OS banner (macOS 🍎 / Linux 🐧) |
| `install_homebrew` | Bootstraps Homebrew on macOS |
| `run_pre_install_updates` | Updates packages before installs |
| `run_post_install_maintenance` | Updates + cleans packages after installs |
| `set_system_locale_english` | Forces `en_US.UTF-8` locale |
| `configure_git_user` | Interactive git name/email config (skips if set) |
| `setup_ssh_github` | Generates ed25519 key, configures SSH, uploads to GitHub via `gh` |
| `install_vscode_extensions` | Installs predefined VS Code extensions |
| `configure_vscode_extensions` | Writes `settings.json` for VS Code |
| `configure_documents_workspace` | Creates `~/Documents/projects.code-workspace` |
| `install_shell_setup` | Installs and configures Oh My Zsh on Linux |
| `configure_zsh_completions` | Adds completions for kubectl, docker, gh, terraform |
| `enable_slack_autostart` | Configures Slack to start on login |
| `install_remote_desktop` | Installs Windows App (macOS) or Remmina (Linux) |
| `install_linux_utils` | Installs openssl, dnsutils, wget, telnet, zsh |
| `print_summary` | Final report of installed / failed tools + elapsed time |
| `prompt_reboot` | Asks user to reboot; runs `countdown_reboot` if confirmed |

## How to Run

```bash
chmod +x ./sre-setup.sh
./sre-setup.sh
```

## Editing Guidelines for AI

- **Do not break the OS/distro branching structure** — every installer must handle `macos`, `apt`, and `dnf` paths
- **Keep non-interactive** — no prompts inside tool installers (only `configure_git_user` and `setup_ssh_github` are interactive by design)
- **Idempotent** — each installer must check if the tool is already present and skip gracefully
- When adding a new tool, follow the existing pattern and add it to the `main` function call sequence
- `FAILED_INSTALLATIONS` and `SKIPPED_INSTALLATIONS` arrays must be updated appropriately on errors/skips
- Test changes on the three supported platforms before merging

