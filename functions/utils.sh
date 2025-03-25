#!/bin/bash

# Function to handle yes/no confirmations
confirm_action() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$prompt (y/n): " response
        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) echo "Please answer with y or n." ;;
        esac
    done
}

# Function to check for existing OpenVPN installation
check_existing_installation() {
    if systemctl is-active --quiet openvpn@server; then
        echo "⚠️ OpenVPN server is already running on this system."
        echo "Running this script might interfere with your existing configuration."
        if ! confirm_action "Do you want to continue anyway?"; then
            echo "Exiting script. Your current configuration remains unchanged."
            exit 0
        fi
    fi
}
