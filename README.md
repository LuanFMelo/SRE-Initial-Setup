# SRE Initial Setup

Bootstrap script for macOS, Ubuntu, and Fedora developer/SRE machines.

> For AI assistant context and editing guidelines, see [claude.md](claude.md).

## Supported Operating Systems

| OS | Package Manager |
|---|---|
| macOS | Homebrew |
| Ubuntu | apt |
| Fedora | dnf |

## What This Script Does

The script [sre-setup.sh](sre-setup.sh) runs fully non-interactive and automates:

1. OS and distro detection
2. Sudo validation (one-time at startup)
3. System locale set to `en_US.UTF-8`
4. Pre-install package updates
5. Installation and configuration of all SRE tools (see below)
6. Zsh / Oh My Zsh setup with completions (Linux)
7. Post-install update and cleanup
8. Final installation summary with elapsed time
9. Optional system reboot with countdown

## Installed Tools

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

Installed via `pip --user`: `debugpy`, `ipdb`, `pdbpp`, `rich`, `icecream`, `py-spy`

### Linux System Utilities

`openssl`, `dnsutils` / `bind-utils`, `wget`, `telnet`, `zsh`

## VS Code Configuration

Beyond installing VS Code, the script also:

- **Installs extensions:** `anthropic.claude-code`, `PKief.material-icon-theme`, `azemoh.one-monokai`, `ms-vscode.powershell`, `ms-python.python`, `eamodio.gitlens`, `mhutchie.git-graph`
- **Writes `settings.json`** with icon theme, Git Graph, and formatter settings
- **Creates `~/Documents/projects.code-workspace`** with full workspace settings for all installed extensions

## Git & SSH Setup

- Prompts for name and email to configure `git config --global` (only if not already set)
- Generates an `ed25519` SSH key at `~/.ssh/id_ed25519` (skips if already present)
- Configures `~/.ssh/config` for `github.com`
- Uploads the public key to GitHub via `gh ssh-key add` (requires `gh auth login`)

## Shell Behavior

- **macOS:** keeps default `zsh`, no changes
- **Linux:** installs Oh My Zsh with:
  - Theme: `apple`
  - Plugins: `git docker kubectl terraform python ssh-agent`
  - Default shell changed to `zsh`
- **Completions configured for:** `kubectl`, `docker`, `gh`, `terraform`

Slack is configured to start automatically on login (LaunchAgent on macOS, `.desktop` autostart on Linux).

## Package Maintenance

| Phase | macOS | Ubuntu | Fedora |
|---|---|---|---|
| Pre-install | `brew update && brew upgrade` | `apt update && apt upgrade` | `dnf upgrade --refresh` |
| Post-install | `brew update && brew upgrade && brew cleanup -s` | `apt upgrade`, `autoremove`, `autoclean`, `clean` | `dnf upgrade --refresh`, `autoremove`, `clean all` |

## Requirements

- Internet access
- `sudo` privileges
- Bash shell

## Usage

```bash
chmod +x ./sre-setup.sh
./sre-setup.sh
```

## Notes

- The script is intentionally scoped to macOS, Ubuntu, and Fedora.
- Some tools require manual auth after install: `gh auth login`, `az login`, Bitwarden vault unlock.
- Open a new terminal after completion to reload PATH and shell changes.
- On macOS, setting Microsoft Edge as the default browser must be done manually via System Settings → General → Default web browser.

## Contributing / AI Assistance

When using an AI assistant (e.g. Claude) to edit this repository, refer to [claude.md](claude.md) for project conventions, tool inventory, and editing guidelines.
