#!/usr/bin/env bash
# arch_post_post_install.sh - Arch Linux Post-Post Install Script
# Date: 2025-04-20
# Author: Original by ChatGPT, enhanced by Grok
# License: MIT
# Description:
#   Enhanced Arch Linux post-post installation script with gaming optimizations.
#   Features:
#     - Interactive menu for selecting components
#     - Safe modification of pacman.conf with backups
#     - Robust Chaotic-AUR setup with validation
#     - Install gaming stack (Steam, Vulkan, Wine, MangoHud, Corectrl, VKBasalt)
#     - Install LibreOffice Fresh (EN & SV spellcheck)
#     - Install digiKam and PhotoGIMP (AUR)
#     - Optional system optimizations (ZRAM, linux-zen)
#     - Safety checks for sudo, system status, disk space

set -euo pipefail
IFS=$'\n\t'

# Constants
CHAOTIC_KEY="3056513887B78AEB"
CHAOTIC_KEYSERVER="keyserver.ubuntu.com"
CHAOTIC_URL="https://cdn-mirror.chaotic.cx/chaotic-aur"
LOGFILE="/tmp/nirucon-alppi_$(date +%F_%H%M%S).log"
MIN_DISK_SPACE_MB=2000  # Minimum disk space required in MB

# Colors
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

exec > >(tee -a "${LOGFILE}") 2>&1

# Handle interrupts (Ctrl+C)
cleanup() {
    print_msg warn "Script interrupted, cleaning up..."
    # Remove temporary files if they exist
    [[ -f "/tmp/pacman.conf.tmp" ]] && rm -f /tmp/pacman.conf.tmp
    print_msg info "Exiting safely"
    exit 1
}
trap cleanup SIGINT SIGTERM

print_msg() {
    local type="$1" message="$2"
    case "$type" in
        info)    echo -e "${BLUE}${BOLD}[INFO ]${RESET} $message";;
        success) echo -e "${GREEN}${BOLD}[ OK  ]${RESET} $message";;
        warn)    echo -e "${YELLOW}${BOLD}[WARN ]${RESET} $message";;
        error)   echo -e "${RED}${BOLD}[FAIL ]${RESET} $message"; exit 1;;
    esac
}

check_sudo() {
    print_msg info "Checking sudo privileges"
    if ! sudo -n true 2>/dev/null; then
        print_msg error "This script requires sudo privileges. Please run as a user with sudo access."
    fi
    print_msg success "Sudo privileges verified"
}

check_internet() {
    print_msg info "Checking internet connection"
    if ! ping -c 1 archlinux.org &>/dev/null; then
        print_msg error "No internet connection. Please connect and rerun."
    fi
    print_msg success "Internet connection verified"
}

check_system_status() {
    print_msg info "Checking system status for broken dependencies"
    if ! sudo pacman -Dk >/dev/null 2>&1; then
        print_msg error "Broken dependencies detected. Run 'sudo pacman -Syu' and fix issues before continuing."
    fi
    print_msg success "No broken dependencies found"
}

check_disk_space() {
    print_msg info "Checking available disk space"
    local available_space
    available_space=$(df -m / | tail -1 | awk '{print $4}')
    if (( available_space < MIN_DISK_SPACE_MB )); then
        print_msg error "Insufficient disk space (${available_space} MB available, ${MIN_DISK_SPACE_MB} MB required)."
    fi
    print_msg success "Sufficient disk space available (${available_space} MB)"
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
    print_msg info "Backing up pacman.conf and mirrorlist"
    backup_file /etc/pacman.conf
    backup_file /etc/pacman.d/mirrorlist
}

enable_multilib() {
    print_msg info "Enabling multilib repository"
    if grep -q '^\[multilib\]' /etc/pacman.conf && grep -q '^Include = /etc/pacman.d/mirrorlist' /etc/pacman.conf; then
        print_msg success "[multilib] already enabled"
    else
        print_msg info "Uncommenting or adding [multilib]"
        sudo sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
        sudo sed -i '/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
        if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf
        fi
        print_msg success "[multilib] enabled"
    fi
    sudo pacman -Syu --noconfirm
}

enable_chaotic_aur() {
    print_msg info "Configuring Chaotic-AUR repository"

    # Check if Chaotic-AUR is already configured correctly
    if grep -q '^\[chaotic-aur\]' /etc/pacman.conf && grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' /etc/pacman.conf; then
        print_msg success "Chaotic-AUR already configured in pacman.conf"
    else
        print_msg info "Setting up Chaotic-AUR keyring and mirrorlist"
        if ! pacman -Q chaotic-keyring >/dev/null 2>&1; then
            sudo pacman-key --recv-key "${CHAOTIC_KEY}" --keyserver "${CHAOTIC_KEYSERVER}"
            sudo pacman-key --lsign-key "${CHAOTIC_KEY}"
            sudo pacman -U --noconfirm \
                "${CHAOTIC_URL}/chaotic-keyring.pkg.tar.zst" \
                "${CHAOTIC_URL}/chaotic-mirrorlist.pkg.tar.zst"
            print_msg success "Chaotic-AUR keyring and mirrorlist installed"
        else
            print_msg success "Chaotic-AUR keyring already installed"
        fi

        # Add [chaotic-aur] to pacman.conf safely
        print_msg info "Adding [chaotic-aur] to pacman.conf"
        local tmp_conf="/tmp/pacman.conf.tmp"
        cp /etc/pacman.conf "${tmp_conf}"
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> "${tmp_conf}"
        if sudo mv "${tmp_conf}" /etc/pacman.conf; then
            print_msg success "Chaotic-AUR added to pacman.conf"
        else
            print_msg error "Failed to update pacman.conf"
        fi
    fi
    sudo pacman -Syu --noconfirm
    print_msg success "Chaotic-AUR fully enabled"
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
    sudo pacman -S --noconfirm --needed "${pkgs[@]}" || print_msg error "Failed to install pacman packages"
    print_msg success "Pacman packages installed"
}

install_aur_pkgs() {
    local pkgs=("${@}")
    print_msg info "Installing AUR packages: ${pkgs[*]}"
    yay -S --noconfirm --needed "${pkgs[@]}" || print_msg error "Failed to install AUR packages"
    print_msg success "AUR packages installed"
}

check_orphans() {
    print_msg info "Checking for orphaned (unnecessary) packages"
    local orphans
    orphans=$(pacman -Qdtq)
    if [[ -z "$orphans" ]]; then
        print_msg success "No orphaned packages found"
    else
        print_msg warn "Found orphaned packages: $orphans"
        read -p "Remove orphaned packages? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sudo pacman -Rns --noconfirm "$orphans"
            print_msg success "Orphaned packages removed"
        else
            print_msg info "Skipping removal of orphaned packages"
        fi
    fi
}

# Package lists
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
    corectrl
    vkbasalt
    dxvk-bin
    vkd3d
    lutris
    pipewire
    pipewire-pulse
)
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
    linux-zen
)

show_menu() {
    echo -e "${BLUE}${BOLD}Arch Linux Post-Post Install Menu${RESET}"
    echo "1. Install all components"
    echo "2. Install gaming stack"
    echo "3. Install productivity apps (LibreOffice, digiKam)"
    echo "4. Install AUR packages (PhotoGIMP, Proton-GE)"
    echo "5. Enable system optimizations (ZRAM, linux-zen)"
    echo "6. Exit"
    read -p "Select an option [1-6]: " choice
}

enable_system_optimizations() {
    print_msg info "Enabling system optimizations"
    read -p "Enable gamemoded service? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl enable --now gamemoded
        print_msg success "gamemoded enabled"
    else
        print_msg info "Skipping gamemoded activation"
    fi

    read -p "Enable ZRAM for memory compression? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo pacman -S --noconfirm zram-generator
        echo -e "[zram0]\nzram-size = ram / 2" | sudo tee /etc/systemd/zram-generator.conf
        sudo systemctl start systemd-zram-setup@zram0
        print_msg success "ZRAM enabled"
    else
        print_msg info "Skipping ZRAM setup"
    fi
}

main() {
    print_msg info "Starting Arch post-post install script"

    # Run safety checks
    check_sudo
    check_internet
    check_system_status
    check_disk_space

    # Keep sudo alive
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    backup_configs
    enable_multilib
    enable_chaotic_aur
    check_yay

    print_msg info "Updating system packages"
    sudo pacman -Syu --noconfirm
    print_msg success "System up to date"

    check_orphans

    while true; do
        show_menu
        case $choice in
            1)
                install_pacman_pkgs "${PACMAN_PKGS[@]}"
                install_pacman_pkgs "${GAMING_PKGS[@]}"
                install_aur_pkgs "${AUR_PKGS[@]}"
                enable_system_optimizations
                break
                ;;
            2)
                install_pacman_pkgs "${GAMING_PKGS[@]}"
                ;;
            3)
                install_pacman_pkgs "${PACMAN_PKGS[@]}"
                ;;
            4)
                install_aur_pkgs "${AUR_PKGS[@]}"
                ;;
            5)
                enable_system_optimizations
                install_aur_pkgs linux-zen
                ;;
            6)
                print_msg success "Exiting script"
                exit 0
                ;;
            *)
                print_msg warn "Invalid option, please try again"
                ;;
        esac
    done

    print_msg success "All selected components installed"
    echo -e "\n${GREEN}${BOLD}Done!${RESET} Review log at $LOGFILE"
}

main
