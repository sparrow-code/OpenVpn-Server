#!/bin/bash

# Function to set up network configuration
setup_network() {
    echo "Enabling IP forwarding..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        echo "Installing UFW (Uncomplicated Firewall)..."
        apt update
        apt install -y ufw
    fi

    # Configure UFW for OpenVPN
    echo "Configuring UFW for OpenVPN..."
    
    # Get OpenVPN port and protocol from server.conf
    VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}' || echo "1194")
    VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}' || echo "udp")
    
    # Allow SSH to prevent lockout
    ufw allow OpenSSH
    
    # Allow OpenVPN port
    ufw allow $VPN_PORT/$VPN_PROTO
    
    # Enable packet forwarding in UFW
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw

    # Enable IP forwarding in UFW's configuration
    if ! grep -q "net.ipv4.ip_forward=1" /etc/ufw/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/ufw/sysctl.conf
    fi

    # Detect external interface
    EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [ -z "$EXTERNAL_IF" ]; then
        echo "Warning: Could not detect external network interface."
        echo "Please enter your external interface name (e.g., eth0):"
        read EXTERNAL_IF
        if [ -z "$EXTERNAL_IF" ]; then
            echo "No interface specified. Using eth0 as default."
            EXTERNAL_IF="eth0"
        fi
    fi
    
    # Set up NAT masquerading in UFW
    if ! grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
        cat << EOF | sed -i '1r /dev/stdin' /etc/ufw/before.rules
# NAT table rules for OpenVPN
*nat
:POSTROUTING ACCEPT [0:0]
# Forward traffic from VPN through $EXTERNAL_IF
-A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE
COMMIT

EOF
    fi
    
    # Allow traffic forwarding between tun0 and external interface
    ufw route allow in on tun0 out on $EXTERNAL_IF
    ufw route allow in on $EXTERNAL_IF out on tun0
    
    # Enable the firewall if it's not already enabled
    if ! ufw status | grep -q "Status: active"; then
        echo "Enabling UFW firewall. This might disconnect you if SSH rules aren't configured properly."
        echo "Make sure SSH access is allowed before proceeding!"
        read -p "Continue enabling UFW? (y/n): " ENABLE_UFW
        if [[ $ENABLE_UFW =~ ^[Yy]$ ]]; then
            ufw --force enable
        else
            echo "UFW not enabled. You can manually enable it later with 'sudo ufw enable'."
            echo "Make sure to allow SSH first with 'sudo ufw allow OpenSSH'."
        fi
    else
        echo "UFW is already active. Reloading configuration..."
        ufw reload
    fi
    
    echo "Network configuration completed."
    echo "UFW status:"
    ufw status
}

# Function with check for existing configuration
setup_network_with_check() {
    echo
    echo "Step 5: Network Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step enables IP forwarding and configures UFW firewall for VPN traffic."
    echo "✓ This only needs to be done once per server."
    echo "✓ If you've already configured networking before, you can skip this step."

    if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "✓ IP forwarding appears to be already enabled."
        if confirm_action "Do you want to ensure IP forwarding and UFW are properly set up?"; then
            setup_network
        else
            echo "Skipping network configuration."
        fi
    else
        if confirm_action "Do you want to set up network forwarding with UFW?"; then
            setup_network
        else
            echo "Skipping network setup. Note that clients may not be able to access the internet through the VPN."
        fi
    fi
}
