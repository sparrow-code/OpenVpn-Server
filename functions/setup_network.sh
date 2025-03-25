#!/bin/bash

# Function to set up network configuration
setup_network() {
    echo "Enabling IP forwarding..."
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

# Function with check for existing configuration
setup_network_with_check() {
    echo
    echo "Step 5: Network Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step enables IP forwarding for VPN traffic."
    echo "✓ This only needs to be done once per server."
    echo "✓ If you've already configured networking before, you can skip this step."

    if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "✓ IP forwarding appears to be already enabled."
        if confirm_action "Do you want to ensure IP forwarding is properly set up?"; then
            setup_network
        else
            echo "Skipping network configuration."
        fi
    else
        if confirm_action "Do you want to set up network forwarding?"; then
            setup_network
        else
            echo "Skipping network setup. Note that clients may not be able to access the internet through the VPN."
        fi
    fi
}
