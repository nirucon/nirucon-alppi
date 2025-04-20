#!/bin/bash

# Nirucon-ALPPI: Arch Linux Post-Post Install Script (Safe & Optimized)
# Version: 2025-04-20
# Author: Nicklas Rudolfsson
# GitHub: https://github.com/nirucon/nirucon-alppi
# License: MIT

# ================== CONFIG ==================
DRYRUN=0
[[ "$1" == "--dry-run" ]] && DRYRUN=1
LOGFILE="/tmp/nirucon-alppi.log"

# ================== COLORS ==================
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4)
    BOLD=$(tput bold); RESET=$(tput sgr0)
else
    RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'
    BOLD='\e[1m'; RESET='\e[0m'
fi

# ================== LOGGING ==================
exec 1> >(tee -a "$LOGFILE")
exec 2>&1

# ================== HELPERS ==================
print_message() {
    local type="$1" msg="$2"
    case "$type" in
        success) echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $msg" ;;
        error)   echo -e "${RED}${BOLD}[ERROR]${RESET}   $msg" >&2 ;;
        warning) echo -e "${YELLOW}${BOLD}[WARN]${RESET}    $msg" ;;
        info)    echo -e "${BLUE}${BOLD}[INFO]${RESET}    $msg" ;;
    esac
}

run_safe() {
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        eval "$@"
    fi
}

declare -A installed_components

# ================== FUNCTIONS ==================

display_welcome() {
    clear
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${BLUE}${BOLD}  Nirucon-ALPPI – Safe & Optimized Arch Post-Install  ${RESET}"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${YELLOW}Log file:${RESET} $LOGFILE"
    [[ "$DRYRUN" -eq 1 ]] && echo -e "${YELLOW}DRY-RUN mode: no changes will be made.${RESET}"
    echo
}

check_internet() {
    print_message info "Checking internet connection..."
    if ! ping -q -c1 archlinux.org &>/dev/null; then
        print_message error "No internet connection. Aborting."
        exit 1
    fi
    print_message success "Internet OK"
}

check_yay() {
    print_message info "Checking for yay..."
    if ! command -v yay &>/dev/null; then
        print_message error "yay is not installed. Install yay first."
        exit 1
    fi
    print_message success "yay detected"
}

validate_pacman_conf() {
    print_message info "Validating /etc/pacman.conf..."
    if grep -q '^\[options\]' /etc/pacman.conf &&
       grep -A10 '^\[options\]' /etc/pacman.conf | grep -q '^Server'; then
        print_message warning "'Server' lines under [options] detected; commenting out..."
        run_safe sudo cp /etc/pacman.conf /etc/pacman.conf.bak
        run_safe sudo awk '
            BEGIN { in_options=0 }
            /^\[options\]/          { in_options=1 }
            /^\[/ && !/^\[options\]/ { in_options=0 }
            in_options && /^Server/ { print "#" $0; next }
            { print }
        ' /etc/pacman.conf | sudo tee /etc/pacman.conf > /dev/null
        print_message success "/etc/pacman.conf sanitized"
    else
        print_message success "/etc/pacman.conf OK"
    fi
}

fix_mirrorlist() {
    print_message info "Checking mirrorlist..."
    if [ ! -s /etc/pacman.d/mirrorlist ] || grep -v '^#' /etc/pacman.d/mirrorlist | grep -q '^\[.*\]'; then
        print_message warning "mirrorlist invalid or empty; regenerating..."
        run_safe sudo mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak 2>/dev/null
        if ! command -v reflector &>/dev/null; then
            print_message info "Installing reflector..."
            run_safe sudo pacman -S --noconfirm reflector
        fi
        run_safe sudo reflector --country Sweden --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || {
            print_message warning "reflector failed; applying fallback..."
            echo -e "Server = https://mirror.archlinux.se/\$repo/os/\$arch\nServer = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" \
                | run_safe sudo tee /etc/pacman.d/mirrorlist > /dev/null
        }
        print_message success "mirrorlist updated"
    else
        print_message success "mirrorlist OK"
    fi
}

clear_yay_cache_prompt() {
    read -p "[?] Clear yay cache (optional)? [y/N]: " ans
    ans="${ans,,}"
    if [[ "$ans" =~ ^(y|yes)$ ]]; then
        print_message info "Clearing yay cache..."
        run_safe yay -Sc --noconfirm
    else
        print_message info "Skipped yay cache clean"
    fi
}

update_system() {
    print_message info "Updating system with pacman -Syu..."
    run_safe sudo pacman -Syu --noconfirm || {
        print_message error "System update failed"
        exit 1
    }
    print_message success "System updated"
}

install_chaotic_aur() {
    print_message info "Installing Chaotic-AUR keyring & mirrorlist..."
    run_safe sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    run_safe sudo pacman-key --lsign-key 3056513887B78AEB
    run_safe sudo pacman -U --noconfirm \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
    run_safe sudo bash -c "echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' >> /etc/pacman.conf"
    run_safe sudo pacman -Sy --noconfirm
    installed_components["chaotic-aur"]="Installed"
    print_message success "Chaotic-AUR added"
}

install_photogimp() {
    if ! pacman -Q gimp &>/dev/null; then
        print_message warning "GIMP not installed; skipping PhotoGIMP"
        installed_components["photogimp"]="Skipped"
        return
    fi
    print_message info "Installing PhotoGIMP..."
    local tmp=$(mktemp -d)
    run_safe curl -L https://github.com/Diolinux/PhotoGIMP/archive/master.zip -o "$tmp/photogimp.zip"
    run_safe unzip "$tmp/photogimp.zip" -d "$tmp"
    local src="$tmp/PhotoGIMP-master/GIMP/3.0"
    if [ ! -d "$src" ]; then
        src=$(find "$tmp/PhotoGIMP-master" -type d -name "3.0" | head -n1)
    fi
    run_safe mkdir -p "$HOME/.config/GIMP/3.0"
    run_safe cp -r "$src/"* "$HOME/.config/GIMP/3.0/"
    rm -rf "$tmp"
    installed_components["photogimp"]="Installed"
    print_message success "PhotoGIMP applied"
}

install_gaming() {
    print_message info "Installing gaming packages..."
    # enable multilib
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        print_message info "Enabling multilib repo..."
        run_safe sudo sed -i '/#\[multilib\]/s/^#//' /etc/pacman.conf
        run_safe sudo sed -i '/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
        run_safe sudo pacman -Sy --noconfirm
    fi

    local pkgs=(steam lib32-pipewire lib32-libpulse lib32-alsa-lib lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader gamemode wine protontricks mangohud)
    for pkg in "${pkgs[@]}"; do
        if pacman -Si "$pkg" &>/dev/null; then
            run_safe sudo pacman -S --noconfirm "$pkg"
        else
            run_safe yay -S --noconfirm "$pkg"
        fi
    done

    # GPU-specific
    if lspci -k | grep -iq nvidia; then
        run_safe sudo pacman -S --noconfirm nvidia nvidia-utils lib32-nvidia-utils
    elif lspci -k | grep -iqE 'amd|radeon'; then
        run_safe sudo pacman -S --noconfirm mesa vulkan-radeon lib32-vulkan-radeon
    elif lspci -k | grep -iq intel; then
        run_safe sudo pacman -S --noconfirm mesa vulkan-intel lib32-vulkan-intel
    fi

    installed_components["gaming"]="Installed"
    print_message success "Gaming stack installed"
}

install_components() {
    print_message info "=== Additional Components ==="
    local comps=(
        "Chaotic-AUR:add repo:custom:install_chaotic_aur"
        "PhotoGIMP:GIMP tweaks:custom:install_photogimp"
        "Gaming:Steam & Vulkan:custom:install_gaming"
    )
    for entry in "${comps[@]}"; do
        IFS=":" read -r name desc type func <<< "$entry"
        read -p "[?] Install $name ($desc)? [Y/n]: " ans
        ans="${ans,,}"
        if [[ "$ans" =~ ^(y|yes| ) ]] || [[ -z "$ans" ]]; then
            $func
        else
            installed_components["$name"]="Skipped"
            print_message info "Skipped $name"
        fi
    done
}

display_summary() {
    echo
    echo -e "${BLUE}${BOLD}=== Installation Summary ===${RESET}"
    for comp in "${!installed_components[@]}"; do
        echo -e " - ${BOLD}$comp:${RESET} ${installed_components[$comp]}"
    done
    echo -e "${BLUE}${BOLD}=============================${RESET}"
}

# ================== MAIN ==================
main() {
    sudo -v || { print_message error "Sudo auth failed"; exit 1; }
    display_welcome
    check_internet
    check_yay
    validate_pacman_conf
    fix_mirrorlist
    clear_yay_cache_prompt
    update_system
    install_components
    display_summary
    print_message info "All done! 🎉"
}

main "$@"
