#!/usr/bin/env bash
# nirucon-alppi.sh - Arch Linux Post-Post Install Script
# Date: 2025-04-22
# Author: Nicklas Rudolfsson
# License: MIT
# Description:
#   A robust, user-friendly script for post-post installation on Arch Linux.
#   Features:
#     - Interactive, visually appealing menu
#     - Safe pacman.conf modification with backups and rollback
#     - Robust Chaotic-AUR setup with retries
#     - Installs gaming stack (Steam, Vulkan, Wine, MangoHud, Corectrl, VKBasalt, Lutris)
#     - Installs productivity apps (LibreOffice, digiKam)
#     - Installs PhotoGIMP with version checks and dual-directory support
#     - Installs AUR packages (Proton-GE, linux-zen, dxvk-bin, goverlay)
#     - Optional system optimizations (ZRAM, gamemoded, linux-zen)
#     - Supports systemd-boot and GRUB for linux-zen
#     - Comprehensive safety checks (sudo, internet, disk space, system status)
#     - Package availability validation
#     - Orphaned package cleanup and cache management

set -euo pipefail
IFS=$'\n\t'

# Constants
CHAOTIC_KEY="3056513887B78AEB"
CHAOTIC_KEYSERVER="keyserver.ubuntu.com"
CHAOTIC_URL="https://cdn-mirror.chaotic.cx/chaotic-aur"
LOGFILE="/tmp/nirucon-alppi_$(date +%F_%H%M%S).log"
ERROR_LOG="${LOGFILE}.errors"
FAILED_LOG="${LOGFILE}.failed"
MIN_DISK_SPACE_MB=2000  # Minimum disk space required in MB
MAX_RETRIES=3  # Max retries for network operations

# Colors
if command -v tput &>/dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; MAGENTA='\e[35m'; BOLD='\e[1m'; RESET='\e[0m'
fi

exec > >(tee -a "${LOGFILE}") 2> >(tee -a "${ERROR_LOG}" >&2)

# Handle interrupts (Ctrl+C)
cleanup() {
    print_msg warn "Script interrupted, cleaning up..."
    [[ -f "/tmp/pacman.conf.tmp" ]] && rm -f /tmp/pacman.conf.tmp
    [[ -d "/tmp/photogimp_temp" ]] && rm -rf /tmp/photogimp_temp
    print_msg info "Exiting safely. Logs saved at $LOGFILE"
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
        prompt)  echo -e "${MAGENTA}${BOLD}[INPUT]${RESET} $message";;
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
    local endpoints=("archlinux.org" "google.com" "cloudflare.com")
    local success=false
    for endpoint in "${endpoints[@]}"; do
        if ping -c 1 "$endpoint" &>/dev/null || curl -s --head --fail "https://$endpoint" &>/dev/null; then
            success=true
            break
        fi
    done
    if [[ "$success" == false ]]; then
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
    local filesystems=("/" "/home" "/tmp")
    for fs in "${filesystems[@]}"; do
        if [[ -d "$fs" ]]; then
            local available_space
            available_space=$(df -m "$fs" | tail -1 | awk '{print $4}')
            if (( available_space < MIN_DISK_SPACE_MB )); then
                print_msg error "Insufficient disk space in $fs (${available_space} MB available, ${MIN_DISK_SPACE_MB} MB required)."
            fi
            print_msg success "Sufficient disk space in $fs (${available_space} MB)"
        fi
    done
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

check_essential_tools() {
    print_msg info "Checking essential tools"
    local tools=(curl unzip lspci grep sed awk less)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_msg info "$tool is missing. Installing..."
            sudo pacman -S --noconfirm --needed "${tool}" || print_msg error "Failed to install $tool."
        fi
    done
    print_msg success "All essential tools verified"
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

refresh_mirrorlist() {
    print_msg info "Refreshing mirrorlist"
    sudo pacman -Syy
    if command -v reflector &>/dev/null; then
        sudo reflector --country 'SE,DE,FR' --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        print_msg success "Mirrorlist refreshed with reflector"
    else
        print_msg warn "reflector not found, using existing mirrorlist"
    fi
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
            local attempt=1
            while [[ $attempt -le $MAX_RETRIES ]]; do
                if sudo pacman-key --recv-key "${CHAOTIC_KEY}" --keyserver "${CHAOTIC_KEYSERVER}"; then
                    break
                fi
                print_msg warn "Failed to retrieve Chaotic-AUR key (attempt $attempt/$MAX_RETRIES)"
                ((attempt++))
                sleep 2
            done
            [[ $attempt -le $MAX_RETRIES ]] || print_msg error "Failed to retrieve Chaotic-AUR key after $MAX_RETRIES attempts."
            sudo pacman-key --lsign-key "${CHAOTIC_KEY}"
            sudo pacman -U --noconfirm \
                "${CHAOTIC_URL}/chaotic-keyring.pkg.tar.zst" \
                "${CHAOTIC_URL}/chaotic-mirrorlist.pkg.tar.zst" || {
                print_msg error "Failed to install Chaotic-AUR keyring/mirrorlist."
            }
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
            if ! pacman -Sp "$pkg" >/dev/null 2>>"${ERROR_LOG}"; then
                print_msg warn "Package $pkg not found in pacman repositories, checking AUR"
                if yay -Sp "$pkg" >/dev/null 2>>"${ERROR_LOG}"; then
                    AUR_PKGS+=("$pkg")
                    GAMING_PKGS=("${GAMING_PKGS[@]/$pkg}")
                    PACMAN_PKGS=("${PACMAN_PKGS[@]/$pkg}")
                else
                    failed_pkgs+=("$pkg")
                fi
            fi
        elif [[ "$pkg_type" == "aur" ]]; then
            if ! yay -Sp "$pkg" >/dev/null 2>>"${ERROR_LOG}"; then
                failed_pkgs+=("$pkg")
            fi
        fi
    done
    if [[ ${#failed_pkgs[@]} -gt 0 ]]; then
        print_msg warn "Some packages not found: ${failed_pkgs[*]}. They will be skipped."
        echo "Failed packages: ${failed_pkgs[*]}" >> "${FAILED_LOG}"
    fi
}

review_aur_pkgbuild() {
    local pkg="$1"
    print_msg info "Reviewing PKGBUILD for $pkg"
    local pkgbuild_file="/tmp/PKGBUILD.$pkg"
    if yay -Gp "$pkg" > "$pkgbuild_file" 2>>"${ERROR_LOG}"; then
        if [[ -s "$pkgbuild_file" ]]; then
            less "$pkgbuild_file"
            print_msg prompt "Proceed with installation of $pkg? [y/N]: "
            read -r answer
            [[ "$answer" =~ ^[Yy]$ ]] || return 1
        else
            print_msg warn "PKGBUILD for $pkg is empty, proceeding without review"
        fi
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
        if ! sudo pacman -S --noconfirm --needed "$pkg" 2>>"${ERROR_LOG}"; then
            print_msg warn "Failed to install $pkg, it may not exist in pacman repositories"
            failed_pkgs+=("$pkg")
        fi
    done
    if [[ ${#failed_pkgs[@]} -eq 0 ]]; then
        print_msg success "Pacman packages installed"
    else
        print_msg warn "Some packages failed to install: ${failed_pkgs[*]}"
        echo "Failed pacman packages: ${failed_pkgs[*]}" >> "${FAILED_LOG}"
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
        if yay -S --noconfirm --needed "${filtered_pkgs[@]}" 2>>"${ERROR_LOG}"; then
            print_msg success "AUR packages installed"
        else
            print_msg warn "Some AUR packages failed to install. Check $ERROR_LOG for details."
        fi
    else
        print_msg info "No AUR packages selected for installation"
    fi
}

install_photogimp() {
    print_msg info "Installing PhotoGIMP..."

    # Determine the actual user's home directory, even if run with sudo
    local user_name="$USER"
    local user_home="$HOME"
    if [[ -n "${SUDO_USER:-}" ]]; then
        user_name="$SUDO_USER"
        user_home=$(eval echo "~$SUDO_USER")
    fi

    # Step 1: Check prerequisites
    if ! command -v gimp &>/dev/null; then
        print_msg error "GIMP is not installed. Please install GIMP and rerun."
    fi

    # Check GIMP version (PhotoGIMP is designed for GIMP 2.10)
    local gimp_version
    gimp_version=$(gimp --version | head -n1 | grep -o '[0-9]\.[0-9]*\.[0-9]*')
    if [[ "$gimp_version" != "2.10"* ]]; then
        print_msg warn "Detected GIMP version $gimp_version. PhotoGIMP is optimized for GIMP 2.10."
        print_msg prompt "Proceed with installation? [y/N]: "
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || {
            print_msg info "Aborting PhotoGIMP installation."
            return 1
        }
    fi

    # Check dependencies
    local deps=(curl unzip)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            print_msg info "$dep is missing. Installing..."
            sudo pacman -S --noconfirm --needed "$dep" || {
                print_msg error "Failed to install $dep."
                return 1
            }
        fi
    done

    # Check disk space
    local available_space
    available_space=$(df -m "$user_home" | tail -1 | awk '{print $4}')
    if (( available_space < MIN_DISK_SPACE_MB )); then
        print_msg error "Insufficient disk space in $user_home (${available_space} MB available, ${MIN_DISK_SPACE_MB} MB required)."
    fi

    # Step 2: Confirm overwrite of existing GIMP configs
    local config_dirs=("$user_home/.config/GIMP" "$user_home/.local/GIMP")
    local overwrite_needed=false
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            overwrite_needed=true
            print_msg warn "Existing GIMP configuration found at $dir."
        fi
    done
    if [[ "$overwrite_needed" == true ]]; then
        print_msg prompt "Overwrite existing GIMP configurations? [y/N]: "
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || {
            print_msg info "Aborting PhotoGIMP installation."
            return 1
        }
    fi

    # Step 3: Download and extract PhotoGIMP
    local temp_dir="/tmp/photogimp_temp_$$"
    mkdir -p "$temp_dir" || {
        print_msg error "Failed to create temporary directory $temp_dir."
        return 1
    }
    local photogimp_url="https://github.com/Diolinux/PhotoGIMP/archive/master.zip"
    print_msg info "Downloading PhotoGIMP from $photogimp_url..."
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        if curl -L --fail "$photogimp_url" -o "$temp_dir/PhotoGIMP.zip" 2>>"${ERROR_LOG}"; then
            break
        fi
        print_msg warn "Failed to download PhotoGIMP (attempt $attempt/$MAX_RETRIES)"
        ((attempt++))
        sleep 2
    done
    [[ $attempt -le $MAX_RETRIES ]] || {
        print_msg error "Failed to download PhotoGIMP zip after $MAX_RETRIES attempts."
        rm -rf "$temp_dir"
        return 1
    }

    print_msg info "Extracting archive..."
    if ! unzip -q "$temp_dir/PhotoGIMP.zip" -d "$temp_dir" 2>>"${ERROR_LOG}"; then
        print_msg error "Failed to extract PhotoGIMP archive."
        rm -rf "$temp_dir"
        return 1
    }

    local source_config="$temp_dir/PhotoGIMP-master/.config/GIMP"
    if [[ ! -d "$source_config" ]]; then
        print_msg error "Could not find GIMP configuration folder in the archive."
        rm -rf "$temp_dir"
        return 1
    }

    # Step 4: Copy PhotoGIMP configuration to both target directories
    for target_dir in "${config_dirs[@]}"; do
        print_msg info "Copying PhotoGIMP configuration to $target_dir..."
        mkdir -p "$(dirname "$target_dir")" || {
            print_msg error "Failed to create parent directory for $target_dir."
            rm -rf "$temp_dir"
            return 1
        }
        [[ -d "$target_dir" ]] && rm -rf "$target_dir"
        cp -r "$source_config" "$target_dir" || {
            print_msg error "Failed to copy PhotoGIMP configuration to $target_dir."
            rm -rf "$temp_dir"
            return 1
        }
        sudo chown -R "$user_name":"$user_name" "$target_dir" || {
            print_msg error "Failed to set ownership for $target_dir."
            rm -rf "$temp_dir"
            return 1
        }
        chmod -R u+rw "$target_dir" || {
            print_msg error "Failed to set permissions for $target_dir."
            rm -rf "$temp_dir"
            return 1
        }
    done

    # Step 5: Cleanup
    print_msg prompt "Remove temporary files at $temp_dir? [Y/n]: "
    read -r cleanup_answer
    if [[ ! "$cleanup_answer" =~ ^[Nn]$ ]]; then
        rm -rf "$temp_dir"
        print_msg info "Temporary files removed."
    else
        print_msg info "Temporary files left at $temp_dir for inspection."
    fi

    # Step 6: Done
    print_msg success "PhotoGIMP installed to ${config_dirs[*]}!"
    print_msg info "Launch GIMP to use the new Photoshop-like layout."
}

check_orphans() {
    set +e
    print_msg info "Checking for orphaned packages"
    local orphans
    orphans=$(pacman -Qdtq)
    if [[ -z "$orphans" ]]; then
        print_msg success "No orphaned packages found"
    else
        print_msg warn "Found orphaned packages: $orphans"
        print_msg prompt "Remove orphaned packages? [y/N]: "
        read -r answer
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
    print_msg prompt "Clean pacman and yay cache? [y/N]: "
    read -r answer
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
        print_msg prompt "Update bootloader to include linux-zen? [y/N]: "
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
                print_msg info "Configuring systemd-boot for linux-zen..."
                local root_part=$(findmnt -n -o SOURCE / | cut -d'[' -f1)
                local partuuid=$(blkid -s PARTUUID -o value "$root_part")
                if [[ -z "$partuuid" ]]; then
                    print_msg error "Could not determine PARTUUID for root partition."
                fi
                local entry="/boot/loader/entries/arch-zen.conf"
                sudo bash -c "cat > $entry" << EOF
title Arch Linux (Zen)
linux /vmlinuz-linux-zen
initrd /initramfs-linux-zen.img
options root=PARTUUID=$partuuid rw
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

# GPU detection
if command -v lspci &>/dev/null; then
    if lspci -k | grep -iE 'vga.*nvidia' &>/dev/null; then
        GAMING_PKGS+=(nvidia nvidia-utils lib32-nvidia-utils)
    elif lspci -k | grep -iE 'vga.*amd' &>/dev/null; then
        GAMING_PKGS+=(mesa vulkan-radeon lib32-vulkan-radeon)
    elif lspci -k | grep -iE 'vga.*intel' &>/dev/null; then
        GAMING_PKGS+=(mesa vulkan-intel lib32-vulkan-intel)
    else
        print_msg warn "No supported GPU detected; installing generic mesa"
        GAMING_PKGS+=(mesa)
    fi
else
    print_msg warn "lspci not found; installing generic mesa"
    GAMING_PKGS+=(mesa)
fi

show_menu() {
    clear
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${GREEN}${BOLD}       Arch Linux Post-Post Install Script by Nicklas       ${RESET}"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${YELLOW}Welcome! This script will help you set up your Arch Linux system.${RESET}"
    echo -e "${YELLOW}Please select an option from the menu below:${RESET}\n"
    echo -e "${BLUE}1.${RESET} Install all components (gaming, productivity, PhotoGIMP, AUR, optimizations)"
    echo -e "${BLUE}2.${RESET} Install gaming stack (Steam, Vulkan, Wine, etc.)"
    echo -e "${BLUE}3.${RESET} Install productivity apps (LibreOffice, digiKam)"
    echo -e "${BLUE}4.${RESET} Install PhotoGIMP and AUR packages (Proton-GE, linux-zen, etc.)"
    echo -e "${BLUE}5.${RESET} Enable system optimizations (ZRAM, gamemoded, linux-zen)"
    echo -e "${BLUE}6.${RESET} Check and remove orphaned packages"
    echo -e "${BLUE}7.${RESET} Clean package cache"
    echo -e "${BLUE}8.${RESET} Exit"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    print_msg prompt "Select an option [1-8]: "
    read -r choice
}

enable_system_optimizations() {
    set +e
    print_msg info "Enabling system optimizations"
    
    # Check system specs for optimization suitability
    local total_ram
    total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if (( total_ram < 8*1024*1024 )); then
        print_msg info "Low RAM detected ($((total_ram/1024)) MB). ZRAM recommended."
    fi

    print_msg prompt "Enable gamemoded service for gaming performance? [y/N]: "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if systemctl list-units --full | grep -q gamemoded.service; then
            sudo systemctl enable --now gamemoded
            print_msg success "gamemoded enabled"
        else
            print_msg warn "gamemoded.service not found. Ensure gamemode is installed."
        fi
    else
        print_msg info "Skipping gamemoded activation"
    fi

    print_msg prompt "Enable ZRAM for memory compression? [y/N]: "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo pacman -S --noconfirm zram-generator
        echo -e "[zram0]\nzram-size = ram / 2" | sudo tee /etc/systemd/zram-generator.conf
        sudo systemctl start systemd-zram-setup@zram0
        print_msg success "ZRAM enabled"
    else
        print_msg info "Skipping ZRAM setup"
    fi

    print_msg prompt "Enable irqbalance for network performance? [y/N]: "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl enable --now irqbalance
        print_msg success "irqbalance enabled"
    else
        print_msg info "Skipping irqbalance activation"
    fi
    set -e
}

main() {
    print_msg info "Starting Arch Linux post-post install script"

    # Prompt for sudo password upfront
    sudo -v || print_msg error "Failed to obtain sudo privileges."

    # Run safety checks
    check_sudo
    check_internet
    check_system_status
    check_disk_space
    check_bootloader
    check_essential_tools

    # Keep sudo alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    backup_configs
    refresh_mirrorlist
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

    print_msg success "All selected components installed!"
    echo -e "\n${GREEN}${BOLD}🎉 Installation Complete!${RESET}"
    echo -e "${BLUE}Logs saved at:${RESET} $LOGFILE"
    if [[ -f "${FAILED_LOG}" ]]; then
        echo -e "${YELLOW}${BOLD}⚠️ Note:${RESET} Some packages failed to install. Check ${FAILED_LOG} and ${ERROR_LOG} for details."
    fi
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
}

main
