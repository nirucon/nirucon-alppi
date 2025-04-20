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

# Enable logging
exec 1> >(tee -a "/tmp/nirucon-alppi.log")
exec 2>&1

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

# Function: Check and fix mirrorlist
check_mirrorlist() {
    print_message info "Checking pacman configuration and mirrorlists..."

    # Log pacman and yay versions
    print_message info "Pacman version: $(pacman --version | head -n 1)"
    print_message info "Yay version: $(yay --version | head -n 1)"

    # Log shell aliases and environment variables
    print_message info "Checking shell aliases for pacman or yay..."
    local aliases
    aliases=$(alias | grep -E "pacman|yay" || echo "None")
    print_message info "Aliases:\n$aliases"
    print_message info "Checking environment variables for PACMAN or ALPM..."
    local env_vars
    env_vars=$(env | grep -E "PACMAN|ALPM" || echo "None")
    print_message info "Environment variables:\n$env_vars"

    # Log modification history of key configuration files
    print_message info "Checking modification history of configuration files..."
    for file in /etc/pacman.conf /etc/pacman.d/mirrorlist /etc/pacman.d/chaotic-mirrorlist; do
        if [ -f "$file" ]; then
            print_message info "Modification time of $file: $(stat -c %y "$file")"
        else
            print_message warning "$file does not exist"
        fi
    done

    # Check for backups and compare
    for file in /etc/pacman.conf.bak /etc/pacman.d/mirrorlist.bak /etc/pacman.d/chaotic-mirrorlist.bak; do
        if [ -f "$file" ]; then
            local original="${file%.bak}"
            print_message info "Backup found: $file"
            print_message info "Differences between $file and $original:"
            diff "$file" "$original" | while read -r line; do
                print_message info "  $line"
            done
            # Check if backup is valid (no [options] with Server)
            if ! grep -q '^\[options\]' "$file" || ! grep -A 10 '^\[options\]' "$file" | grep -q '^Server'; then
                print_message info "Backup $file appears valid. Restoring..."
                sudo cp "$file" "$original" || {
                    print_message error "Failed to restore $file to $original"
                }
            else
                print_message warning "Backup $file contains invalid [options] with Server. Not restoring."
            fi
        fi
    done

    # Log all configuration files loaded by pacman
    print_message info "Checking configuration files loaded by pacman..."
    local pacman_conf_files
    pacman_conf_files=$(sudo pacman -Syu --debug 2>&1 | grep "loading.*conf" | awk '{print $NF}' | sort -u)
    if [ -n "$pacman_conf_files" ]; then
        print_message info "Pacman is loading the following configuration files:"
        echo "$pacman_conf_files" | while read -r file; do
            print_message info "  - $file"
            if [ -f "$file" ]; then
                print_message info "Content of $file:"
                cat "$file" | while read -r line; do
                    print_message info "    $line"
                done
            else
                print_message warning "File $file does not exist"
            fi
        done
    else
        print_message warning "No configuration files detected by pacman --debug"
    fi

    # Check /etc/pacman.conf for invalid Server directives in [options]
    if grep -q '^\[options\]' /etc/pacman.conf && grep -A 10 '^\[options\]' /etc/pacman.conf | grep -q '^Server'; then
        print_message warning "Found invalid 'Server' directive in [options] section of /etc/pacman.conf. Backing up and fixing..."
        sudo cp /etc/pacman.conf /etc/pacman.conf.bak || {
            print_message error "Failed to backup /etc/pacman.conf"
            exit 1
        }
        sudo sed -i '/^\[options\]/,/^$/s/^Server/#Server/' /etc/pacman.conf || {
            print_message error "Failed to comment out Server directives in /etc/pacman.conf"
            exit 1
        }
    fi

    # Check /etc/pacman.d/mirrorlist
    if [ ! -s /etc/pacman.d/mirrorlist ] || grep -q '^\[.*\]' /etc/pacman.d/mirrorlist; then
        print_message warning "Invalid or empty /etc/pacman.d/mirrorlist detected. Attempting to fix..."
        sudo mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak 2>/dev/null || {
            print_message warning "No existing mirrorlist to backup"
        }
        if ! command -v reflector >/dev/null 2>&1; then
            print_message info "Installing reflector for optimized mirrorlist..."
            sudo pacman -S --noconfirm reflector || {
                print_message warning "Failed to install reflector. Using fallback mirrorlist..."
                echo -e "# Arch Linux mirrorlist\nServer = https://mirror.archlinux.se/\$repo/os/\$arch\nServer = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist >/dev/null || {
                    print_message error "Failed to create fallback mirrorlist"
                    exit 1
                }
            }
        fi
        if command -v reflector >/dev/null 2>&1; then
            print_message info "Generating new mirrorlist with reflector..."
            sudo reflector --country Sweden --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || {
                print_message warning "Failed to generate new mirrorlist with reflector. Using fallback..."
                echo -e "# Arch Linux mirrorlist\nServer = https://mirror.archlinux.se/\$repo/os/\$arch\nServer = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist >/dev/null || {
                    print_message error "Failed to create fallback mirrorlist"
                    exit 1
                }
            }
        fi
    else
        print_message success "/etc/pacman.d/mirrorlist is valid"
    fi

    # Check /etc/pacman.d/chaotic-mirrorlist if it exists
    if [ -f /etc/pacman.d/chaotic-mirrorlist ]; then
        if [ ! -s /etc/pacman.d/chaotic-mirrorlist ] || grep -q '^\[.*\]' /etc/pacman.d/chaotic-mirrorlist; then
            print_message warning "Invalid or empty /etc/pacman.d/chaotic-mirrorlist detected. Attempting to fix..."
            sudo mv /etc/pacman.d/chaotic-mirrorlist /etc/pacman.d/chaotic-mirrorlist.bak 2>/dev/null || {
                print_message warning "No existing chaotic-mirrorlist to backup"
            }
            echo -e "Server = https://cdn-mirror.chaotic.cx/chaotic-aur/\$arch\nServer = https://geo-mirror.chaotic.cx/chaotic-aur/\$arch" | sudo tee /etc/pacman.d/chaotic-mirrorlist >/dev/null || {
                print_message error "Failed to create chaotic-mirrorlist"
                exit 1
            }
        else
            print_message success "/etc/pacman.d/chaotic-mirrorlist is valid"
        fi
    fi

    # Check /etc/pacman.d/gnupg/ for unexpected configuration files
    print_message info "Checking /etc/pacman.d/gnupg/ for unexpected configuration files..."
    local gnupg_files
    gnupg_files=$(find /etc/pacman.d/gnupg/ -type f -name "*.conf")
    if [ -n "$gnupg_files" ]; then
        print_message warning "Found unexpected configuration files in /etc/pacman.d/gnupg/: $gnupg_files"
        echo "$gnupg_files" | while read -r file; do
            print_message warning "Content of $file:"
            cat "$file" | while read -r line; do
                print_message warning "  $line"
            done
        done
    else
        print_message success "No unexpected configuration files in /etc/pacman.d/gnupg/"
    fi

    # Check for [options] or Server in other pacman.d files
    local invalid_files
    invalid_files=$(find /etc/pacman.d/ -type f -exec grep -l -E "^\[options\]|^Server" {} \;)
    if [ -n "$invalid_files" ]; then
        print_message warning "Found [options] or Server directives in the following files: $invalid_files"
        echo "$invalid_files" | while read -r file; do
            print_message warning "Content of $file:"
            cat "$file" | while read -r line; do
                print_message warning "  $line"
            done
        done
        print_message warning "Please inspect and correct these files manually, or back them up and remove them."
    fi

    # Clear pacman and yay cache
    print_message info "Clearing pacman and yay cache to avoid cached configuration issues..."
    sudo pacman -Scc --noconfirm || {
        print_message warning "Failed to clear pacman cache"
    }
    yay -Sc --noconfirm || {
        print_message warning "Failed to clear yay cache"
    }

    # Sync repositories
    sudo pacman -Sy || {
        print_message error "Failed to sync repositories after checking mirrorlists"
        exit 1
    }
    print_message success "Mirrorlist configurations checked and repositories synced"
}

# Function: Check if yay is installed
check_yay() {
    print_message info "Checking if yay is installed..."
    if ! command -v yay >/dev/null 2>&1; then
        print_message error "yay is not installed. Please install yay (e.g., via nirucon-alpi.sh) and try again."
        exit 1
    fi
    print_message success "yay is installed"
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

# Function: Install Chaotic-AUR
install_chaotic_aur() {
    print_message info "Installing Chaotic-AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || { print_message error "Failed to receive Chaotic-AUR key"; exit 1; }
    sudo pacman-key --lsign-key 3056513887B78AEB || { print_message error "Failed to sign Chaotic-AUR key"; exit 1; }
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || { print_message error "Failed to install Chaotic-AUR packages"; exit 1; }
    # Verify chaotic-mirrorlist before appending
    if [ -f /etc/pacman.d/chaotic-mirrorlist ] && ! grep -q '^\[.*\]' /etc/pacman.d/chaotic-mirrorlist; then
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    else
        print_message warning "Chaotic-mirrorlist is invalid or missing. Writing fallback..."
        echo -e "Server = https://cdn-mirror.chaotic.cx/chaotic-aur/\$arch\nServer = https://geo-mirror.chaotic.cx/chaotic-aur/\$arch" | sudo tee /etc/pacman.d/chaotic-mirrorlist >/dev/null
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    fi
    sudo pacman -Sy || { print_message error "Failed to sync Chaotic-AUR"; exit 1; }
    installed_components["chaotic-aur"]="Installed"
    print_message success "Chaotic-AUR installed"
}

# Function: Install PhotoGIMP
install_photogimp() {
    if ! pacman -Q gimp &>/dev/null; then
        print_message warning "GIMP is not installed. Skipping PhotoGIMP installation."
        installed_components["photogimp"]="Skipped (GIMP not installed)"
        return
    fi

    print_message info "Installing PhotoGIMP for GIMP 3.0..."
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
    # Look for GIMP 3.0 config directory, fallback to any GIMP config if 3.0 not found
    if [ -d "$temp_dir/PhotoGIMP-master/GIMP/3.0" ]; then
        photogimp_config_dir="$temp_dir/PhotoGIMP-master/GIMP/3.0"
    elif [ -d "$temp_dir/PhotoGIMP-master/.var/app/org.gimp.GIMP/config/GIMP/3.0" ]; then
        photogimp_config_dir="$temp_dir/PhotoGIMP-master/.var/app/org.gimp.GIMP/config/GIMP/3.0"
    else
        # Fallback to any GIMP config directory
        photogimp_config_dir=$(find "$temp_dir/PhotoGIMP-master" -type d -path "*/GIMP/*" -maxdepth 3 | head -n 1)
        if [ -z "$photogimp_config_dir" ]; then
            print_message warning "PhotoGIMP configuration directory not found. Skipping configuration copy."
            rm -rf "$temp_dir"
            installed_components["photogimp"]="Partially installed (config not applied)"
            return
        fi
        print_message warning "GIMP 3.0 config not found in PhotoGIMP repo. Using $photogimp_config_dir as fallback."
    fi

    # Backup existing GIMP configuration
    local gimp_config_dir="$HOME/.config/GIMP/3.0"
    if [ -d "$gimp_config_dir" ]; then
        print_message info "Backing up existing GIMP configuration to $gimp_config_dir.bak..."
        cp -r "$gimp_config_dir" "$gimp_config_dir.bak" || {
            print_message error "Failed to backup GIMP configuration"
            rm -rf "$temp_dir"
            installed_components["photogimp"]="Failed"
            return
        }
    fi

    # Apply PhotoGIMP configuration
    mkdir -p "$gimp_config_dir"
    print_message info "Applying PhotoGIMP configuration to $gimp_config_dir..."
    cp -r "$photogimp_config_dir/"* "$gimp_config_dir/" || {
        print_message error "Failed to apply PhotoGIMP configuration"
        rm -rf "$temp_dir"
        installed_components["photogimp"]="Failed"
        return
    }

    rm -rf "$temp_dir"
    installed_components["photogimp"]="Installed"
    print_message success "PhotoGIMP installed and configured for GIMP 3.0"
}

# Function: Install Steam and gaming-related components
install_gaming() {
    print_message info "Installing Steam and gaming components..."

    # Check if multilib is enabled
    if ! grep -q '^\[multilib\]' /etc/pacman.conf || ! grep -q '^Include = /etc/pacman.d/mirrorlist' /etc/pacman.conf -A 1; then
        print_message warning "Multilib repository is not enabled. Enabling it now..."
        sudo cp /etc/pacman.conf /etc/pacman.conf.bak || {
            print_message error "Failed to backup /etc/pacman.conf"
            exit 1
        }
        sudo sed -i '/#\[multilib\]/s/^#//; /#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf || {
            print_message error "Failed to enable multilib repository"
            exit 1
        }
        sudo pacman -Sy || {
            print_message error "Failed to sync repositories after enabling multilib"
            exit 1
        }
        print_message success "Multilib repository enabled"
    fi

    # Define gaming-related packages
    local gaming_packages=(
        "steam"                     # Steam client
        "lib32-pipewire"            # 32-bit PipeWire for audio compatibility
        "lib32-libpulse"            # 32-bit PulseAudio for audio compatibility
        "lib32-alsa-lib"            # 32-bit ALSA for audio
        "lib32-mesa"                # 32-bit Mesa for OpenGL/Vulkan
        "vulkan-icd-loader"         # Vulkan loader
        "lib32-vulkan-icd-loader"   # 32-bit Vulkan loader
        "gamemode"                  # Optimizes system for gaming
        "wine"                      # For running Windows games
        "protontricks"              # For managing Proton prefixes
        "mangohud"                  # Performance overlay for games
    )

    # Detect GPU and add appropriate driver packages
    if lspci -k | grep -iE 'vga.*nvidia' >/dev/null; then
        print_message info "NVIDIA GPU detected. Including NVIDIA-specific packages."
        gaming_packages+=("nvidia" "nvidia-utils" "lib32-nvidia-utils")
    elif lspci -k | grep -iE 'vga.*(amd|radeon)' >/dev/null; then
        print_message info "AMD GPU detected. Including AMD-specific packages."
        gaming_packages+=("mesa" "vulkan-radeon" "lib32-vulkan-radeon")
    elif lspci -k | grep -iE 'vga.*intel' >/dev/null; then
        print_message info "Intel GPU detected. Including Intel-specific packages."
        gaming_packages+=("mesa" "vulkan-intel" "lib32-vulkan-intel")
    else
        print_message warning "No supported GPU detected. Installing generic Mesa drivers."
        gaming_packages+=("mesa")
    fi

    # Install gaming packages with fallback to yay
    for pkg in "${gaming_packages[@]}"; do
        if ! pacman -Si "$pkg" >/dev/null 2>&1; then
            print_message info "Package $pkg not found in pacman repos. Trying yay..."
            yay -S --noconfirm "$pkg" || {
                print_message warning "Failed to install $pkg with yay"
            }
        else
            sudo pacman -S --noconfirm "$pkg" || {
                print_message warning "Failed to install $pkg with pacman"
            }
        fi
    done

    # Install optional Chaotic-AUR gaming packages
    if [[ "${installed_components['chaotic-aur']}" == "Installed" ]]; then
        read -p "${BLUE}${BOLD}[?]${RESET} Install Proton-GE-Custom from Chaotic-AUR for enhanced Steam Play? [Y/n]: " proton_choice
        proton_choice="${proton_choice,,}"
        if [[ "$proton_choice" =~ ^(yes|y| ) ]] || [[ -z "$proton_choice" ]]; then
            sudo pacman -S --noconfirm proton-ge-custom || {
                print_message warning "Failed to install proton-ge-custom"
            }
        fi

        read -p "${BLUE}${BOLD}[?]${RESET} Install Lutris for additional gaming platform? [Y/n]: " lutris_choice
        lutris_choice="${lutris_choice,,}"
        if [[ "$lutris_choice" =~ ^(yes|y| ) ]] || [[ -z "$lutris_choice" ]]; then
            sudo pacman -S --noconfirm lutris || {
                print_message warning "Failed to install Lutris"
            }
        fi

        read -p "${BLUE}${BOLD}[?]${RESET} Install linux-zen kernel for optimized gaming performance? [Y/n]: " kernel_choice
        kernel_choice="${kernel_choice,,}"
        if [[ "$kernel_choice" =~ ^(yes|y| ) ]] || [[ -z "$proton_choice" ]]; then
            sudo pacman -S --noconfirm linux-zen linux-zen-headers || {
                print_message warning "Failed to install linux-zen"
            }
            print_message info "If linux-zen was installed, update GRUB with 'sudo grub-mkconfig -o /boot/grub/grub.cfg' to use the new kernel."
        fi
    fi

    # Enable Steam udev rules (for controller support)
    if [ -f /usr/lib/udev/rules.d/70-steam-input.rules ]; then
        print_message info "Enabling Steam udev rules for controller support..."
        sudo udevadm control --reload-rules && sudo udevadm trigger || {
            print_message warning "Failed to reload udev rules for Steam"
        }
    fi

    # Enable gamemode service (optional, for user to decide)
    print_message info "Gamemode is installed. Enable it manually with 'systemctl --user enable gamemoded' if desired."

    # Inform about Steam Play
    print_message info "To enable Windows games on Steam, go to Steam Settings > Steam Play and enable 'Enable Steam Play for all titles'."

    # Verify Vulkan installation
    if command -v vulkaninfo >/dev/null 2>&1; then
        vulkaninfo --summary >/dev/null 2>&1 && print_message success "Vulkan is correctly installed"
    else
        print_message warning "Vulkan is not properly installed. Some games may not work."
    fi

    installed_components["gaming"]="Installed"
    print_message success "Steam and gaming components installed"
}

# Function: Install components
install_components() {
    print_message info "=== Additional Components ==="
    # Define components: name, description, type (pacman/yay/custom), package(s)/function
    local components=(
        "chaotic-aur:Additional AUR repository with precompiled packages:custom:install_chaotic_aur"
        "libreoffice-fresh:Full-featured office suite (Writer, Calc, Impress, etc.):pacman:libreoffice-fresh"
        "libreoffice-sv:Swedish language support and spellcheck for LibreOffice:pacman:hunspell-sv"
        "digikam:Professional photo management and editing software:pacman:digikam"
        "gimp:GIMP image editor with PhotoGIMP customization:pacman:gimp"
        "photogimp:Customizes GIMP to resemble Photoshop (requires GIMP):custom:install_photogimp"
        "gaming:Steam client and gaming optimizations (Vulkan, Gamemode, etc.):custom:install_gaming"
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
        # Split package strings into individual packages
        local all_packages=()
        for pkg_string in "${selected_pacman[@]}"; do
            read -ra pkgs <<< "$pkg_string"
            all_packages+=("${pkgs[@]}")
        done
        if ! sudo pacman -S --noconfirm "${all_packages[@]}"; then
            print_message error "Failed to install pacman components: ${all_packages[*]}"
            exit 1
        fi
        for pkg_string in "${selected_pacman[@]}"; do
            local pkg_name="${pkg_string%% *}"
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
    check_mirrorlist
    check_yay

    # Check if system is up to date
    print_message info "Checking if system is up to date..."
    if ! sudo pacman -Syu --noconfirm; then
        print_message error "Failed to update system. Please run 'pacman -Syu' manually and try again."
        exit 1
    fi
    print_message success "System is up to date"

    install_components
    display_summary
    print_message info "=== Installation Complete ==="
}

main
