#!/usr/bin/env bash
# arch_post_post_install.sh - Arch Linux Post-Post Install Script
# Date: 2025-04-20
# Author: ChatGPT
# License: MIT
# Description:
#   Fully automated Arch Linux post-post installation script.
#   Features:
#     - Backup of pacman.conf and mirrorlist with timestamp
#     - Enable multilib repository
#     - Enable Chaotic-AUR repository
#     - Install gaming stack (Steam, Vulkan, wine, MangoHud)
#     - Install LibreOffice Fresh (EN & SV spellcheck)
#     - Install digiKam and PhotoGIMP (AUR)

set -euo pipefail
IFS=$'\n\t'

# Initialize colors if TTY supports
if command -v tput &>/dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; BOLD='\e[1m'; RESET='\e[0m'
fi

# Log file
LOGFILE="/tmp/nirucon-alppi_$(date +%F_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

print_msg() {
    local type="$1" message="$2"
    case "$type" in
        info)    echo -e "${BLUE}${BOLD}[INFO ]${RESET} $message";;
        success) echo -e "${GREEN}${BOLD}[ OK  ]${RESET} $message";;
        warn)    echo -e "${YELLOW}${BOLD}[WARN ]${RESET} $message";;
        error)   echo -e "${RED}${BOLD}[FAIL ]${RESET} $message"; exit 1;;
    esac
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local ts=$(date +%F_%H%M%S)
        sudo cp "$file" "${file}.bak.${ts}" && print_msg success "Backed up $file to ${file}.bak.${ts}"
    else
        print_msg warn "$file not found, skipping backup"
    fi
}

backup_configs() {
    print_msg info "Backup pacman.conf and mirrorlist"
    backup_file /etc/pacman.conf
    backup_file /etc/pacman.d/mirrorlist
}

enable_multilib() {
    print_msg info "Enabling multilib repository"
    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        print_msg success "[multilib] already enabled"
    else
        print_msg info "Uncommenting or adding [multilib]"
        sudo sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
        sudo sed -i '/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
        print_msg success "[multilib] added"
    fi
    sudo pacman -Syu --noconfirm
}

enable_chaotic_aur() {
    print_msg info "Installing Chaotic-AUR keyring & mirrorlist"
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
    print_msg info "Adding [chaotic-aur] to pacman.conf"
    if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    fi
    sudo pacman -Syu --noconfirm
    print_msg success "Chaotic-AUR enabled"
}

check_yay() {
    print_msg info "Checking for yay (AUR helper)"
    if ! command -v yay &>/dev/null; then
        print_msg error "yay not found. Please install yay and rerun script."
    fi
    print_msg success "yay detected"
}

install_pacman_pkgs() {
    local pkgs=("${@}")
    print_msg info "Installing pacman packages: ${pkgs[*]}"
    sudo pacman -S --noconfirm --needed "${pkgs[@]}"
    print_msg success "Pacman packages installed"
}

install_aur_pkgs() {
    local pkgs=("${@}")
    print_msg info "Installing AUR packages: ${pkgs[*]}"
    yay -S --noconfirm --needed "${pkgs[@]}"
    print_msg success "AUR packages installed"
}

# Package lists (add new here)
PACMAN_PKGS=(
    libreoffice-fresh
    libreoffice-fresh-sv
    digikam
)
GAMING_PKGS=(
    steam
    vulkan-icd-loader
    lib32-vulkan-icd-loader
    gamemode
    wine
    protontricks
    mangohud
)
# Detect GPU and add drivers
if lspci | grep -i nvidia &>/dev/null; then
    GAMING_PKGS+=(nvidia nvidia-utils lib32-nvidia-utils)
elif lspci | grep -i amd &>/dev/null; then
    GAMING_PKGS+=(mesa vulkan-radeon lib32-vulkan-radeon)
elif lspci | grep -i intel &>/dev/null; then
    GAMING_PKGS+=(mesa vulkan-intel lib32-vulkan-intel)
else
    print_msg warn "GPU not detected; installing generic mesa"
    GAMING_PKGS+=(mesa)
fi

AUR_PKGS=(
    photogimp
    proton-ge-custom
)

main() {
    print_msg info "Starting Arch post-post install script"
    
    # Keep sudo alive throughout script execution
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    
    backup_configs
    enable_multilib
    enable_chaotic_aur
    check_yay

    print_msg info "Updating system packages"
    pacman -Syu --noconfirm
    print_msg success "System up to date"

    install_pacman_pkgs "${PACMAN_PKGS[@]}"
    install_pacman_pkgs "${GAMING_PKGS[@]}"
    install_aur_pkgs "${AUR_PKGS[@]}"

    print_msg success "All components installed"
    echo -e "\n${GREEN}${BOLD}Done!${RESET} Review log at $LOGFILE"
}

main
