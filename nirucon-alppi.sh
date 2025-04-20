#!/bin/bash

# Nirucon-ALPPI: Arch Linux Post-Post Install Script
# Version: 2025-04-21
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

# Function: Validate pacman configuration
validate_pacman_conf() {
    local conf_file="$1"
    print_message info "Validating $conf_file..."
    if sudo pacman -Syy --debug 2>&1 | grep -q "error: config file $conf_file"; then
        print_message error "$conf_file contains syntax errors"
        return 1
    fi
    print_message success "$conf_file is syntactically correct"
    return 0
}

# Function: Enable multilib repository
enable_multilib() {
    print_message info "Checking if [multilib] is enabled..."
    if grep -q '^\[multilib\]' /etc/pacman.conf && grep -q '^Include = /etc/pacman.d/mirrorlist' /etc/pacman.conf -A 1; then
        print_message success "[multilib] is already enabled"
        return 0
    fi

    print_message info "Enabling [multilib] repository..."
    # Create a backup
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak || {
        print_message error "Failed to backup /etc/pacman.conf"
        exit 1
    }
    print_message info "Backup created: /etc/pacman.conf.bak"

    # Check if [multilib] is commented out
    if grep -q '^#\[multilib\]' /etc/pacman.conf; then
        print_message info "Uncommenting [multilib] section..."
        sudo sed -i '/^#\[multilib\]/s/^#//; /^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf || {
            print_message error "Failed to uncomment [multilib] section"
            sudo cp /etc/pacman.conf.bak /etc/pacman.conf
            exit 1
        }
    else
        print_message info "Adding [multilib] section to /etc/pacman.conf..."
        echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null || {
            print_message error "Failed to add [multilib] section"
            sudo cp /etc/pacman.conf.bak /etc/pacman.conf
            exit 1
        }
    fi

    # Validate the new configuration
    if ! validate_pacman_conf /etc/pacman.conf; then
        print_message error "New /etc/pacman.conf is invalid. Restoring backup..."
        sudo cp /etc/pacman.conf.bak /etc/pacman.conf
        exit 1
    }

    # Sync repositories
    sudo pacman -Syy || {
        print_message error "Failed to sync repositories after enabling [multilib]"
        sudo cp /etc/pacman.conf.bak /etc/pacman.conf
        exit 1
    }
    print_message success "[multilib] repository enabled"
}

# Function: Install and enable Chaotic-AUR
install_chaotic_aur() {
    print_message info "Installing Chaotic-AUR..."
    # Check if [chaotic-aur] is already enabled
    if grep -q '^\[chaotic-aur\]' /etc/pacman.conf && grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' /etc/pacman.conf -A 1; then
        print_message success "[chaotic-aur] is already enabled"
        return 0
    fi

    # Create a backup
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak || {
        print_message error "Failed to backup /etc/pacman.conf"
        exit 1
    }
    print_message info "Backup created: /etc/pacman.conf.bak"

    # Install Chaotic-AUR keyring and mirrorlist
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || {
        print_message error "Failed to receive Chaotic-AUR key"
        exit 1
    }
    sudo pacman-key --lsign-key 3056513887B78AEB || {
        print_message error "Failed to sign Chaotic-AUR key"
        exit 1
    }
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || {
        print_message error "Failed to install Chaotic-AUR packages"
        exit 1
    }

    # Validate /etc/pacman.d/chaotic-mirrorlist
    if [ ! -f /etc/pacman.d/chaotic-mirrorlist ] || [ ! -s /etc/pacman.d/chaotic-mirrorlist ] || grep -q '^\[.*\]' /etc/pacman.d/chaotic-mirrorlist; then
        print_message warning "Invalid or empty /etc/pacman.d/chaotic-mirrorlist. Writing fallback..."
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

    # Add [chaotic-aur] to /etc/pacman.conf
    print_message info "Adding [chaotic-aur] section to /etc/pacman.conf..."
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null || {
        print_message error "Failed to add [chaotic-aur] section"
        sudo cp /etc/pacman.conf.bak /etc/pacman.conf
        exit 1
    }

    # Validate the new configuration
    if ! validate_pacman_conf /etc/pacman.conf; then
        print_message error "New /etc/pacman.conf is invalid. Restoring backup..."
        sudo cp /etc/pacman.conf.bak /etc/pacman.conf
        exit 1
    }

    # Sync repositories
    sudo pacman -Syy || {
        print_message error "Failed to sync Chaotic-AUR"
        sudo cp /etc/pacman.conf.bak /etc/pacman.conf
        exit 1
    }
    installed_components["chaotic-aur"]="Installed"
    print_message success "Chaotic-AUR installed and enabled"
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
    pacman_conf_files=$(sudo pacman -Syy --debug 2>&1 | grep "loading.*conf" | awk '{print $NF}' | sort -u)
    if [ -n "$pacman_conf_files" ]; then
        print_message info "Pacman is loading the following configuration files:"
        while read -r file; do
            print_message info "  - $file"
            if [ -f "$file" ]; then
                print_message info "Content of $file:"
                cat "$file" | while read -r line; do
                    print_message info "    $line"
                done
            else
                print_message warning "File $file does not exist"
            fi
        done <<< "$pacman_conf_files"
    else
        print_message warning "No configuration files detected by pacman --debug"
    fi

    # Check /etc/pacman.conf for invalid Server directives in [options]
    if grep -q '^\[options\]' /etc/pacman.conf && grep -A 10 '^\[options\]' /etc/pacman.conf | grep -q '^Server'; then
        print_message warning "Found invalid 'Server' directive in [options] section of /etc/pacman.conf. Fixing..."
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

    # Check for [options] or Server in other pacman.d files
    local invalid_files
    invalid_files=$(find /etc/pacman.d/ -type f -exec grep -l -E "^\[options\]|^Server" {} \;)
    if [ -n "$invalid_files" ]; then
        print_message warning "Found [options] or Server directives in the following files: $invalid_files"
        while read -r file; do
            print_message warning "Content of $file:"
            cat "$file" | while read -r line; do
                print_message warning "  $line"
            done
            if [[ "$file" != "/etc/pacman.d/mirrorlist" && "$file" != "/etc/pacman.d/chaotic-mirrorlist" ]]; then
                print_message info "Backing up and commenting out [options] or Server in $file..."
                sudo cp "$file" "$file.bak" || {
                    print_message error "Failed to backup $file"
                }
                sudo sed -i '/^\[options\]/,/^$/s/^Server/#Server/' "$file" || {
                    print_message error "Failed to comment out Server directives in $file"
                }
            fi
        done <<< "$invalid_files"
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
    sudo pacman -Syy || {
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
    echo -e "${YELLOW}Version:${RESET} 2025-04-21 | ${YELLOW}Author:${RESET} Nicklas Rudolfsson | ${YELLOW}GitHub:${RESET} https://github.com/nirucon/nirucon-alppi"
    echo -e "${BLUE}${BOLD}------------------------------------------------------------${RESET}"
}

# Function: Install components
install_components() {
    print_message info "=== Additional Components ==="
    local components=(
        "chaotic-aur:Additional AUR repository with precompiled packages:custom:install_chaotic_aur"
        "gaming:Steam client and gaming optimizations (Vulkan, Gamemode, etc.):custom:install_gaming"
    )
    local selected_custom=()

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
        if [[ "$type" == "custom" && -n "${installed_components[$name]}" ]]; then
            print_message info "$name already processed"; continue
        fi

        read -p "${BLUE}${BOLD}[?]${RESET} Install $name ($desc)? [Y/n]: " comp_choice
        comp_choice="${comp_choice,,}"
        if [[ "$comp_choice" =~ ^(yes|y| ) ]] || [[ -z "$comp_choice" ]]; then
            selected_custom+=("$name:$pkg_or_func")
        fi
    done

    if [[ ${#selected_custom[@]} -eq 0 ]]; then
        print_message warning "No components selected"
        installed_components["components"]="None selected"
        return
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

# Function: Install Steam and gaming-related components
install_gaming() {
    print_message info "Installing Steam and gaming components..."

    # Enable multilib if needed
    enable_multilib

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
    fi

    # Verify Vulkan installation
    if command -v vulkaninfo >/dev/null 2>&1; then
        vulkaninfo --summary >/dev/null 2>&1 && print_message success "Vulkan is correctly installed"
    else
        print_message warning "Vulkan is not properly installed. Some games may not work."
    fi

    installed_components["gaming"]="Installed"
    print_message success "Steam and gaming components installed"
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

# Function: Main
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
