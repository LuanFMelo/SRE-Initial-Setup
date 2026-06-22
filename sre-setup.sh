#!/usr/bin/env bash
# =============================================================================
# SRE Initial Setup Script
# Supported OS: macOS, Ubuntu, Fedora
#
# Tools: git, gh (GitHub CLI), ansible, tfenv, terraform (via tfenv),
#        pipenv, kubectl, kubectx, kubens, vscode, spotify, oh-my-zsh,
#        bitwarden
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BOLD}${BLUE}━━━  $*  ━━━${NC}"; }

command_exists() { command -v "$1" &>/dev/null; }

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    log_info "This step requires sudo privileges."
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
        ubuntu)
          PKG_MANAGER="apt"
          ;;
        fedora)
          PKG_MANAGER="dnf"
          ;;
        *)
          log_error "Unsupported Linux distribution: $DISTRO (supported: ubuntu, fedora)"
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac

  log_info "Detected OS: ${BOLD}${OS}${NC}${DISTRO:+ ($DISTRO)}"
}

print_terminal_logo() {
  log_section "Platform"
  echo -e "${BOLD}${GREEN}"
  case "$OS" in
    macos)
      echo "  🍎  macOS"
      ;;
    linux)
      echo "  🐧  Linux"
      ;;
  esac
  echo -e "${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# macOS – Homebrew bootstrap
# ─────────────────────────────────────────────────────────────────────────────
install_homebrew() {
  if command_exists brew; then
    log_success "Homebrew already installed — updating..."
    brew update
    return
  fi
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  log_success "Homebrew installed."
}

# ─────────────────────────────────────────────────────────────────────────────
# Linux – apt helpers
# ─────────────────────────────────────────────────────────────────────────────
apt_install() {
  require_sudo
  sudo apt install -y "$@"
}

apt_update() {
  require_sudo
  sudo apt update -y
}

dnf_install() {
  require_sudo
  sudo "$PKG_MANAGER" install -y "$@"
}

# ── Package maintenance ──────────────────────────────────────────────────────
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
          require_sudo
          sudo apt upgrade -y
          ;;
        dnf|yum)
          require_sudo
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
          require_sudo
          sudo apt upgrade -y
          sudo apt autoremove -y
          sudo apt autoclean -y
          sudo apt clean
          ;;
        dnf|yum)
          require_sudo
          sudo "$PKG_MANAGER" upgrade --refresh -y
          sudo "$PKG_MANAGER" autoremove -y
          sudo "$PKG_MANAGER" clean all
          ;;
      esac
      ;;
  esac
  log_success "Post-install maintenance complete."
}

# ─────────────────────────────────────────────────────────────────────────────
# Tool installers
# ─────────────────────────────────────────────────────────────────────────────

# ── Git ───────────────────────────────────────────────────────────────────────
install_git() {
  log_section "Git"
  if command_exists git; then
    log_success "git $(git --version | awk '{print $3}') already installed."
    return
  fi
  case "$OS" in
    macos)   brew install git ;;
    linux)
      case "$PKG_MANAGER" in
        apt) apt_install git ;;
        dnf|yum) dnf_install git ;;
      esac
      ;;
  esac
  log_success "git installed: $(git --version)"
}

# ── GitHub CLI (gh) ───────────────────────────────────────────────────────────
install_github_cli() {
  log_section "GitHub CLI (gh)"
  if command_exists gh; then
    log_success "gh $(gh --version | head -1 | awk '{print $3}') already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install gh
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install curl gpg
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
          sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
            https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
          apt_update && apt_install gh
          ;;
        dnf|yum)
          dnf_install dnf-plugins-core
          sudo "$PKG_MANAGER" config-manager --add-repo \
            https://cli.github.com/packages/rpm/gh-cli.repo
          dnf_install gh
          ;;
      esac
      ;;
  esac
  log_success "gh installed: $(gh --version | head -1)"
}

# ── Ansible ───────────────────────────────────────────────────────────────────
install_ansible() {
  log_section "Ansible"
  if command_exists ansible; then
    log_success "ansible $(ansible --version | head -1) already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install ansible
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install software-properties-common
          sudo add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null \
            || apt_update
          apt_install ansible
          ;;
        dnf|yum)
          dnf_install ansible
          ;;
      esac
      ;;
  esac
  log_success "ansible installed."
}

# ── tfenv + Terraform ─────────────────────────────────────────────────────────
install_tfenv() {
  log_section "tfenv + Terraform"

  # tfenv
  if command_exists tfenv; then
    log_success "tfenv already installed."
  else
    case "$OS" in
      macos)
        brew install tfenv
        ;;
      linux)
        TFENV_DIR="$HOME/.tfenv"
        if [[ -d "$TFENV_DIR" ]]; then
          log_warn "$TFENV_DIR already exists; pulling latest..."
          git -C "$TFENV_DIR" pull --ff-only
        else
          git clone --depth=1 https://github.com/tfutils/tfenv.git "$TFENV_DIR"
        fi
        # Add to PATH in shell rc files
        for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
          if [[ -f "$RC" ]] && ! grep -q 'tfenv/bin' "$RC"; then
            echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> "$RC"
            log_info "Added tfenv to PATH in $RC"
          fi
        done
        export PATH="$HOME/.tfenv/bin:$PATH"
        ;;
    esac
    log_success "tfenv installed."
  fi

  # Install latest stable Terraform via tfenv
  if command_exists terraform; then
    log_success "terraform $(terraform version -json 2>/dev/null | grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' | head -1 || terraform version | head -1) already installed."
  else
    log_info "Installing latest stable Terraform via tfenv..."
    tfenv install latest
    tfenv use latest
    log_success "terraform installed: $(terraform version | head -1)"
  fi
}

# ── pipenv ────────────────────────────────────────────────────────────────────
install_pipenv() {
  log_section "pipenv"
  if command_exists pipenv; then
    log_success "pipenv $(pipenv --version) already installed."
    return
  fi
  # Ensure pip / python3 is available
  if ! command_exists python3; then
    log_warn "python3 not found — installing..."
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
    macos)
      brew install pipenv
      ;;
    linux)
      # Prefer pipx for isolated install; fall back to pip
      if command_exists pipx; then
        pipx install pipenv
      else
        python3 -m pip install --user pipenv
        # Ensure ~/.local/bin is in PATH
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

# ── kubectl ───────────────────────────────────────────────────────────────────
install_kubectl() {
  log_section "kubectl"
  if command_exists kubectl; then
    log_success "kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client) already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install kubectl
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install apt-transport-https ca-certificates curl gnupg
          KUBE_MINOR=$(curl -fsSL https://dl.k8s.io/release/stable.txt | grep -oP 'v\d+\.\d+')
          KUBE_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/Release.key" \
            | sudo gpg --dearmor -o "$KUBE_KEYRING"
          echo "deb [signed-by=${KUBE_KEYRING}] https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR}/deb/ /" \
            | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
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

# ── kubectx + kubens ──────────────────────────────────────────────────────────
install_kubectx_kubens() {
  log_section "kubectx + kubens"
  local need_kubectx need_kubens
  need_kubectx=$(command_exists kubectx && echo "no" || echo "yes")
  need_kubens=$(command_exists kubens   && echo "no" || echo "yes")

  if [[ "$need_kubectx" == "no" && "$need_kubens" == "no" ]]; then
    log_success "kubectx and kubens already installed."
    return
  fi

  case "$OS" in
    macos)
      brew install kubectx   # installs both kubectx and kubens
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          # kubectx package is not in default repos; install from GitHub releases
          KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest \
            | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
          ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH="x86_64" || ARCH="arm64"

          TMP=$(mktemp -d)
          curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
            | tar xz -C "$TMP" kubectx
          curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
            | tar xz -C "$TMP" kubens
          sudo install -m 755 "$TMP/kubectx" /usr/local/bin/kubectx
          sudo install -m 755 "$TMP/kubens"  /usr/local/bin/kubens
          rm -rf "$TMP"
          ;;
        dnf|yum)
          # Same binary install from GitHub
          KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest \
            | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
          ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH="x86_64" || ARCH="arm64"

          TMP=$(mktemp -d)
          curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
            | tar xz -C "$TMP" kubectx
          curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
            | tar xz -C "$TMP" kubens
          sudo install -m 755 "$TMP/kubectx" /usr/local/bin/kubectx
          sudo install -m 755 "$TMP/kubens"  /usr/local/bin/kubens
          rm -rf "$TMP"
          ;;
      esac
      ;;
  esac
  log_success "kubectx and kubens installed."
}

# ── VS Code ───────────────────────────────────────────────────────────────────
install_vscode() {
  log_section "Visual Studio Code"
  if command_exists code; then
    log_success "VS Code already installed: $(code --version | head -1)"
    return
  fi
  case "$OS" in
    macos)
      brew install --cask visual-studio-code
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install wget gpg apt-transport-https
          wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor \
            | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
          echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
            https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
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

# ── VS Code extensions ───────────────────────────────────────────────────────
install_vscode_extensions() {
  log_section "VS Code Extensions"

  local CODE_BIN=""
  if command_exists code; then
    CODE_BIN="code"
  elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  fi

  if [[ -z "$CODE_BIN" ]]; then
    log_warn "VS Code CLI not found in PATH. Open VS Code and enable the 'code' command, then rerun script."
    return
  fi

  local extensions=(
    PKief.material-icon-theme
    vscode-icons-team.vscode-icons
    azemoh.one-monokai
    ms-vscode.powershell
    ms-python.python
    eamodio.gitlens
    mhutchie.git-graph
  )

  for ext in "${extensions[@]}"; do
    if "$CODE_BIN" --list-extensions | grep -qx "$ext"; then
      log_success "Extension already installed: $ext"
    else
      log_info "Installing extension: $ext"
      "$CODE_BIN" --install-extension "$ext"
      log_success "Extension installed: $ext"
    fi
  done
}

# ── Spotify ───────────────────────────────────────────────────────────────────
install_spotify() {
  log_section "Spotify"
  if command_exists spotify; then
    log_success "Spotify already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install --cask spotify
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install curl gnupg
          curl -fsSL https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg \
            | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
          echo "deb http://repository.spotify.com stable non-free" \
            | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null
          apt_update && apt_install spotify-client
          ;;
        dnf|yum)
          # Spotify is not in official RPM repos; try snap or flatpak
          if command_exists snap; then
            log_info "Installing Spotify via snap..."
            sudo snap install spotify
          elif command_exists flatpak; then
            log_info "Installing Spotify via flatpak..."
            flatpak install --noninteractive flathub com.spotify.Client
          else
            log_warn "Neither snap nor flatpak found."
            log_warn "Install Spotify manually: https://www.spotify.com/download/linux/"
          fi
          ;;
      esac
      ;;
  esac
  log_success "Spotify installed."
}

# ── Linux system utilities (openssl, dig, wget, telnet, zsh) ─────────────────
install_linux_utils() {
  [[ "$OS" != "linux" ]] && return
  log_section "Linux System Utilities (openssl, dig, wget, telnet, zsh)"

  case "$PKG_MANAGER" in
    apt)
      apt_update
      apt_install openssl dnsutils wget telnet zsh
      ;;
    dnf|yum)
      dnf_install openssl bind-utils wget telnet zsh
      ;;
  esac
  log_success "System utilities installed."
}

# ── Shell setup (default macOS zsh / Oh My Zsh on Linux) ────────────────────
install_shell_setup() {
  log_section "Shell Setup"
  local zsh_plugins='plugins=(git docker kubectl terraform python ssh-agent)'

  if [[ "$OS" == "macos" ]]; then
    log_success "Using default macOS zsh setup."
    return
  fi

  if ! command_exists zsh; then
    log_warn "zsh not found — installing..."
    case "$PKG_MANAGER" in
      apt) apt_install zsh ;;
      dnf|yum) dnf_install zsh ;;
    esac
  fi

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log_success "Oh My Zsh already installed."
  else
    log_info "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    log_success "Oh My Zsh installed."
  fi

  if [[ -f "$HOME/.zshrc" ]]; then
    if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
      sed -i 's/^ZSH_THEME=.*/ZSH_THEME="apple"/' "$HOME/.zshrc"
    else
      echo 'ZSH_THEME="apple"' >> "$HOME/.zshrc"
    fi
    if grep -q '^plugins=' "$HOME/.zshrc"; then
      sed -i "s/^plugins=.*/${zsh_plugins}/" "$HOME/.zshrc"
    else
      echo "$zsh_plugins" >> "$HOME/.zshrc"
    fi
  else
    cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="apple"
plugins=(git docker kubectl terraform python ssh-agent)
source "$ZSH/oh-my-zsh.sh"
EOF
  fi
  log_success "Oh My Zsh theme and plugins configured."

  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    if chsh -s "$(command -v zsh)" "$USER"; then
      log_success "Default shell changed to zsh for $USER."
    else
      log_warn "Could not change default shell automatically. Run: chsh -s $(command -v zsh)"
    fi
  fi
}

# ── Zsh completions (macOS + Linux) ──────────────────────────────────────────
configure_zsh_completions() {
  log_section "Zsh Completions"
  local zshrc="$HOME/.zshrc"
  local compdir="$HOME/.zsh/completions"
  local start_marker="# >>> sre zsh completions >>>"
  local end_marker="# <<< sre zsh completions <<<"

  mkdir -p "$compdir"

  # Install common completion package support where available.
  case "$OS" in
    macos)
      if command_exists brew; then
        brew list zsh-completions &>/dev/null 2>&1 || brew install zsh-completions
      fi
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt) apt_install bash-completion ;;
        dnf|yum) dnf_install bash-completion ;;
      esac
      ;;
  esac

  # Generate completion definitions for installed tools.
  if command_exists kubectl; then
    kubectl completion zsh > "$compdir/_kubectl" || true
  fi
  if command_exists docker; then
    docker completion zsh > "$compdir/_docker" || true
  fi
  if command_exists gh; then
    gh completion -s zsh > "$compdir/_gh" || true
  fi
  if command_exists terraform; then
    terraform -install-autocomplete >/dev/null 2>&1 || true
  fi

  if [[ ! -f "$zshrc" ]]; then
    cat > "$zshrc" <<'EOF'
# Generated by SRE initial setup
EOF
  fi

  if grep -q "^${start_marker}$" "$zshrc"; then
    sed -i "/^${start_marker}$/,/^${end_marker}$/d" "$zshrc"
  fi

  cat >> "$zshrc" <<'EOF'
# >>> sre zsh completions >>>
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit -i
# <<< sre zsh completions <<<
EOF

  log_success "Zsh completions configured for kubectl, docker, gh, and terraform (when installed)."
}

# ── TeamViewer ────────────────────────────────────────────────────────────────
install_teamviewer() {
  log_section "TeamViewer"
  if command_exists teamviewer; then
    log_success "TeamViewer already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install --cask teamviewer
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          TMP=$(mktemp -d)
          curl -fsSL "https://download.teamviewer.com/download/linux/teamviewer_amd64.deb" \
            -o "$TMP/teamviewer.deb"
          require_sudo
          sudo apt install -y "$TMP/teamviewer.deb" || \
            { apt_update && sudo apt install -yf && sudo apt install -y "$TMP/teamviewer.deb"; }
          rm -rf "$TMP"
          ;;
        dnf|yum)
          TMP=$(mktemp -d)
          curl -fsSL "https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm" \
            -o "$TMP/teamviewer.rpm"
          require_sudo
          sudo "$PKG_MANAGER" install -y "$TMP/teamviewer.rpm"
          rm -rf "$TMP"
          ;;
      esac
      ;;
  esac
  log_success "TeamViewer installed."
}

# ── Azure CLI ─────────────────────────────────────────────────────────────────
install_azure_cli() {
  log_section "Azure CLI"
  if command_exists az; then
    log_success "Azure CLI $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo '') already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install azure-cli
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install ca-certificates curl apt-transport-https lsb-release gnupg
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
          AZ_DIST=$(lsb_release -cs)
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/azure-cli/ ${AZ_DIST} main" \
            | sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
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

# ── Remote Desktop (Windows App on macOS / Remmina on Linux) ──────────────────
install_remote_desktop() {
  log_section "Remote Desktop"
  case "$OS" in
    macos)
      if ! brew list --cask windows-app &>/dev/null 2>&1; then
        brew install --cask windows-app
        log_success "Windows App installed."
      else
        log_success "Windows App already installed."
      fi
      ;;
    linux)
      if command_exists remmina; then
        log_success "Remmina already installed."
        return
      fi
      case "$PKG_MANAGER" in
        apt)
          apt_update
          apt_install remmina remmina-plugin-rdp remmina-plugin-vnc
          ;;
        dnf|yum)
          dnf_install remmina remmina-plugins-rdp remmina-plugins-vnc
          ;;
      esac
      log_success "Remmina installed."
      ;;
  esac
}

# ── Python debugging tools ──────────────────────────────────────────────────────────
install_python_debug_tools() {
  log_section "Python Debugging Tools"

  # Ensure python3 + pip are present
  if ! command_exists python3; then
    log_warn "python3 not found — skipping Python debug tools."
    return
  fi

  # Packages installed into the user site (pip install --user)
  # debugpy   → VS Code / DAP debugger
  # ipdb      → IPython-powered interactive debugger
  # pdbpp     → drop-in pdb replacement with syntax highlighting
  # rich      → pretty tracebacks & inspection helpers
  # icecream  → painless print-style debugging
  local pip_pkgs=(debugpy ipdb pdbpp rich icecream)

  log_info "Installing pip packages: ${pip_pkgs[*]}"
  python3 -m pip install --user --upgrade "${pip_pkgs[@]}"

  # Ensure ~/.local/bin is in PATH
  export PATH="$HOME/.local/bin:$PATH"
  for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$RC" ]] && ! grep -q '.local/bin' "$RC"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    fi
  done

  # py-spy → sampling profiler / live-process debugger (needs root to attach)
  # Install via pipx for an isolated binary if available, otherwise pip --user
  if ! command_exists py-spy; then
    log_info "Installing py-spy..."
    if command_exists pipx; then
      pipx install py-spy
    else
      python3 -m pip install --user py-spy
    fi
  else
    log_success "py-spy already installed."
  fi

  log_success "Python debugging tools installed: ${pip_pkgs[*]} py-spy"
}

# ── Claude ──────────────────────────────────────────────────────────────────
install_claude() {
  log_section "Claude"
  case "$OS" in
    macos)
      # Claude Chat desktop app
      if brew list --cask claude &>/dev/null 2>&1; then
        log_success "Claude Chat desktop already installed."
      else
        brew install --cask claude
        log_success "Claude Chat desktop installed."
      fi
      # Claude Code CLI (requires Node/npm)
      if command_exists npm; then
        if ! command_exists claude; then
          log_info "Installing Claude Code CLI..."
          npm install -g @anthropic-ai/claude-code
          log_success "Claude Code CLI installed."
        else
          log_success "Claude Code CLI already installed."
        fi
      else
        log_warn "npm not found — skipping Claude Code CLI."
      fi
      ;;
    linux)
      # Claude Chat desktop app
      if command_exists claude-desktop; then
        log_success "Claude Chat desktop already installed."
      else
        log_warn "Claude Chat desktop is not installed. No official Linux package is configured in this script. Use https://claude.ai"
      fi

      # Claude Code CLI (requires Node/npm)
      if command_exists npm; then
        if ! command_exists claude; then
          log_info "Installing Claude Code CLI..."
          npm install -g @anthropic-ai/claude-code
          log_success "Claude Code CLI installed."
        else
          log_success "Claude Code CLI already installed."
        fi
      else
        log_warn "npm not found — skipping Claude Code CLI."
      fi
      ;;
  esac
}

# ── Docker ────────────────────────────────────────────────────────────────────
install_docker() {
  log_section "Docker"
  if command_exists docker; then
    log_success "Docker $(docker --version | awk '{print $3}' | tr -d ',') already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install --cask docker
      log_success "Docker Desktop installed."
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install ca-certificates curl gnupg
          sudo mkdir -p /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/${DISTRO}/gpg \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
          sudo chmod a+r /etc/apt/keyrings/docker.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          apt_update
          apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          sudo systemctl enable --now docker
          sudo usermod -aG docker "$USER"
          log_warn "Log out and back in for group membership to take effect."
          ;;
        dnf|yum)
          dnf_install dnf-plugins-core
          sudo "$PKG_MANAGER" config-manager --add-repo \
            https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
          sudo "$PKG_MANAGER" config-manager --add-repo \
            https://download.docker.com/linux/fedora/docker-ce.repo
          dnf_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          sudo systemctl enable --now docker
          sudo usermod -aG docker "$USER"
          log_warn "Log out and back in for group membership to take effect."
          ;;
      esac
      log_success "Docker installed."
      ;;
  esac
}

# ── Docker Compose ────────────────────────────────────────────────────────────
install_docker_compose() {
  log_section "Docker Compose"
  if command_exists docker && docker compose version &>/dev/null 2>&1; then
    log_success "Docker Compose v2 plugin already available."
    return
  fi
  if command_exists docker-compose; then
    log_success "docker-compose $(docker-compose version --short 2>/dev/null || docker-compose --version) already installed."
    return
  fi
  case "$OS" in
    macos)
      # Bundled with Docker Desktop; also available standalone via brew
      if command_exists docker && docker compose version &>/dev/null 2>&1; then
        log_success "Docker Compose v2 bundled with Docker Desktop."
      else
        brew install docker-compose
      fi
      ;;
    linux)
      # Install standalone docker-compose v2 binary from GitHub releases
      DC_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
      ARCH=$(uname -m)
      [[ "$ARCH" == "x86_64" ]] && ARCH="x86_64" || ARCH="aarch64"
      sudo curl -fsSL \
        "https://github.com/docker/compose/releases/download/v${DC_VERSION}/docker-compose-linux-${ARCH}" \
        -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
      # Also wire up as Docker CLI plugin
      sudo mkdir -p /usr/local/lib/docker/cli-plugins
      sudo ln -sf /usr/local/bin/docker-compose \
        /usr/local/lib/docker/cli-plugins/docker-compose
      log_success "docker-compose v${DC_VERSION} installed."
      ;;
  esac
}

# ── Microsoft Edge ────────────────────────────────────────────────────────────
install_edge() {
  log_section "Microsoft Edge"
  case "$OS" in
    macos)
      if ! brew list --cask microsoft-edge &>/dev/null 2>&1; then
        brew install --cask microsoft-edge
        log_success "Microsoft Edge installed."
      else
        log_success "Microsoft Edge already installed."
      fi
      # Set as default browser (requires defaultbrowser helper)
      if ! command_exists defaultbrowser; then
        brew install defaultbrowser
      fi
      log_info "Setting Microsoft Edge as default browser..."
      defaultbrowser edge
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          if ! command_exists microsoft-edge-stable; then
            apt_install curl gpg
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
              | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] \
https://packages.microsoft.com/repos/edge stable main" \
              | sudo tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null
            apt_update && apt_install microsoft-edge-stable
          else
            log_success "Microsoft Edge already installed."
          fi
          ;;
        dnf|yum)
          if ! command_exists microsoft-edge-stable; then
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
          else
            log_success "Microsoft Edge already installed."
          fi
          ;;
      esac
      # Set as default browser
      if command_exists xdg-settings && command_exists microsoft-edge-stable; then
        xdg-settings set default-web-browser microsoft-edge.desktop
        log_success "Microsoft Edge set as default browser."
      fi
      ;;
  esac
}

# ── Slack ─────────────────────────────────────────────────────────────────────
install_slack() {
  log_section "Slack"
  if command_exists slack; then
    log_success "Slack already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install --cask slack
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          if command_exists snap; then
            sudo snap install slack
          else
            TMP=$(mktemp -d)
          SLACK_VER=$(curl -fsSL "https://slack.com/downloads/instructions/linux" \
            | grep -oP 'slack-desktop-[0-9]+\.[0-9]+\.[0-9]+' | head -1)
          if [[ -z "$SLACK_VER" ]]; then
            log_warn "Could not detect latest Slack version. Install manually: https://slack.com/downloads/linux"
            rm -rf "$TMP"
          else
            curl -fsSL "https://downloads.slack-edge.com/desktop-releases/linux/x64/${SLACK_VER#slack-desktop-}/${SLACK_VER}-amd64.deb" \
              -o "$TMP/slack.deb"
            sudo apt install -y "$TMP/slack.deb"
            rm -rf "$TMP"
          fi
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

# ── Bitwarden ─────────────────────────────────────────────────────────────────
install_bitwarden() {
  log_section "Bitwarden"
  if command_exists bitwarden; then
    log_success "Bitwarden already installed."
    return
  fi

  case "$OS" in
    macos)
      brew install --cask bitwarden
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          if command_exists snap; then
            sudo snap install bitwarden
          else
            TMP=$(mktemp -d)
            curl -fsSL "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb" \
              -o "$TMP/bitwarden.deb"
            require_sudo
            sudo apt install -y "$TMP/bitwarden.deb" || \
              { apt_update && sudo apt install -yf && sudo apt install -y "$TMP/bitwarden.deb"; }
            rm -rf "$TMP"
          fi
          ;;
        dnf|yum)
          TMP=$(mktemp -d)
          curl -fsSL "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm" \
            -o "$TMP/bitwarden.rpm"
          require_sudo
          sudo "$PKG_MANAGER" install -y "$TMP/bitwarden.rpm"
          rm -rf "$TMP"
          ;;
      esac
      ;;
  esac

  log_success "Bitwarden installed."
}

# ── Vim ───────────────────────────────────────────────────────────────────────
install_vim() {
  log_section "Vim"
  if command_exists vim; then
    log_success "vim $(vim --version | head -1 | awk '{print $5}') already installed."
    return
  fi
  case "$OS" in
    macos)  brew install vim ;;
    linux)
      case "$PKG_MANAGER" in
        apt)    apt_install vim ;;
        dnf|yum) dnf_install vim-enhanced ;;
      esac
      ;;
  esac
  log_success "Vim installed."
}

# ── VirtualBox ────────────────────────────────────────────────────────────────
install_virtualbox() {
  log_section "VirtualBox"
  if command_exists VBoxManage; then
    log_success "VirtualBox $(VBoxManage --version) already installed."
    return
  fi
  case "$OS" in
    macos)
      brew install --cask virtualbox
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)
          apt_install curl gnupg
          curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
            | sudo gpg --dearmor -o /usr/share/keyrings/oracle-virtualbox.gpg
          VBOX_DIST=$(. /etc/os-release && echo "$ID")
          VBOX_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
          echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox.gpg] \
https://download.virtualbox.org/virtualbox/debian ${VBOX_CODENAME} contrib" \
            | sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null
          VBOX_VERSION=$(curl -fsSL https://download.virtualbox.org/virtualbox/LATEST.TXT | tr -d '[:space:]')
          VBOX_MAJOR_MINOR=$(echo "$VBOX_VERSION" | grep -oP '^\d+\.\d+')
          apt_update && apt_install "virtualbox-${VBOX_MAJOR_MINOR}"
          ;;
        dnf|yum)
          sudo "$PKG_MANAGER" install -y \
            https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo 2>/dev/null || true
          curl -fsSL https://www.virtualbox.org/download/oracle_vbox.asc \
            | sudo rpm --import -
          cat <<'EOF' | sudo tee /etc/yum.repos.d/virtualbox.repo
[virtualbox]
name=Oracle Linux / RHEL / CentOS-$releasever / $basearch - VirtualBox
baseurl=https://download.virtualbox.org/virtualbox/rpm/el/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://www.virtualbox.org/download/oracle_vbox.asc
EOF
          VBOX_VERSION=$(curl -fsSL https://download.virtualbox.org/virtualbox/LATEST.TXT | tr -d '[:space:]')
          VBOX_MAJOR_MINOR=$(echo "$VBOX_VERSION" | grep -oP '^\d+\.\d+')
          dnf_install "VirtualBox-${VBOX_MAJOR_MINOR}"
          ;;
      esac
      log_success "VirtualBox installed."
      ;;
  esac
  log_success "VirtualBox installed."
}

# ── VirtualBox Extension Pack ────────────────────────────────────────────────
install_virtualbox_extension_pack() {
  log_section "VirtualBox Extension Pack"

  if ! command_exists VBoxManage; then
    log_warn "VBoxManage not found — skipping Extension Pack installation."
    return
  fi

  local vbox_version vbox_extpack_url tmp_dir extpack_file
  vbox_version=$(VBoxManage --version | sed -E 's/r.*//' | sed -E 's/_.*//')

  # Skip when the matching Extension Pack version is already installed.
  if VBoxManage list extpacks 2>/dev/null | grep -q "Oracle VM VirtualBox Extension Pack" && \
     VBoxManage list extpacks 2>/dev/null | grep -q "Version: *${vbox_version}"; then
    log_success "VirtualBox Extension Pack ${vbox_version} already installed."
    return
  fi

  if ! command_exists curl; then
    case "$OS" in
      macos) brew install curl ;;
      linux)
        case "$PKG_MANAGER" in
          apt) apt_install curl ;;
          dnf|yum) dnf_install curl ;;
        esac
        ;;
    esac
  fi

  vbox_extpack_url="https://download.virtualbox.org/virtualbox/${vbox_version}/Oracle_VM_VirtualBox_Extension_Pack-${vbox_version}.vbox-extpack"
  tmp_dir=$(mktemp -d)
  extpack_file="$tmp_dir/Oracle_VM_VirtualBox_Extension_Pack-${vbox_version}.vbox-extpack"

  log_info "Downloading VirtualBox Extension Pack ${vbox_version}..."
  curl -fsSL "$vbox_extpack_url" -o "$extpack_file"

  log_info "Installing VirtualBox Extension Pack..."
  require_sudo
  yes | sudo VBoxManage extpack install --replace "$extpack_file" >/dev/null
  rm -rf "$tmp_dir"

  log_success "VirtualBox Extension Pack installed."
}

print_summary() {
  log_section "Installation Summary"
  local tools=(brew git gh ansible tfenv terraform pipenv kubectl kubectx kubens az code spotify teamviewer py-spy claude docker docker-compose bitwarden vim VBoxManage)
  # Linux-only tools
  local linux_tools=(openssl dig wget telnet zsh remmina microsoft-edge-stable slack)

  for tool in "${tools[@]}"; do
    # brew only relevant on macOS
    [[ "$tool" == "brew" && "$OS" != "macos" ]] && continue
    # teamviewer binary may be in a non-standard path; skip strict check
    if command_exists "$tool"; then
      echo -e "  ${GREEN}✔${NC} $tool"
    else
      echo -e "  ${RED}✘${NC} $tool  (not found in PATH — may need a new shell session)"
    fi
  done

  if [[ "$OS" == "linux" ]]; then
    for tool in "${linux_tools[@]}"; do
      if command_exists "$tool"; then
        echo -e "  ${GREEN}✔${NC} $tool"
      else
        echo -e "  ${RED}✘${NC} $tool  (not found in PATH — may need a new shell session)"
      fi
    done
  fi

  # Python debug packages (pip --user; check via python3 -m)
  echo -e "\n  ${BOLD}Python debug packages:${NC}"
  local py_pkgs=(debugpy ipdb pdbpp rich icecream)
  for pkg in "${py_pkgs[@]}"; do
    if python3 -c "import ${pkg//-/_}" &>/dev/null 2>&1; then
      echo -e "  ${GREEN}✔${NC} $pkg"
    else
      echo -e "  ${RED}✘${NC} $pkg"
    fi
  done
  log_info "Restart your shell (or run ${BOLD}source ~/.bashrc${NC} / ${BOLD}source ~/.zshrc${NC}) to pick up PATH changes."
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${BLUE}"
  echo "╔══════════════════════════════════════╗"
  echo "║       SRE Initial Setup Script       ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"

  detect_os
  print_terminal_logo

  [[ "$OS" == "macos" ]] && install_homebrew
  run_pre_install_updates

  install_git
  install_github_cli
  install_ansible
  install_tfenv
  install_pipenv
  install_kubectl
  install_kubectx_kubens
  install_vscode
  install_vscode_extensions
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
  install_slack
  install_bitwarden
  install_vim
  install_virtualbox
  install_virtualbox_extension_pack
  configure_zsh_completions
  run_post_install_maintenance

  print_summary
}

main "$@"
