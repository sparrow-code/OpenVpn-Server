#!/bin/bash

# Source common utilities
source "$(dirname "$0")/common.sh"

# Display header
show_header "Configure UFW for OpenVPN"

# Check if running as root
check_root

echo "Setting up UFW firewall rules for OpenVPN..."

# Detect OpenVPN configuration
if [ -f "/etc/openvpn/server.conf" ]; then
    VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}' || echo "1194")
    VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}' || echo "udp")
    VPN_SUBNET=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2"/"substr($3,4)}' || echo "10.8.0.0/24")
    
    echo "Detected OpenVPN configuration:"
    echo "- Port: $VPN_PORT"
    echo "- Protocol: $VPN_PROTO"
    echo "- VPN subnet: $VPN_SUBNET"
else
    echo "Warning: OpenVPN server configuration not found."
    VPN_PORT="1194"
    VPN_PROTO="tcp"
    VPN_SUBNET="10.8.0.0/24"
    
    echo "Using default settings:"
    echo "- Port: $VPN_PORT"
    echo "- Protocol: $VPN_PROTO"
    echo "- VPN subnet: $VPN_SUBNET"
fi

# Detect network interfaces
EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
VPN_IF=$(ip addr | grep -E '^[0-9]+: tun' | cut -d: -f2 | tr -d ' ' | head -1 || echo "tun0")

if [ -z "$EXTERNAL_IF" ]; then
    echo "Warning: Could not detect external network interface."
    echo "Please specify your external interface name (e.g., eth0):"
    read EXTERNAL_IF
    if [ -z "$EXTERNAL_IF" ]; then
        echo "No interface specified. Using eth0 as default."
        EXTERNAL_IF="eth0"
    fi
fi

echo "Using interfaces:"
echo "- External interface: $EXTERNAL_IF"
echo "- VPN interface: $VPN_IF"

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "UFW is not installed. Installing now..."
    apt update
    apt install -y ufw
fi

# Steps to configure UFW for OpenVPN
echo "Configuring UFW for OpenVPN..."

# Allow SSH (to prevent lockout)
echo "1. Ensuring SSH access is allowed..."
ufw allow OpenSSH

# Allow OpenVPN port
echo "2. Adding OpenVPN port rule..."
ufw allow $VPN_PORT/$VPN_PROTO

# Enable packet forwarding in UFW
echo "3. Setting UFW forwarding policy to ACCEPT..."
if grep -q "DEFAULT_FORWARD_POLICY=\"DROP\"" /etc/default/ufw; then
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
    echo "✓ UFW forwarding policy updated to ACCEPT"
else
    echo "✓ UFW forwarding policy already set to ACCEPT"
fi

# Enable IP forwarding in UFW's configuration
echo "4. Enabling IP forwarding in UFW configuration..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/ufw/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/ufw/sysctl.conf
    echo "✓ IP forwarding enabled in UFW configuration"
else
    echo "✓ IP forwarding already enabled in UFW configuration"
fi

# Set up NAT masquerading in UFW
echo "5. Setting up NAT masquerading for VPN traffic..."
if ! grep -q "POSTROUTING -s $VPN_SUBNET" /etc/ufw/before.rules; then
    # Extract the VPN subnet without CIDR
    VPN_SUBNET_BASE=$(echo $VPN_SUBNET | cut -d'/' -f1)
    
    # Create temp file for insertion
    cat > /tmp/nat_rules.txt << EOF
# NAT table rules for OpenVPN
*nat
:POSTROUTING ACCEPT [0:0]
# Forward VPN traffic to the internet
-A POSTROUTING -s $VPN_SUBNET -o $EXTERNAL_IF -j MASQUERADE
COMMIT

EOF
    
    # Insert at the beginning of before.rules
    sed -i '1r /tmp/nat_rules.txt' /etc/ufw/before.rules
    rm /tmp/nat_rules.txt
    echo "✓ NAT masquerading rules added to UFW configuration"
else
    echo "✓ NAT masquerading already configured in UFW"
fi

# Add routing rules for VPN traffic
echo "6. Adding routing rules for VPN traffic..."
ufw route allow in on $VPN_IF out on $EXTERNAL_IF
ufw route allow in on $EXTERNAL_IF out on $VPN_IF
echo "✓ Added routing rules for VPN traffic"

# Verify and enable UFW
echo "7. Verifying and enabling UFW..."
if ! ufw status | grep -q "Status: active"; then
    echo "===================================================================="
    echo "WARNING: Enabling UFW might disconnect your SSH session if SSH"
    echo "         access is not properly allowed. We've tried to add an SSH rule,"
    echo "         but please verify that SSH access is allowed before proceeding."
    echo "===================================================================="
    read -p "Continue enabling UFW? (y/n): " ENABLE_UFW
    if [[ $ENABLE_UFW =~ ^[Yy]$ ]]; then
        echo "Enabling UFW..."
        ufw --force enable
        echo "✓ UFW enabled"
    else
        echo "UFW not enabled. You can manually enable it later with:"
        echo "sudo ufw enable"
    fi
else
    echo "✓ UFW is already active. Reloading configuration..."
    ufw reload
fi

# Display UFW status
echo -e "\nCurrent UFW status:"
ufw status verbose

echo -e "\nCurrent UFW routes:"
ufw status | grep ROUTE || echo "No UFW routes found"

echo -e "\nSetup complete."
echo "Your OpenVPN server is now configured to use UFW instead of ."
echo "Test your VPN connection to verify everything is working properly."

exit 0
