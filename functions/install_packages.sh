#!/bin/bash

# Function to install required packages
install_packages() {
    echo "Installing required packages..."
    sudo apt update
    sudo apt install openvpn easy-rsa -y
}

# Function with check for existing installation
install_packages_with_check() {
    echo
    echo "Step 1: Package Installation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step installs OpenVPN and Easy-RSA packages."
    echo "✓ This only needs to be done once per server."
    echo "✓ If you've already installed these packages before, you can skip this step."

    if [ -f /usr/sbin/openvpn ] && [ -d /usr/share/easy-rsa ]; then
        echo "✓ OpenVPN and Easy-RSA appear to be already installed."
        if ! confirm_action "Do you want to reinstall/update packages?"; then
            echo "Skipping package installation."
            return
        fi
    else
        if ! confirm_action "Do you want to install the required packages?"; then
            echo "Skipping package installation. Note that the script may fail if packages are missing."
            return
        fi
    fi
    
    install_packages
}
