#!/usr/bin/env bash
# =============================================================================
# PersonalOS MEGA INSTALLER v3.0
# Tek Dosya = Tüm Sistem (Linux/macOS/Windows-WSL)
# =============================================================================

set -euo pipefail

# Renkler
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# Loglama
LOG_FILE="/tmp/personalos_mega_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[X]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

# =============================================================================
# KONFİGÜRASYON
# =============================================================================

ROOT_DIR="${1:-$HOME/personalos}"
PROFILE="${2:-standard}"

install_prerequisites() {
    info "On gereksinimler kontrol ediliyor..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y curl wget git jq openssl unzip
    elif command -v yum &>/dev/null; then
        sudo yum install -y curl wget git jq openssl unzip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm curl wget git jq openssl unzip
    elif [[ "$OS" == "Darwin" ]]; then
        command -v brew &>/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew install curl wget git jq openssl unzip
    fi
}

install_docker() {
    command -v docker &>/dev/null && { log "Docker zaten kurulu: $(docker --version)"; return; }
    info "Docker kurulumu..."
    if [[ "$OS" == "Darwin" ]]; then
        brew install --cask docker
    else
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER"
    fi
    log "Docker kuruldu"
}

create_directory_structure() {
    info "Dizin yapisi olusturuluyor: $ROOT_DIR"
    mkdir -p "$ROOT_DIR"/{services/{gateway,agent,adapters,ai},infra/{k8s,docker},observability/{prometheus,grafana},data/{postgres,redis},scripts,config,docs}
    log "Dizin yapisi olusturuldu"
}

log "=== PersonalOS MEGA INSTALLER v3.0 ==="
log "Kurulum profili: $PROFILE"
log "Hedef dizin: $ROOT_DIR"

install_prerequisites
install_docker
create_directory_structure

log "=== Kurulum Tamamlandi! ==="
log "Simdi: cd $ROOT_DIR && docker compose up -d"
