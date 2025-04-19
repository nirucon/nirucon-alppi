#!/bin/bash

# Nirucon-ALPPI: Arch Linux Post-Post Install Script
# Version: 2025-04-19
# Author: Nicklas Rudolfsson
# GitHub: https://github.com/nirucon/nirucon-alppi
# Email: n@rudolfsson.net
# License: MIT License - Feel free to use and modify. Donations welcome: https://www.paypal.com/paypalme/nicklasrudolfsson
# Disclaimer:
# - Use at your own risk. The author is not responsible for any system issues.
# - This script is a work in progress and may not receive updates.
# Dependencies: Assumes nirucon-alpi.sh has been run, with yay installed.

# Initialize colors using tput for TTY compatibility
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED='\e[31m'
    GREEN='\e[32m'
    YELLOW='\e[33m'
    BLUE='\e[34m'
    BOLD='\e[1m'
    RESET='\e[0m'
fi

# Force color output in TTY
export TERM=xterm-256color

# Track installed components
declare -A installed_components

# Function: Print formatted messages
print_message() {
    local type="$1" msg="$2"
    case "$type" in
        success) echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $msg" ;;
        error) echo -e "${RED}${BOLD}[ERROR]${RESET} $msg" >&2 ;;
        warning) echo -e "${YELLOW}${BOLD}[WARNING]${RESET} $msg" ;;
        info) echo -e "${BLUE}${BOLD}[INFO]${RESET} $msg" ;;
    esac
}

# Function: Create temporary directory
create_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d 2>/dev/null) || { print_message error "Failed to create temporary directory"; exit 1; }
    echo "$temp_dir"
}

# Function: Check internet connection
check_internet() {
    print_message info "Checking internet connection..."
    ping -q -c 1 -W 1 archlinux.org >/dev/null 2>&1 || { print_message error "Internet connection required"; exit 1; }
    print_message success "Internet connection: OK"
}

# Function: Display welcome message
display_welcome() {
    clear
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${BLUE}${BOLD} Nirucon-ALPPI: Arch Linux Post-Post Install Script ${RESET}"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${RED}${BOLD}Disclaimer:${RESET} Use at your own risk. No responsibility for system issues."
    echo -e "${YELLOW}Version:${RESET} 2025-04-19 | ${YELLOW}Author:${RESET} Nicklas Rudolfsson | ${YELLOW}GitHub:${RESET} https://github.com/nirucon/nirucon-alppi"
    echo -e "${BLUE}${BOLD}------------------------------------------------------------${RESET}"
}

# Function: Confirm installation
confirm_proceed() {
    read -p "${BLUE}${BOLD}[?]${RESET} Continue with installation? [Y/n]: " confirm
    confirm="${confirm,,}"
    [[ "$confirm" == "n" ]] && { print_message warning "Installation aborted"; exit 0; }
    print_message success "Proceeding with installation..."
}

# Function: Install Chaotic-AUR
install_chaotic_aur() {
    print_message info "Installing Chaotic-AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || { print_message error "Failed to receive Chaotic-AUR key"; exit 1; }
    sudo pacman-key --lsign-key 3056513887B78AEB || { print_message error "Failed to sign Chaotic-AUR key"; exit 1; }
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || { print_message error "Failed to install Chaotic-AUR packages"; exit 1; }
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    sudo pacman -Sy || { print_message error "Failed to sync Chaotic-AUR"; exit 1; }
    installed_components["chaotic-aur"]="Installed"
    print_message success "Chaotic-AUR installed"
}

# Function: Install PhotoGIMP
install_photogimp() {
    print_message info "Installing PhotoGIMP..."
    local temp_dir=$(create_temp_dir)
    curl -L https://github.com/Diolinux/PhotoGIMP/archive/master.zip -o "$temp_dir/PhotoGIMP.zip" || {
        print_message error "Failed to download PhotoGIMP"
        rm -rf "$temp_dir"
        installed_components["photogimp"]="Failed"
        return
    }
    unzip "$temp_dir/PhotoGIMP.zip" -d "$temp_dir" || {
        print_message error "Failed to unzip PhotoGIMP"
        rm -rf "$temp_dir"
        installed_components["photogimp"]="Failed"
        return
    }

    local photogimp_config_dir
    if [ -d "$temp_dir/PhotoGIMP-master/GIMP/3.0" ]; then
        photogimp_config_dir="$temp_dir/PhotoGIMP-master/GIMP/3.0"
    elif [ -d "$temp_dir/PhotoGIMP-master/.var/app/org.gimp.GIMP/config/GIMP/3.0" ]; then
        photogimp_config_dir="$temp_dir/PhotoGIMP-master/.var/app/org.gimp.GIMP/config/GIMP/3.0"
    else
        print_message warning "PhotoGIMP configuration directory for GIMP 3.0 not found. Skipping configuration copy."
        rm -rf "$temp_dir"
        installed_components["photogimp"]="Partially installed (config not applied)"
        return
    fi

    if [ -d "$HOME/.config/GIMP/3.0" ]; then
        print_message info "Backing up existing GIMP configuration to ~/.config/GIMP/3.0.bak..."
        cp -r "$HOME/.config/GIMP/3.0" "$HOME/.config/GIMP/3.0.bak"
    fi
    mkdir -p ~/.config/GIMP/3.0
    print_message info "Applying PhotoGIMP configuration..."
    cp -r "$photogimp_config_dir/"* ~/.config/GIMP/3.0/ || {
        print_message error "Failed to apply PhotoGIMP configuration"
        rm -rf "$temp_dir"
        installed_components["photogimp"]="Failed"
        return
    }
    rm -rf "$temp_dir"
    installed_components["photogimp"]="Installed"
    print_message success "PhotoGIMP installed"
}

# Function: Install components
install_components() {
    print_message info "=== Additional Components ==="
    # Define components: name, description, type (pacman/yay/custom), package(s)/function
    local components=(
        "chaotic-aur:Additional AUR repository with precompiled packages:custom:install_chaotic_aur"
        "libreoffice-fresh:Full-featured office suite (Writer, Calc, Impress, etc.):pacman:libreoffice-fresh"
        "libreoffice-fresh-sv:Swedish language support and spellcheck for LibreOffice:pacman:libreoffice-fresh-sv hunspell-sv"
        "digikam:Professional photo management and editing software:pacman:digikam"
        "gimp:GIMP image editor with PhotoGIMP customization:pacman:gimp"
        "photogimp:Customizes GIMP to resemble Photoshop (requires GIMP):custom:install_photogimp"
    )
    local selected_pacman=() selected_custom=()

    read -p "${BLUE}${BOLD}[?]${RESET} Install additional components? [Y/n]: " choice
    choice="${choice,,}"
    [[ "$choice" == "n" ]] && { installed_components["components"]="Skipped"; return; }

    for component in "${components[@]}"; do
        local name="${component%%:*}"
        local desc="${component#*:}"
        desc="${desc%%:*}"
        local type="${component#*:*:}"
        type="${type%%:*}"
        local pkg_or_func="${component##*:}"

        # Skip if already installed
        if [[ "$type" == "pacman" ]]; then
            local pkg_check="${pkg_or_func%% *}"
            pacman -Qq "$pkg_check" &>/dev/null && { print_message info "$name already installed"; continue; }
        elif [[ "$type" == "custom" && -n "${installed_components[$name]}" ]]; then
            print_message info "$name already processed"; continue
        fi

        read -p "${BLUE}${BOLD}[?]${RESET} Install $name ($desc)? [Y/n]: " comp_choice
        comp_choice="${comp_choice,,}"
        if [[ "$comp_choice" =~ ^(yes|y| ) ]] || [[ -z "$comp_choice" ]]; then
            if [[ "$type" == "pacman" ]]; then
                selected_pacman+=("$pkg_or_func")
            elif [[ "$type" == "custom" ]]; then
                selected_custom+=("$name:$pkg_or_func")
            fi
        fi
    done

    if [[ ${#selected_pacman[@]} -eq 0 ]] && [[ ${#selected_custom[@]} -eq 0 ]]; then
        print_message warning "No components selected"
        installed_components["components"]="None selected"
        return
    fi

    # Install pacman packages
    if [[ ${#selected_pacman[@]} -gt 0 ]]; then
        sudo pacman -S --noconfirm "${selected_pacman[@]}" || { print_message error "Failed to install pacman components"; exit 1; }
        for pkg in "${selected_pacman[@]}"; do
            local pkg_name="${pkg%% *}"
            installed_components["$pkg_name"]="Installed"
        done
    fi

    # Install custom components
    for custom in "${selected_custom[@]}"; do
        local name="${custom%%:*}"
        local func="${custom##*:}"
        $func
    done

    installed_components["components"]="Installed"
    print_message success "Additional components installed"
}

# Function: Display summary
display_summary() {
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${BLUE}${BOLD} Installation Summary ${RESET}"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    for component in "${!installed_components[@]}"; do
        echo -e "${GREEN}${BOLD}$component:${RESET} ${installed_components[$component]}"
    done
    echo -e "${BLUE}${BOLD}------------------------------------------------------------${RESET}"
}

# Main function
main() {
    sudo -v || { print_message error "Sudo authentication failed"; exit 1; }
    display_welcome
    check_internet
    confirm_proceed
    install_components
    display_summary
    print_message info "=== Installation Complete ==="
}

main
