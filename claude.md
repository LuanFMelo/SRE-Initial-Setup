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
| GitHub CLI (gh) | brew | apt (keyring) | dnf (repo) |
| Ansible | brew | apt (PPA) | dnf |
| tfenv + Terraform | brew | git clone | git clone |
| pipenv | brew | pip/pipx | pip/pipx |
| kubectl | brew | apt (k8s repo) | dnf (k8s repo) |
| kubectx + kubens | brew | GitHub release | GitHub release |
| Visual Studio Code | brew cask | apt (MS repo) | dnf (MS repo) |
| Docker + Compose | brew cask | apt (Docker repo) | dnf (Docker repo) |
| Azure CLI | brew | apt (MS repo) | dnf (MS repo) |
| Claude Desktop/CLI | brew cask | .deb download | n/a |
| Slack | brew cask | apt | dnf |
| Bitwarden | brew cask | apt | dnf |
| Spotify | brew cask | snap | n/a |
| TeamViewer | brew cask | .deb download | .rpm download |
| Microsoft Edge | brew cask | apt (MS repo) | dnf (MS repo) |
| VirtualBox | brew cask | apt | dnf |
| Vim | brew | apt | dnf |
| Python debug tools | pip | pip | pip |

## Shell Setup

- **macOS**: default `zsh`, no changes
- **Linux**: installs Oh My Zsh, sets theme `apple`, plugins: `git docker kubectl terraform python ssh-agent`
- Completions added for: `kubectl`, `docker`, `gh`, `terraform`

## Key Functions

| Function | Purpose |
|---|---|
| `detect_os` | Sets `$OS`, `$DISTRO`, `$PKG_MANAGER` |
| `validate_sudo_once` | One-time sudo validation at start |
| `run_pre_install_updates` | Updates packages before installs |
| `run_post_install_maintenance` | Updates + cleans packages after installs |
| `configure_git_user` | Interactive git name/email config |
| `setup_ssh_github` | Generates ed25519 key, configures SSH, uploads to GitHub |
| `set_system_locale_english` | Forces `en_US.UTF-8` locale |
| `print_install_summary` | Final report of OK/FAILED/SKIPPED |

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
