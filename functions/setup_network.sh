#!/bin/bash

# Function to set up network configuration
setup_network() {
    echo "Enabling IP forwarding..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p

    # Detect if UFW is active and configure it properly
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        echo "UFW firewall detected and active. Configuring for OpenVPN..."
        
        # Get OpenVPN protocol and port
        VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}' || echo "1194")
        VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}' || echo "udp")
        
        # Allow OpenVPN port
        ufw allow $VPN_PORT/$VPN_PROTO
        
        # Configure UFW for forwarding
        if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
            sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
        fi
        
        # Enable IP forwarding in UFW
        if ! grep -q "net.ipv4.ip_forward=1" /etc/ufw/sysctl.conf; then
            echo "net.ipv4.ip_forward=1" >> /etc/ufw/sysctl.conf
        fi
        
        # Detect external interface
        EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
        
        # Configure NAT masquerading if not already set
        if ! grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
            # Add after the header but before any other rules
            sed -i '1,/*filter/s/^*filter/# NAT for OpenVPN\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0\/24 -o '$EXTERNAL_IF' -j MASQUERADE\nCOMMIT\n\n*filter/' /etc/ufw/before.rules
        fi
        
        # Allow routing from VPN to internet
        ufw route allow in on tun0 out on $EXTERNAL_IF
        
        # Reload UFW
        ufw reload
        
        echo "UFW configured for OpenVPN."
    else
        # Traditional iptables setup for non-UFW systems
        echo "Setting up iptables rules for VPN traffic..."
        
        # Detect external interface
        EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
        
        # Add NAT rule
        iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE
        
        # Allow forwarding
        iptables -A FORWARD -i tun0 -o $EXTERNAL_IF -j ACCEPT
        iptables -A FORWARD -i $EXTERNAL_IF -o tun0 -j ACCEPT
        
        # Save rules (if iptables-persistent is available)
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save
        else
            echo "Warning: iptables-persistent is not installed. Firewall rules will not persist after reboot."
            echo "Install with: apt install iptables-persistent"
        fi
    fi
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
