#!/usr/bin/env bash
# ==============================================================================
# install-tools.sh - Install or update omnictl and kubectl
# ==============================================================================
# Usage:
#   ./install-tools.sh [INSTALL_DIR]
#
# Examples:
#   ./install-tools.sh                # Installs to ~/bin (no sudo needed)
#   sudo ./install-tools.sh           # Installs system-wide to /usr/local/bin
#   ./install-tools.sh /usr/local/bin # Installs to /usr/local/bin (prompts for sudo)
# ==============================================================================

set -euo pipefail

# ANSI color codes for friendly output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $*"; }
warn()  { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
error() { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; exit 1; }

# Determine default installation directory
if [ -n "${1:-}" ]; then
  TARGET_DIR="$1"
elif [ "${EUID}" -eq 0 ]; then
  TARGET_DIR="/usr/local/bin"
elif [ -d "$HOME/bin" ]; then
  TARGET_DIR="$HOME/bin"
else
  TARGET_DIR="$HOME/.local/bin"
fi

mkdir -p "$TARGET_DIR"

# Check write permissions; use sudo if target directory is not writable
SUDO=""
if [ ! -w "$TARGET_DIR" ]; then
  if command -v sudo >/dev/null 2>&1; then
    warn "Target directory '${TARGET_DIR}' is not writable by current user. Using sudo."
    SUDO="sudo"
  else
    error "Target directory '${TARGET_DIR}' is not writable and sudo is not installed."
  fi
fi

# Detect OS and Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  arm64)   ARCH="arm64" ;;
  *)       error "Unsupported architecture: $ARCH" ;;
esac

case "$OS" in
  linux|darwin) ;;
  *) error "Unsupported operating system: $OS" ;;
esac

info "Detected Platform: ${BOLD}${OS}/${ARCH}${NC}"
info "Installation Directory: ${BOLD}${TARGET_DIR}${NC}"
echo ""

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ------------------------------------------------------------------------------
# 1. Install omnictl (Sidero Omni CLI)
# ------------------------------------------------------------------------------
info "Installing / Updating ${BOLD}omnictl${NC}..."

OMNI_VERSION="${OMNI_VERSION:-latest}"
if [ "$OMNI_VERSION" = "latest" ]; then
  OMNI_VERSION="$(curl -sSL -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/siderolabs/omni/releases/latest | grep '"tag_name":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"
  if [ -z "$OMNI_VERSION" ]; then
    warn "Could not resolve latest omnictl release via GitHub API, falling back to v1.12.4"
    OMNI_VERSION="v1.12.4"
  fi
fi

OMNI_URL="https://github.com/siderolabs/omni/releases/download/${OMNI_VERSION}/omnictl-${OS}-${ARCH}"
info "Downloading omnictl ${OMNI_VERSION} from ${OMNI_URL}..."

curl -sSL -f -o "${TMP_DIR}/omnictl" "$OMNI_URL" || error "Failed to download omnictl from $OMNI_URL"
chmod +x "${TMP_DIR}/omnictl"

$SUDO install -m 755 "${TMP_DIR}/omnictl" "${TARGET_DIR}/omnictl"
success "omnictl installed to ${TARGET_DIR}/omnictl"
echo -n "  Version: "
"${TARGET_DIR}/omnictl" -v || true
echo ""

# ------------------------------------------------------------------------------
# 2. Install kubectl (Kubernetes CLI)
# ------------------------------------------------------------------------------
info "Installing / Updating ${BOLD}kubectl${NC}..."

KUBECTL_VERSION="${KUBECTL_VERSION:-latest}"
if [ "$KUBECTL_VERSION" = "latest" ]; then
  KUBECTL_VERSION="$(curl -sSL -f https://dl.k8s.io/release/stable.txt)"
fi

KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
info "Downloading kubectl ${KUBECTL_VERSION} from ${KUBECTL_URL}..."

curl -sSL -f -o "${TMP_DIR}/kubectl" "$KUBECTL_URL" || error "Failed to download kubectl from $KUBECTL_URL"
chmod +x "${TMP_DIR}/kubectl"

$SUDO install -m 755 "${TMP_DIR}/kubectl" "${TARGET_DIR}/kubectl"
success "kubectl installed to ${TARGET_DIR}/kubectl"
echo -n "  Version: "
"${TARGET_DIR}/kubectl" version --client --output=yaml | grep 'gitVersion:' | head -n1 | sed 's/^[ ]*//' || true
echo ""

# ------------------------------------------------------------------------------
# PATH Check
# ------------------------------------------------------------------------------
if [[ ":$PATH:" != *":${TARGET_DIR}:"* ]]; then
  warn "'${TARGET_DIR}' is not currently in your PATH!"
  echo -e "  To add it, append the following line to your ~/.bashrc or ~/.zshrc:"
  echo -e "  ${BOLD}export PATH=\"${TARGET_DIR}:\$PATH\"${NC}"
  echo ""
fi

success "All tools successfully installed!"

