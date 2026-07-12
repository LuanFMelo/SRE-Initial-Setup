# SRE Initial Setup

Bootstrap script for macOS, Ubuntu, and Fedora developer/SRE machines.

> For AI assistant context and editing guidelines, see [claude.md](claude.md).

## Supported Operating Systems

- macOS
- Ubuntu
- Fedora

## What This Script Does

The script in [sre-setup.sh](sre-setup.sh) automates:

- OS detection and platform banner output
- Package updates before installation
- Installation/configuration of common SRE tools
- Zsh/Oh My Zsh setup and shell completions
- Package updates and cleanup after installation
- Final install summary

## Installed Tools

Primary tools configured by the script include:

- Git
- GitHub CLI (gh)
- Ansible
- tfenv + Terraform
- pipenv
- kubectl
- kubectx + kubens
- Visual Studio Code
- VS Code extensions (predefined list)
- Spotify
- TeamViewer
- Azure CLI
- Remote Desktop tools
- Python debugging tools (debugpy, ipdb, pdbpp, rich, icecream, py-spy)
- Claude desktop/CLI handling
- Docker + Docker Compose
- Microsoft Edge
- Slack
- Bitwarden
- Vim
- VirtualBox

## Shell Behavior

- macOS: keeps default zsh
- Linux: installs and configures Oh My Zsh with:
  - Theme: `apple`
  - Plugins: `git docker kubectl terraform python ssh-agent`
- Configures zsh completions for kubectl, docker, gh, and terraform when available

## Package Maintenance

The script performs maintenance in two phases:

1. Pre-install update
   - macOS: `brew update && brew upgrade`
   - Ubuntu: `apt update && apt upgrade`
   - Fedora: `dnf upgrade --refresh`
2. Post-install update and cleanup
   - macOS: `brew update && brew upgrade && brew cleanup -s`
   - Ubuntu: `apt upgrade`, `autoremove`, `autoclean`, `clean`
   - Fedora: `dnf upgrade --refresh`, `autoremove`, `clean all`

## Requirements

- Internet access
- `sudo` privileges for package installation and system changes
- Bash shell

## Usage

Run from the repository root:

```bash
chmod +x ./sre-setup.sh
./sre-setup.sh
```

## Notes

- The script is intentionally scoped to macOS, Ubuntu, and Fedora.
- Some tools may still require login/auth steps after install (for example gh, Azure CLI, Bitwarden).
- Open a new terminal session after completion to ensure PATH and shell changes are loaded.

## Contributing / AI Assistance

When using an AI assistant (e.g. Claude) to edit this repository, refer to [claude.md](claude.md) for project conventions, tool inventory, and editing guidelines.
