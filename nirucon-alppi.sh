#!/usr/bin/env bash
# nirucon-alppi.sh - Arch Linux Post-Post Install Script
# Date: 2025-04-20
# Author: Nicklas Rudolfsson
# License: MIT
# Description:
#   Fully automated and user-friendly Arch Linux post-post installation script.
#   Features:
#     - Interactive menu with clear options
#     - Safe modification of pacman.conf with backups and rollback
#     - Robust Chaotic-AUR setup with validation
#     - Install gaming stack (Steam, Vulkan, Wine, MangoHud, Corectrl, VKBasalt, Lutris)
#     - Install productivity apps (LibreOffice, digiKam)
#     - Install PhotoGIMP via GitHub
#     - Install AUR packages (Proton-GE, linux-zen, dxvk-bin, goverlay)
#     - Optional system optimizations (ZRAM, gamemoded, linux-zen)
#     - Support for systemd-boot and GRUB for linux-zen
#     - Safety checks for sudo, internet, disk space, system status
#     - Package availability validation
#     - Orphaned package cleanup and cache management

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
    [[ -f "/tmp/pacman.conf.tmp" ]] && rm -f /tmp/pacman.conf.tmp
    [[ -d "/tmp/photogimp_temp" ]] && rm -rf /tmp/photogimp_temp
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

check_bootloader() {
    print_msg info "Checking for bootloader"
    if [[ -f "/boot/loader/loader.conf" ]]; then
        BOOTLOADER="systemd-boot"
        print_msg success "Detected systemd-boot"
    elif [[ -f "/boot/grub/grub.cfg" ]]; then
        BOOTLOADER="grub"
        print_msg success "Detected GRUB"
    else
        print_msg error "No supported bootloader (systemd-boot or GRUB) detected."
    fi
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

rollback_pacman_conf() {
    local latest_backup=$(ls -t /etc/pacman.conf.bak.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        sudo mv "$latest_backup" /etc/pacman.conf
        print_msg success "Restored pacman.conf from $latest_backup"
    else
        print_msg warn "No backup found, cannot restore pacman.conf"
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
        local tmp_conf="/tmp/pacman.conf.tmp"
        cp /etc/pacman.conf "${tmp_conf}"
        sed -i '/^#\[multilib\]/s/^#//' "${tmp_conf}"
        sed -i '/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' "${tmp_conf}"
        if ! grep -q '^\[multilib\]' "${tmp_conf}"; then
            echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "${tmp_conf}"
        fi
        if sudo mv "${tmp_conf}" /etc/pacman.conf; then
            print_msg success "[multilib] enabled"
        else
            print_msg error "Failed to update pacman.conf"
        fi
    fi
    sudo pacman -Syu --noconfirm
}

enable_chaotic_aur() {
    print_msg info "Configuring Chaotic-AUR repository"
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
        print_msg info "Adding [chaotic-aur] to pacman.conf"
        local tmp_conf="/tmp/pacman.conf.tmp"
        cp /etc/pacman.conf "${tmp_conf}"
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> "${tmp_conf}"
        if sudo mv "${tmp_conf}" /etc/pacman.conf; then
            print_msg success "Chaotic-AUR added to pacman.conf"
        else
            rollback_pacman_conf
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

check_package_availability() {
    local pkg_type="$1" pkgs=("${@:2}")
    print_msg info "Checking availability of $pkg_type packages: ${pkgs[*]}"
    local failed_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if [[ "$pkg_type" == "pacman" ]]; then
            if ! pacman -Sp "$pkg" >/dev/null 2>&1; then
                print_msg warn "Package $pkg not found in pacman repositories, checking AUR"
                if yay -Sp "$pkg" >/dev/null 2>&1; then
                    AUR_PKGS+=("$pkg")
                    GAMING_PKGS=("${GAMING_PKGS[@]/$pkg}")
                    PACMAN_PKGS=("${PACMAN_PKGS[@]/$pkg}")
                else
                    failed_pkgs+=("$pkg")
                fi
            fi
        elif [[ "$pkg_type" == "aur" ]]; then
            if ! yay -Sp "$pkg" >/dev/null 2>&1; then
                failed_pkgs+=("$pkg")
            fi
        fi
    done
    if [[ ${#failed_pkgs[@]} -gt 0 ]]; then
        print_msg warn "Some packages not found: ${failed_pkgs[*]}. They will be skipped."
    fi
}

review_aur_pkgbuild() {
    local pkg="$1"
    print_msg info "Reviewing PKGBUILD for $pkg"
    local pkgbuild_file="/tmp/PKGBUILD.$pkg"
    yay -Gp "$pkg" > "$pkgbuild_file" 2>/dev/null
    if [[ -s "$pkgbuild_file" ]]; then
        if ! command -v less &>/dev/null; then
            print_msg warn "less not found. Installing it now..."
            sudo pacman -S --noconfirm --needed less || {
                print_msg warn "Failed to install less, using cat to display PKGBUILD"
                cat "$pkgbuild_file"
            }
        else
            less "$pkgbuild_file"
        fi
        read -p "Proceed with installation of $pkg? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
    else
        print_msg warn "Could not retrieve PKGBUILD for $pkg, proceeding without review"
    fi
}

install_pacman_pkgs() {
    local pkgs=("${@}")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        print_msg info "No pacman packages to install"
        return
    fi
    print_msg info "Installing pacman packages: ${pkgs[*]}"
    local failed_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if ! sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
            print_msg warn "Failed to install $pkg, it may not exist in pacman repositories"
            failed_pkgs+=("$pkg")
        fi
    done
    if [[ ${#failed_pkgs[@]} -eq 0 ]]; then
        print_msg success "Pacman packages installed"
    else
        print_msg warn "Some packages failed to install: ${failed_pkgs[*]}"
        echo "Failed pacman packages: ${failed_pkgs[*]}" >> "${LOGFILE}.failed"
    fi
}

install_aur_pkgs() {
    local pkgs=("${@}")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        print_msg info "No AUR packages to install"
        return
    fi
    print_msg info "Installing AUR packages: ${pkgs[*]}"
    local filtered_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if [[ "$pkg" == "linux-zen" && -n "${ZEN_APPROVED:-}" ]]; then
            filtered_pkgs+=("$pkg")
        else
            review_aur_pkgbuild "$pkg" && filtered_pkgs+=("$pkg")
        fi
    done
    if [[ ${#filtered_pkgs[@]} -gt 0 ]]; then
        yay -S --noconfirm --needed "${filtered_pkgs[@]}" || print_msg warn "Some AUR packages failed to install"
        print_msg success "AUR packages installed"
    else
        print_msg info "No AUR packages selected for installation"
    fi
}

install_photogimp() {
    print_msg info "Installing PhotoGIMP config directly into ~/.config/GIMP/3.0"

    for dep in curl unzip; do
        if ! command -v "$dep" &>/dev/null; then
            print_msg warn "$dep is not installed. Installing it..."
            sudo pacman -S --noconfirm --needed "$dep" || print_msg error "Failed to install $dep"
        fi
    done

    local temp_dir
    temp_dir=$(mktemp -d -t photogimp_temp.XXXXXX) || print_msg error "Failed to create temp dir"

    curl -L https://github.com/Diolinux/PhotoGIMP/archive/master.zip -o "$temp_dir/PhotoGIMP.zip" || {
        print_msg error "Failed to download PhotoGIMP"
        rm -rf "$temp_dir"
        return 1
    }

    unzip "$temp_dir/PhotoGIMP.zip" -d "$temp_dir" || {
        print_msg error "Failed to unzip PhotoGIMP"
        rm -rf "$temp_dir"
        return 1
    }

    local source_dir="$temp_dir/PhotoGIMP-master/.config/GIMP/3.0"
    local target_dir="$HOME/.config/GIMP/3.0"

    if [[ ! -d "$source_dir" ]]; then
        print_msg error "Expected source directory not found: $source_dir"
        rm -rf "$temp_dir"
        return 1
    fi

    # Backup gammal konfig
    if [[ -d "$target_dir" ]]; then
        cp -r "$target_dir" "${target_dir}.bak.$(date +%s)"
        print_msg info "Backed up existing GIMP config to ${target_dir}.bak.*"
    fi

    mkdir -p "$target_dir"
    # 🔥 Viktigt! Kopiera ALLT, inklusive dolda filer
    cp -rf "$source_dir"/. "$target_dir"/ || print_msg error "Failed to copy PhotoGIMP config"

    rm -rf "$temp_dir"
    print_msg success "PhotoGIMP configuration copied into ~/.config/GIMP/3.0"
    echo -e "${YELLOW}Starta om GIMP för att se ändringarna.${RESET}"
}

check_orphans() {
    set +e
    print_msg info "Checking for orphaned (unnecessary) packages"
    local orphans
    orphans=$(pacman -Qdtq)
    if [[ -z "$orphans" ]]; then
        print_msg success "No orphaned packages found"
    else
        print_msg warn "Found orphaned packages: $orphans"
        read -p "Remove orphaned packages? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            for pkg in $orphans; do
                if pacman -Q "$pkg" >/dev/null 2>&1; then
                    sudo pacman -Rns --noconfirm "$pkg" && print_msg success "Removed $pkg"
                elif yay -Q "$pkg" >/dev/null 2>&1; then
                    yay -Rns --noconfirm "$pkg" && print_msg success "Removed AUR package $pkg"
                else
                    print_msg warn "Package $pkg not found, skipping"
                fi
            done
        else
            print_msg info "Skipping removal of orphaned packages"
        fi
    fi
    set -e
}

clean_cache() {
    print_msg info "Checking package cache"
    read -p "Clean pacman and yay cache? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo pacman -Sc --noconfirm
        yay -Sc --noconfirm
        print_msg success "Package cache cleaned"
    else
        print_msg info "Skipping cache cleaning"
    fi
}

update_bootloader() {
    if [[ "$1" == "linux-zen" ]]; then
        print_msg info "Updating bootloader for linux-zen"
        read -p "Update bootloader to include linux-zen? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
                print_msg info "Configuring systemd-boot for linux-zen..."
                local entry="/boot/loader/entries/arch-zen.conf"
                sudo bash -c "cat > $entry" << EOF
title Arch Linux (Zen)
linux /vmlinuz-linux-zen
initrd /initramfs-linux-zen.img
options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/nvme0n1p2) rw
EOF
                sudo bootctl install
                print_msg success "systemd-boot updated. Select 'Arch Linux (Zen)' at boot."
            elif [[ "$BOOTLOADER" == "grub" ]]; then
                print_msg info "Configuring GRUB for linux-zen..."
                sudo grub-mkconfig -o /boot/grub/grub.cfg
                print_msg success "GRUB updated. Select linux-zen from GRUB menu at boot."
            fi
        else
            print_msg info "Skipping bootloader update. You must manually configure $BOOTLOADER to use linux-zen."
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
    vkd3d
    lutris
    pipewire
    pipewire-pulse
    irqbalance
)
AUR_PKGS=(
    proton-ge-custom
    linux-zen
    dxvk-bin
    goverlay
    hunspell-sv
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

show_menu() {
    echo -e "${BLUE}${BOLD}Arch Linux Post-Post Install Menu${RESET}"
    echo "1. Install all components (gaming, productivity, PhotoGIMP, AUR, optimizations)"
    echo "2. Install gaming stack (Steam, Vulkan, Wine, etc.)"
    echo "3. Install productivity apps (LibreOffice, digiKam)"
    echo "4. Install PhotoGIMP and AUR packages (Proton-GE, linux-zen, etc.)"
    echo "5. Enable system optimizations (ZRAM, gamemoded, linux-zen)"
    echo "6. Check and remove orphaned packages"
    echo "7. Clean package cache"
    echo "8. Exit"
    read -p "Select an option [1-8]: " choice
}

enable_system_optimizations() {
    set +e
    print_msg info "Enabling system optimizations"
    read -p "Enable gamemoded service for gaming performance? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if systemctl list-units --full | grep -q gamemoded.service; then
            sudo systemctl enable --now gamemoded
            print_msg success "gamemoded enabled"
        else
            print_msg warn "gamemoded.service not found. Ensure gamemode is installed and configured."
        fi
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

    read -p "Enable irqbalance for network performance? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl enable --now irqbalance
        print_msg success "irqbalance enabled"
    else
        print_msg info "Skipping irqbalance activation"
    fi
    set -e
}

main() {
    print_msg info "Starting Arch post-post install script"

    # Run safety checks
    check_sudo
    check_internet
    check_system_status
    check_disk_space
    check_bootloader

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
                check_package_availability pacman "${PACMAN_PKGS[@]}"
                check_package_availability pacman "${GAMING_PKGS[@]}"
                check_package_availability aur "${AUR_PKGS[@]}"
                install_pacman_pkgs "${PACMAN_PKGS[@]}"
                install_pacman_pkgs "${GAMING_PKGS[@]}"
                install_photogimp
                install_aur_pkgs "${AUR_PKGS[@]}"
                enable_system_optimizations
                update_bootloader linux-zen
                break
                ;;
            2)
                check_package_availability pacman "${GAMING_PKGS[@]}"
                install_pacman_pkgs "${GAMING_PKGS[@]}"
                ;;
            3)
                check_package_availability pacman "${PACMAN_PKGS[@]}"
                install_pacman_pkgs "${PACMAN_PKGS[@]}"
                ;;
            4)
                check_package_availability aur "${AUR_PKGS[@]}"
                install_photogimp
                install_aur_pkgs "${AUR_PKGS[@]}"
                update_bootloader linux-zen
                ;;
            5)
                enable_system_optimizations
                check_package_availability aur linux-zen
                ZEN_APPROVED=1 install_aur_pkgs linux-zen
                update_bootloader linux-zen
                ;;
            6)
                check_orphans
                ;;
            7)
                clean_cache
                ;;
            8)
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
    if [[ -f "${LOGFILE}.failed" ]]; then
        echo -e "${YELLOW}${BOLD}Note:${RESET} Some packages failed to install. Check ${LOGFILE}.failed for details."
    fi
}

main
