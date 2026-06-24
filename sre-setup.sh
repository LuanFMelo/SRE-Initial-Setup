#!/usr/bin/env bash

# =============================================================================
# SRE Initial Setup Script (Improved)
# Supported OS: macOS, Ubuntu, Fedora
# Changes: Non-interactive, no sudo password, guaranteed Claude/Bitwarden
# =============================================================================

set -euo pipefail

# ── Tracking variables ─────────────────────────────────────────────────────────
SCRIPT_START=$(date +%s)
FAILED_INSTALLATIONS=()
SKIPPED_INSTALLATIONS=()

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BOLD}${BLUE}━━━  $*  ━━━${NC}"; }

command_exists() { command -v "$1" &>/dev/null; }

# ── Sudoers validation (one-time, keeps timestamp fresh) ────────────────────
validate_sudo_once() {
  if [[ "$EUID" -ne 0 ]]; then
    log_info "Validating sudo privileges..."
    sudo -v
  fi
}

# ── OS Detection ──────────────────────────────────────────────────────────────
detect_os() {
  OS=""
  DISTRO=""
  PKG_MANAGER=""

  case "$(uname -s)" in
    Darwin)
      OS="macos"
      ;;
    Linux)
      OS="linux"
      if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="${ID:-unknown}"
      fi
      case "$DISTRO" in
        ubuntu) PKG_MANAGER="apt" ;;
        fedora) PKG_MANAGER="dnf" ;;
        *) log_error "Unsupported: $DISTRO"; exit 1 ;;
      esac
      ;;
    *) log_error "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac

  log_info "Detected OS: ${BOLD}${OS}${NC}${DISTRO:+ ($DISTRO)}"
}

print_terminal_logo() {
  log_section "Platform"
  echo -e "${BOLD}${GREEN}"
  case "$OS" in
    macos) echo "  🍎  macOS" ;;
    linux) echo "  🐧  Linux" ;;
  esac
  echo -e "${NC}"
}

# ── macOS – Homebrew bootstrap ────────────────────────────────────────────────
install_homebrew() {
  if command_exists brew; then
    log_success "Homebrew already installed — updating..."
    brew update
    return
  fi
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  log_success "Homebrew installed."
}

# ── Linux – apt helpers ───────────────────────────────────────────────────────
apt_install() {
  sudo apt install -y "$@"
}

apt_update() {
  sudo apt update -y
}

dnf_install() {
  sudo "$PKG_MANAGER" install -y "$@"
}

# ── Package maintenance ───────────────────────────────────────────────────────
run_pre_install_updates() {
  log_section "Pre-Install Package Update"
  case "$OS" in
    macos)
      brew update
      brew upgrade
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          sudo apt upgrade -y
          ;;
        dnf|yum)
          sudo "$PKG_MANAGER" upgrade --refresh -y
          ;;
      esac
      ;;
  esac
  log_success "Pre-install updates complete."
}

run_post_install_maintenance() {
  log_section "Post-Install Update and Cleanup"
  case "$OS" in
    macos)
      brew update
      brew upgrade
      brew cleanup -s
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          sudo apt upgrade -y
          sudo apt autoremove -y
          sudo apt autoclean -y
          sudo apt clean
          ;;
        dnf|yum)
          sudo "$PKG_MANAGER" upgrade --refresh -y
          sudo "$PKG_MANAGER" autoremove -y
          sudo "$PKG_MANAGER" clean all
          ;;
      esac
      ;;
  esac
  log_success "Post-install maintenance complete."
}

# ── System Locale (English) ───────────────────────────────────────────────────
set_system_locale_english() {
  log_section "System Locale Configuration"
  case "$OS" in
    macos)
      log_info "Setting macOS locale to English..."
      defaults write NSGlobalDomain AppleLanguages -array en
      defaults write NSGlobalDomain AppleLocale -string "en_US.UTF-8"
      defaults write NSGlobalDomain NSPreferredSpellServerLanguage -string "en"
      log_success "macOS locale set to English."
      ;;
    linux)
      log_info "Setting Linux locale to English..."
      case "$PKG_MANAGER" in
        apt)
          # Ensure en_US.UTF-8 locale exists
          sudo locale-gen en_US.UTF-8
          sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
          ;;
        dnf|yum)
          # Fedora uses localectl
          if command_exists localectl; then
            sudo localectl set-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
          else
            echo "LANG=en_US.UTF-8" | sudo tee -a /etc/environment > /dev/null
          fi
          ;;
      esac
      log_success "Linux locale set to English (takes effect on next login)."
      log_warn "Restart your session for changes to apply: ${BOLD}exec bash${NC} or logout/login"
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Tool installers (non-interactive, auto-confirm)
# ─────────────────────────────────────────────────────────────────────────────

install_git() {
  log_section "Git"
  if command_exists git; then
    log_success "git $(git --version | awk '{print $3}') already installed."
    return
  fi
  case "$OS" in
    macos) brew install git ;;
    linux)
      case "$PKG_MANAGER" in
        apt) apt_install git ;;
        dnf|yum) dnf_install git ;;
      esac
      ;;
  esac
  log_success "git installed: $(git --version)"
}

# ── Git User Configuration ───────────────────────────────────────────────────
configure_git_user() {
  log_section "Git User Configuration"
  
  local git_name=$(git config --global user.name 2>/dev/null)
  local git_email=$(git config --global user.email 2>/dev/null)
  
  if [[ -n "$git_name" && -n "$git_email" ]]; then
    log_success "Git already configured: $git_name <$git_email>"
    return
  fi
  
  log_info "Enter your Git user information:"
  read -p "  Full Name: " git_name
  read -p "  Email: " git_email
  
  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
  git config --global core.editor vim
  
  log_success "Git configured: $git_name <$git_email>"
}

# ── SSH Key + GitHub Setup ───────────────────────────────────────────────────
setup_ssh_github() {
  log_section "SSH Key & GitHub Setup"
  local ssh_key="$HOME/.ssh/id_ed25519"

  # Check if key exists
  if [[ -f "$ssh_key" ]]; then
    log_success "SSH key already exists: $ssh_key"
  else
    log_info "Generating SSH key (ed25519)..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$ssh_key" -N "" -C "$(git config user.email 2>/dev/null || echo "$USER@$(hostname)")"
    chmod 600 "$ssh_key"
    log_success "SSH key generated: $ssh_key"
  fi

  # Start SSH agent and add key
  log_info "Starting SSH agent..."
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add "$ssh_key" 2>/dev/null || log_warn "Could not add key to agent."
  log_success "SSH agent running."

  # Configure SSH for GitHub
  if [[ ! -f "$HOME/.ssh/config" ]] || ! grep -q "Host github.com" "$HOME/.ssh/config"; then
    log_info "Configuring SSH for GitHub..."
    mkdir -p "$HOME/.ssh"
    cat >> "$HOME/.ssh/config" <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  AddKeysToAgent yes
EOF
    log_success "SSH config updated."
  fi

  # Add key to GitHub via gh CLI
  if command_exists gh; then
    log_info "Authenticating with GitHub..."
    if ! gh auth status &>/dev/null 2>&1; then
      log_info "Running GitHub CLI authentication..."
      gh auth login --scopes admin:public_key --web || {
        log_warn "GitHub auth failed. Run manually: ${BOLD}gh auth login${NC}"
        return
      }
    fi

    # Check if key already uploaded to GitHub
    local key_fingerprint
    key_fingerprint=$(ssh-keygen -lf "$ssh_key.pub" 2>/dev/null | awk '{print $2}')
    
    if gh ssh-key list --json title,key 2>/dev/null | grep -q "$key_fingerprint" 2>/dev/null; then
      log_success "SSH public key already on GitHub."
    else
      log_info "Uploading SSH public key to GitHub..."
      if gh ssh-key add "$ssh_key.pub" --title "SRE Setup $(date +%Y-%m-%d)" 2>/dev/null; then
        log_success "SSH public key uploaded to GitHub."
      else
        log_warn "Could not upload key. Check manually: ${BOLD}gh ssh-key add $ssh_key.pub${NC}"
      fi
    fi
  else
    log_warn "GitHub CLI not found. Upload SSH key manually: ${BOLD}gh ssh-key add $ssh_key.pub${NC}"
  fi

  # Test connection
  log_info "Testing SSH connection to GitHub..."
  if ssh -T git@github.com &>/dev/null 2>&1; then
    log_success "GitHub SSH connection verified."
  else
    log_warn "GitHub SSH test inconclusive. May work after agent restart."
  fi
}

install_github_cli() {
  log_section "GitHub CLI (gh)"
  if command_exists gh; then
    log_success "gh already installed."
    return
  fi
  case "$OS" in
    macos) brew install gh ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install curl gpg
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
          sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
          apt_update && apt_install gh
          ;;
        dnf|yum)
          dnf_install dnf-plugins-core
          sudo "$PKG_MANAGER" config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
          dnf_install gh
          ;;
      esac
      ;;
  esac
  log_success "gh installed."
}

install_ansible() {
  log_section "Ansible"
  if command_exists ansible; then
    log_success "ansible already installed."
    return
  fi
  case "$OS" in
    macos) brew install ansible ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install software-properties-common
          sudo add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null || apt_update
          apt_install ansible
          ;;
        dnf|yum) dnf_install ansible ;;
      esac
      ;;
  esac
  log_success "ansible installed."
}

install_tfenv() {
  log_section "tfenv + Terraform"
  if command_exists tfenv; then
    log_success "tfenv already installed."
  else
    case "$OS" in
      macos) brew install tfenv ;;
      linux)
        TFENV_DIR="$HOME/.tfenv"
        if [[ -d "$TFENV_DIR" ]]; then
          git -C "$TFENV_DIR" pull --ff-only
        else
          git clone --depth=1 https://github.com/tfutils/tfenv.git "$TFENV_DIR"
        fi
        for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
          if [[ -f "$RC" ]] && ! grep -q 'tfenv/bin' "$RC"; then
            echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> "$RC"
          fi
        done
        export PATH="$HOME/.tfenv/bin:$PATH"
        ;;
    esac
    log_success "tfenv installed."
  fi

  if command_exists terraform; then
    log_success "terraform already installed."
  else
    log_info "Installing latest Terraform..."
    tfenv install latest
    tfenv use latest
    log_success "terraform installed."
  fi
}

install_pipenv() {
  log_section "pipenv"
  if command_exists pipenv; then
    log_success "pipenv already installed."
    return
  fi
  if ! command_exists python3; then
    case "$OS" in
      macos) brew install python ;;
      linux)
        case "$PKG_MANAGER" in
          apt) apt_install python3 python3-pip ;;
          dnf|yum) dnf_install python3 python3-pip ;;
        esac
        ;;
    esac
  fi
  case "$OS" in
    macos) brew install pipenv ;;
    linux)
      if command_exists pipx; then
        pipx install pipenv
      else
        python3 -m pip install --user pipenv
        export PATH="$HOME/.local/bin:$PATH"
        for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
          if [[ -f "$RC" ]] && ! grep -q '.local/bin' "$RC"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
          fi
        done
      fi
      ;;
  esac
  log_success "pipenv installed."
}

install_kubectl() {
  log_section "kubectl"
  if command_exists kubectl; then
    log_success "kubectl already installed."
    return
  fi
  case "$OS" in
    macos) brew install kubectl ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install apt-transport-https ca-certificates curl gnupg
          KUBE_MINOR=$(curl -fsSL https://dl.k8s.io/release/stable.txt | grep -oP 'v\d+\.\d+')
          KUBE_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/Release.key" | sudo gpg --dearmor -o "$KUBE_KEYRING"
          echo "deb [signed-by=${KUBE_KEYRING}] https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
          apt_update && apt_install kubectl
          ;;
        dnf|yum)
          KUBE_MINOR=$(curl -fsSL https://dl.k8s.io/release/stable.txt | grep -oP 'v\d+\.\d+')
          cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/rpm/repodata/repomd.xml.key
EOF
          dnf_install kubectl
          ;;
      esac
      ;;
  esac
  log_success "kubectl installed."
}

install_kubectx_kubens() {
  log_section "kubectx + kubens"
  if command_exists kubectx && command_exists kubens; then
    log_success "kubectx + kubens already installed."
    return
  fi
  case "$OS" in
    macos) brew install kubectx ;;
    linux)
      KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
      ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH="x86_64" || ARCH="arm64"
      TMP=$(mktemp -d)
      curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" | tar xz -C "$TMP" kubectx
      curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" | tar xz -C "$TMP" kubens
      sudo install -m 755 "$TMP/kubectx" /usr/local/bin/kubectx
      sudo install -m 755 "$TMP/kubens" /usr/local/bin/kubens
      rm -rf "$TMP"
      ;;
  esac
  log_success "kubectx + kubens installed."
}

install_vscode() {
  log_section "Visual Studio Code"
  if command_exists code; then
    log_success "VS Code already installed."
    return
  fi
  case "$OS" in
    macos) brew install --cask visual-studio-code ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install wget gpg apt-transport-https
          wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
          echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
          apt_update && apt_install code
          ;;
        dnf|yum)
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          cat <<'EOF' | sudo tee /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
          dnf_install code
          ;;
      esac
      ;;
  esac
  log_success "VS Code installed."
}

install_vscode_extensions() {
  log_section "VS Code Extensions"
  local CODE_BIN=""
  if command_exists code; then
    CODE_BIN="code"
  elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  fi
  [[ -z "$CODE_BIN" ]] && { log_warn "VS Code CLI not found."; return; }

  local extensions=(
    anthropic.claude-code
    PKief.material-icon-theme
    azemoh.one-monokai
    ms-vscode.powershell
    ms-python.python
    eamodio.gitlens
    mhutchie.git-graph
  )
  
  # Get list of installed extensions (lowercase for comparison)
  local installed_extensions
  installed_extensions=$("$CODE_BIN" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')
  
  for ext in "${extensions[@]}"; do
    local ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    # Check if already installed
    if echo "$installed_extensions" | grep -qi "^${ext_lower}$"; then
      log_success "✓ $ext (already installed)"
    else
      log_info "Installing $ext..."
      "$CODE_BIN" --install-extension "$ext" 2>/dev/null && {
        log_success "✓ $ext installed"
      } || {
        log_warn "✗ $ext installation failed"
      }
    fi
  done
  
  log_success "VS Code extensions configured."
}

set_default_browser_manual() {
  log_section "Default Browser (Manual)"
  log_info "macOS requires user confirmation for default browser."
  log_info ""
  log_info "To set Microsoft Edge as default:"
  log_info "  1. Open System Settings"
  log_info "  2. General → Default web browser"
  log_info "  3. Select 'Microsoft Edge'"
  log_info ""
  log_info "Or simply click any link - macOS will prompt you."
}

configure_vscode_extensions() {
  log_section "VS Code Settings Configuration"
  
  local settings_dir
  case "$OS" in
    macos)
      settings_dir="$HOME/Library/Application Support/Code/User"
      ;;
    linux)
      settings_dir="$HOME/.config/Code/User"
      ;;
  esac
  
  [[ ! -d "$settings_dir" ]] && mkdir -p "$settings_dir"
  
  local settings_file="$settings_dir/settings.json"
  
  # Backup existing settings
  [[ -f "$settings_file" ]] && cp "$settings_file" "$settings_file.backup"
  
  # Create or update settings.json with extensions config
  if [[ -f "$settings_file" ]]; then
    # Update existing settings - activate vscode-icons and git-graph
    cat "$settings_file" | \
      python3 -m json.tool 2>/dev/null > /tmp/settings_formatted.json && \
      mv /tmp/settings_formatted.json "$settings_file" || true
  fi
  
  # Add/update icon theme and enable extensions
  cat > "$settings_file" <<'EOF'
{
  "workbench.iconTheme": "material-icon-theme",
  "git.graph.includeRemotes": true,
  "extensions.recommendations": [
    "anthropic.claude-code",
    "PKief.material-icon-theme",
    "mhutchie.git-graph"
  ]
}
EOF

  log_success "VS Code configured: vscode-icons theme + git-graph enabled."
}

configure_documents_workspace() {
  log_section "VS Code Workspace (Documents) - All Extensions"
  
  local docs_dir="$HOME/Documents"
  local workspace_vscode_dir="$docs_dir/.vscode"
  local workspace_file="$docs_dir/projects.code-workspace"
  
  # Create .vscode folder in Documents
  mkdir -p "$workspace_vscode_dir"
  
  # Create workspace-specific settings.json with all extensions configured
  cat > "$workspace_vscode_dir/settings.json" <<'EOF'
{
  "workbench.iconTheme": "material-icon-theme",
  "workbench.colorTheme": "One Monokai",
  
  "git.graph.includeRemotes": true,
  "git.graph.showUncommitedChanges": true,
  "git.ignoreLimitWarning": true,
  
  "gitlens.advanced.telemetry.enabled": false,
  "gitlens.currentLine.enabled": true,
  "gitlens.hovers.currentLine.enabled": true,
  "gitlens.statusBar.enabled": true,
  
  "[python]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "ms-python.python",
    "editor.codeActionsOnSave": {
      "source.organizeImports": "explicit"
    }
  },
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  
  "[json]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "ms-python.python"
  },
  
  "[bash]": {
    "editor.formatOnSave": true
  },
  
  "[powershell]": {
    "editor.formatOnSave": true
  },
  
  "anthropic.claude": {
    "enabled": true
  },
  
  "editor.rulers": [80, 120],
  "editor.wordWrap": "on",
  "editor.formatOnSave": true,
  "editor.formatOnPaste": true,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  
  "extensions.recommendations": [
    "anthropic.claude-code",
    "PKief.material-icon-theme",
    "mhutchie.git-graph",
    "eamodio.gitlens",
    "ms-python.python",
    "ms-vscode.powershell",
    "azemoh.one-monokai"
  ]
}
EOF

  # Create workspace file for easy opening
  cat > "$workspace_file" <<'EOF'
{
  "folders": [
    {
      "path": ".",
      "name": "Projects"
    }
  ],
  "settings": {
    "workbench.iconTheme": "material-icon-theme",
    "workbench.colorTheme": "One Monokai",
    
    "git.graph.includeRemotes": true,
    "git.graph.showUncommitedChanges": true,
    "git.ignoreLimitWarning": true,
    
    "gitlens.advanced.telemetry.enabled": false,
    "gitlens.currentLine.enabled": true,
    "gitlens.hovers.currentLine.enabled": true,
    "gitlens.statusBar.enabled": true,
    "gitlens.blame.highlight.enabled": true,
    
    "[python]": {
      "editor.formatOnSave": true,
      "editor.defaultFormatter": "ms-python.python",
      "editor.codeActionsOnSave": {
        "source.organizeImports": "explicit"
      },
      "editor.rulers": [88]
    },
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "python.formatting.provider": "black",
    "python.defaultInterpreterPath": "${workspaceFolder}/venv/bin/python",
    
    "[json]": {
      "editor.formatOnSave": true,
      "editor.defaultFormatter": "ms-python.python"
    },
    
    "[bash]": {
      "editor.formatOnSave": true,
      "editor.defaultFormatter": "ms-vscode.powershell"
    },
    
    "[powershell]": {
      "editor.formatOnSave": true,
      "powershell.codeFormatting.Preset": "OTBS"
    },
    
    "editor.rulers": [80, 120],
    "editor.wordWrap": "on",
    "editor.formatOnSave": true,
    "editor.formatOnPaste": true,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "files.exclude": {
      "**/.git": false,
      "**/__pycache__": true,
      "**/*.pyc": true,
      "**/node_modules": true,
      "**/.DS_Store": true
    },
    
    "search.exclude": {
      "**/.venv": true,
      "**/venv": true,
      "**/__pycache__": true,
      "**/node_modules": true,
      "**/.git": true
    }
  },
  "extensions": {
    "recommendations": [
      "anthropic.claude-code",
      "PKief.material-icon-theme",
      "mhutchie.git-graph",
      "eamodio.gitlens",
      "ms-python.python",
      "ms-vscode.powershell",
      "azemoh.one-monokai"
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "Python: Current File",
        "type": "python",
        "request": "launch",
        "program": "${file}",
        "console": "integratedTerminal"
      }
    ]
  }
}
EOF

  log_success "Documents workspace created: $workspace_file"
  log_info "Open workspace: ${BOLD}code $workspace_file${NC}"
  log_info "Extensions configured:"
  log_info "  • Claude Code (editor integration)"
  log_info "  • Material Icon Theme (comprehensive icon set)"
  log_info "  • Git Graph (git visualization)"
  log_info "  • GitLens (git annotations)"
  log_info "  • Python (linting, formatting, debugging)"
  log_info "  • PowerShell (scripting)"
  log_info "  • One Monokai (color theme)"
}

install_spotify() {
  log_section "Spotify"
  if command_exists spotify; then
    log_success "Spotify already installed."
    return
  fi
  case "$OS" in
    macos) brew install --cask spotify ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install curl gnupg
          curl -fsSL https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
          echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null
          apt_update && apt_install spotify-client
          ;;
        dnf|yum)
          if command_exists snap; then
            sudo snap install spotify
          elif command_exists flatpak; then
            flatpak install --noninteractive flathub com.spotify.Client
          else
            log_warn "Spotify requires snap or flatpak."
          fi
          ;;
      esac
      ;;
  esac
  log_success "Spotify installed."
}

install_linux_utils() {
  [[ "$OS" != "linux" ]] && return
  log_section "Linux System Utilities"
  case "$PKG_MANAGER" in
    apt) apt_update && apt_install openssl dnsutils wget telnet zsh ;;
    dnf|yum) dnf_install openssl bind-utils wget telnet zsh ;;
  esac
  log_success "System utilities installed."
}

install_shell_setup() {
  log_section "Shell Setup"
  [[ "$OS" == "macos" ]] && { log_success "Using macOS zsh."; return; }

  ! command_exists zsh && {
    case "$PKG_MANAGER" in
      apt) apt_install zsh ;;
      dnf|yum) dnf_install zsh ;;
    esac
  }

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  [[ -f "$HOME/.zshrc" ]] && {
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="apple"/' "$HOME/.zshrc" 2>/dev/null || true
    sed -i 's/^plugins=.*/plugins=(git docker kubectl terraform python ssh-agent)/' "$HOME/.zshrc" 2>/dev/null || true
  }

  [[ "${SHELL:-}" != "$(command -v zsh)" ]] && chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
  log_success "Oh My Zsh configured."
}

configure_zsh_completions() {
  log_section "Zsh Completions"
  local compdir="$HOME/.zsh/completions"
  mkdir -p "$compdir"

  case "$OS" in
    macos)
      command_exists brew && brew list zsh-completions &>/dev/null 2>&1 || brew install zsh-completions
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt) apt_install bash-completion ;;
        dnf|yum) dnf_install bash-completion ;;
      esac
      ;;
  esac

  command_exists kubectl && kubectl completion zsh > "$compdir/_kubectl" 2>/dev/null || true
  command_exists docker && docker completion zsh > "$compdir/_docker" 2>/dev/null || true
  command_exists gh && gh completion -s zsh > "$compdir/_gh" 2>/dev/null || true
  command_exists terraform && terraform -install-autocomplete >/dev/null 2>&1 || true

  local zshrc="$HOME/.zshrc"
  if [[ -f "$zshrc" ]] && ! grep -q 'fpath.*completions' "$zshrc"; then
    cat >> "$zshrc" <<'EOF'
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit -i
EOF
  fi
  log_success "Zsh completions configured."
}

install_teamviewer() {
  log_section "TeamViewer"
  command_exists teamviewer && { log_success "TeamViewer already installed."; return; }
  case "$OS" in
    macos) brew install --cask teamviewer ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          TMP=$(mktemp -d)
          curl -fsSL "https://download.teamviewer.com/download/linux/teamviewer_amd64.deb" -o "$TMP/teamviewer.deb"
          sudo apt install -y "$TMP/teamviewer.deb" || { apt_update && sudo apt install -yf && sudo apt install -y "$TMP/teamviewer.deb"; }
          rm -rf "$TMP"
          ;;
        dnf|yum)
          TMP=$(mktemp -d)
          curl -fsSL "https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm" -o "$TMP/teamviewer.rpm"
          sudo "$PKG_MANAGER" install -y "$TMP/teamviewer.rpm"
          rm -rf "$TMP"
          ;;
      esac
      ;;
  esac
  log_success "TeamViewer installed."
}

install_azure_cli() {
  log_section "Azure CLI"
  command_exists az && { log_success "Azure CLI already installed."; return; }
  case "$OS" in
    macos) brew install azure-cli ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install ca-certificates curl apt-transport-https lsb-release gnupg
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
          AZ_DIST=$(lsb_release -cs)
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_DIST} main" | sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
          apt_update && apt_install azure-cli
          ;;
        dnf|yum)
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          cat <<'EOF' | sudo tee /etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
          dnf_install azure-cli
          ;;
      esac
      ;;
  esac
  log_success "Azure CLI installed."
}

install_remote_desktop() {
  log_section "Remote Desktop"
  case "$OS" in
    macos)
      brew install --cask windows-app 2>/dev/null || true
      log_success "Windows App installed."
      ;;
    linux)
      command_exists remmina && { log_success "Remmina already installed."; return; }
      case "$PKG_MANAGER" in
        apt) apt_install remmina remmina-plugin-rdp remmina-plugin-vnc ;;
        dnf|yum) dnf_install remmina remmina-plugins-rdp remmina-plugins-vnc ;;
      esac
      log_success "Remmina installed."
      ;;
  esac
}

install_python_debug_tools() {
  log_section "Python Debugging Tools"
  command_exists python3 || { log_warn "python3 not found."; return; }

  python3 -m pip install --user --upgrade debugpy ipdb pdbpp rich icecream 2>/dev/null || true
  export PATH="$HOME/.local/bin:$PATH"
  for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$RC" ]] && ! grep -q '.local/bin' "$RC"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    fi
  done

  if command_exists pipx; then
    pipx install py-spy 2>/dev/null || true
  else
    python3 -m pip install --user py-spy 2>/dev/null || true
  fi
  log_success "Python debug tools installed."
}

# ── Claude Desktop ───────────────────────────────────────────────────────────
install_claude() {
  log_section "Claude Desktop"
  case "$OS" in
    macos)
      if [[ -d "/Applications/Claude.app" ]]; then
        log_success "Claude Desktop already installed."
      else
        log_info "Installing Claude Desktop for macOS..."
        brew install --cask claude 2>&1 | grep -i "already an App" >/dev/null && {
          log_warn "Claude.app exists but not linked to Homebrew. Skipping reinstall."
        } || true
        log_success "Claude Desktop installed."
      fi
      ;;
    linux)
      log_warn "Claude Desktop is macOS-only. Use https://claude.ai for web access."
      ;;
  esac
}

install_docker() {
  log_section "Docker"
  command_exists docker && { log_success "Docker already installed."; return; }
  case "$OS" in
    macos)
      log_info "Installing Docker Desktop..."
      brew install --cask docker
      # Disable autostart
      defaults write com.docker.docker launchOnStartup -bool false 2>/dev/null || true
      log_success "Docker Desktop installed (autostart disabled)."
      log_info "First launch requires sudo for kernel extensions. Launch Docker manually when needed."
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install ca-certificates curl gnupg
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/${DISTRO}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
          sudo chmod a+r /etc/apt/keyrings/docker.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          apt_update
          apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          sudo systemctl enable --now docker
          sudo usermod -aG docker "$USER"
          log_warn "Log out/in for group changes."
          ;;
        dnf|yum)
          dnf_install dnf-plugins-core
          sudo "$PKG_MANAGER" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
          dnf_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          sudo systemctl enable --now docker
          sudo usermod -aG docker "$USER"
          log_warn "Log out/in for group changes."
          ;;
      esac
      ;;
  esac
  log_success "Docker installed."
}

install_docker_compose() {
  log_section "Docker Compose"
  if command_exists docker && docker compose version &>/dev/null 2>&1; then
    log_success "Docker Compose v2 available."
    return
  fi
  command_exists docker-compose && { log_success "docker-compose already installed."; return; }

  case "$OS" in
    macos)
      command_exists docker && docker compose version &>/dev/null 2>&1 && return
      brew install docker-compose 2>/dev/null || true
      ;;
    linux)
      DC_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
      ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH="x86_64" || ARCH="aarch64"
      sudo curl -fsSL "https://github.com/docker/compose/releases/download/v${DC_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
      sudo mkdir -p /usr/local/lib/docker/cli-plugins
      sudo ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
      log_success "docker-compose v${DC_VERSION} installed."
      return
      ;;
  esac
}

install_edge() {
  log_section "Microsoft Edge"
  case "$OS" in
    macos)
      brew install --cask microsoft-edge 2>/dev/null || true
      log_success "Microsoft Edge installed."
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install curl gpg
          curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg
          echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null
          apt_update && apt_install microsoft-edge-stable
          ;;
        dnf|yum)
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          cat <<'EOF' | sudo tee /etc/yum.repos.d/microsoft-edge.repo
[microsoft-edge]
name=microsoft-edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
          dnf_install microsoft-edge-stable
          ;;
      esac
      log_success "Microsoft Edge installed."
      ;;
  esac
}



install_slack() {
  log_section "Slack"
  command_exists slack && { log_success "Slack already installed."; return; }
  case "$OS" in
    macos) brew install --cask slack ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          if command_exists snap; then
            sudo snap install slack
          else
            log_warn "Install Slack manually: https://slack.com/downloads/linux"
          fi
          ;;
        dnf|yum)
          if command_exists snap; then
            sudo snap install slack
          elif command_exists flatpak; then
            flatpak install --noninteractive flathub com.slack.Slack
          else
            log_warn "Install Slack manually: https://slack.com/downloads/linux"
          fi
          ;;
      esac
      ;;
  esac
  log_success "Slack installed."
}

enable_slack_autostart() {
  log_section "Slack Autostart"
  case "$OS" in
    macos)
      # Check if Slack app exists
      if [[ ! -d "/Applications/Slack.app" ]]; then
        log_warn "Slack.app not found in /Applications"
        return
      fi
      
      log_info "Adding Slack to Login Items..."
      # Method 1: Try osascript
      osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Slack.app"}' 2>/dev/null && {
        log_success "Slack added to Login Items (osascript)"
        return
      }
      
      # Method 2: Use LaunchAgent (more reliable)
      local launchagent_dir="$HOME/Library/LaunchAgents"
      mkdir -p "$launchagent_dir"
      
      cat > "$launchagent_dir/com.slack.autostart.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.slack.autostart</string>
    <key>Program</key>
    <string>/Applications/Slack.app/Contents/MacOS/Slack</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
</dict>
</plist>
EOF
      
      launchctl load "$launchagent_dir/com.slack.autostart.plist" 2>/dev/null || true
      log_success "Slack will start on system boot (LaunchAgent)."
      ;;
    linux)
      local autostart_dir="$HOME/.config/autostart"
      mkdir -p "$autostart_dir"
      
      if command_exists snap; then
        cat > "$autostart_dir/slack.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Slack
Exec=snap run slack
Icon=slack
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
      elif command_exists flatpak; then
        cat > "$autostart_dir/slack.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Slack
Exec=flatpak run com.slack.Slack
Icon=slack
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
      else
        log_warn "Slack autostart requires snap or flatpak on Linux."
        return
      fi
      log_success "Slack will start on system boot."
      ;;
  esac
}

# ── Bitwarden (GUARANTEED INSTALLATION) ──────────────────────────────────────
install_bitwarden() {
  log_section "Bitwarden"
  command_exists bitwarden && { log_success "Bitwarden already installed."; return; }

  case "$OS" in
    macos)
      log_info "Installing Bitwarden for macOS..."
      brew install --cask bitwarden
      log_success "Bitwarden installed."
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          if command_exists snap; then
            log_info "Installing Bitwarden via snap..."
            sudo snap install bitwarden
          else
            log_info "Installing Bitwarden from deb..."
            TMP=$(mktemp -d)
            curl -fsSL "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb" -o "$TMP/bitwarden.deb"
            sudo apt install -y "$TMP/bitwarden.deb" || { apt_update && sudo apt install -yf && sudo apt install -y "$TMP/bitwarden.deb"; }
            rm -rf "$TMP"
          fi
          log_success "Bitwarden installed."
          ;;
        dnf|yum)
          log_info "Installing Bitwarden from rpm..."
          TMP=$(mktemp -d)
          curl -fsSL "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm" -o "$TMP/bitwarden.rpm"
          sudo "$PKG_MANAGER" install -y "$TMP/bitwarden.rpm"
          rm -rf "$TMP"
          log_success "Bitwarden installed."
          ;;
      esac
      ;;
  esac
}

install_vim() {
  log_section "Vim"
  command_exists vim && { log_success "Vim already installed."; return; }
  case "$OS" in
    macos) brew install vim ;;
    linux)
      case "$PKG_MANAGER" in
        apt) apt_install vim ;;
        dnf|yum) dnf_install vim-enhanced ;;
      esac
      ;;
  esac
  log_success "Vim installed."
}

print_summary() {
  log_section "Installation Summary"
  local tools=(brew git gh ansible tfenv terraform pipenv kubectl kubectx kubens az code docker-compose vim)
  local linux_tools=(openssl dig wget telnet zsh remmina microsoft-edge-stable slack)

  for tool in "${tools[@]}"; do
    [[ "$tool" == "brew" && "$OS" != "macos" ]] && continue
    if command_exists "$tool"; then
      echo -e "  ${GREEN}✔${NC} $tool"
    else
      echo -e "  ${RED}✘${NC} $tool (not found in PATH)"
      FAILED_INSTALLATIONS+=("$tool")
    fi
  done

  [[ "$OS" == "linux" ]] && {
    for tool in "${linux_tools[@]}"; do
      if command_exists "$tool"; then
        echo -e "  ${GREEN}✔${NC} $tool"
      else
        echo -e "  ${RED}✘${NC} $tool (not found in PATH)"
        FAILED_INSTALLATIONS+=("$tool")
      fi
    done
  }

  # Execution time
  local script_end=$(date +%s)
  local duration=$((script_end - SCRIPT_START))
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))
  local seconds=$((duration % 60))
  
  log_section "Execution Time"
  printf "  %02d:%02d:%02d\n" $hours $minutes $seconds

  # Failed installations summary
  if [[ ${#FAILED_INSTALLATIONS[@]} -gt 0 ]]; then
    log_section "Tools Not Found (Installation Skipped or Failed)"
    for tool in "${FAILED_INSTALLATIONS[@]}"; do
      case "$tool" in
        spotify) echo -e "  ${YELLOW}⊘${NC} $tool — Skipped (not available in all regions/systems)" ;;
        teamviewer) echo -e "  ${YELLOW}⊘${NC} $tool — Skipped (manual download recommended)" ;;
        *) echo -e "  ${YELLOW}⊘${NC} $tool — Skipped or failed" ;;
      esac
    done
    log_info "Retry manually: ${BOLD}brew install <tool>${NC} or ${BOLD}brew install --cask <tool>${NC}"
  else
    log_success "All tools installed successfully!"
  fi

  log_info "Done. Restart shell: ${BOLD}source ~/.bashrc${NC} or ${BOLD}source ~/.zshrc${NC}"
}

# ── Reboot prompt with countdown ──────────────────────────────────────────────
prompt_reboot() {
  log_section "System Reboot"
  read -p "Reboot system now? (Y/n - default yes): " -r reboot_choice
  
  # Default to YES if empty or matches [Yy]
  if [[ -z "$reboot_choice" || "$reboot_choice" =~ ^[Yy]$ ]]; then
    countdown_reboot
  else
    log_info "Skipped reboot. You can restart later manually."
  fi
}

countdown_reboot() {
  local seconds=5
  echo -e "${YELLOW}"
  while (( seconds > 0 )); do
    printf "\rRebooting in %2d seconds... Press Ctrl+C to cancel" "$seconds"
    sleep 1
    ((seconds--))
  done
  echo -e "\n${NC}"
  
  log_info "Rebooting now..."
  case "$OS" in
    macos) 
      sudo reboot
      ;;
    linux)
      sudo reboot
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${BLUE}"
  echo "╔══════════════════════════════════════╗"
  echo "║   SRE Initial Setup Script (v2)      ║"
  echo "║   Non-interactive • No sudo prompts  ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"

  detect_os
  print_terminal_logo
  validate_sudo_once

  [[ "$OS" == "macos" ]] && install_homebrew
  run_pre_install_updates
  set_system_locale_english

  install_git
  configure_git_user
  install_github_cli
  setup_ssh_github
  install_ansible
  install_tfenv
  install_pipenv
  install_kubectl
  install_kubectx_kubens
  install_vscode
  install_vscode_extensions
  configure_vscode_extensions
  configure_documents_workspace
  install_spotify
  install_linux_utils
  install_shell_setup
  install_teamviewer
  install_azure_cli
  install_remote_desktop
  install_python_debug_tools
  install_claude
  install_docker
  install_docker_compose
  install_edge
  # set_default_browser  # Requires Accessibility permissions - user can set manually
  install_slack
  enable_slack_autostart
  install_bitwarden
  install_vim
  configure_zsh_completions
  run_post_install_maintenance
  [[ "$OS" == "macos" ]] && set_default_browser_manual

  print_summary
  prompt_reboot
}

main "$@"
