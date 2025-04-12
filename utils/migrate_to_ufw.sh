#!/bin/bash

# Source common utilities
source "$(dirname "$0")/common.sh"

# Display header
show_header "Migrate OpenVPN from iptables to UFW"

# Check if running as root
check_root

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW (Uncomplicated Firewall)..."
    apt update
    apt install -y ufw
fi

# Get OpenVPN configuration
echo "Detecting OpenVPN configuration..."
if [ -f "/etc/openvpn/server.conf" ]; then
    VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}' || echo "1194")
    VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}' || echo "udp")
    
    echo "Detected OpenVPN settings:"
    echo "- Port: $VPN_PORT"
    echo "- Protocol: $VPN_PROTO"
else
    echo "Warning: OpenVPN server configuration not found."
    VPN_PORT="1194"
    VPN_PROTO="tcp"
    echo "Using default settings:"
    echo "- Port: $VPN_PORT"
    echo "- Protocol: $VPN_PROTO"
fi

# Detect network interfaces
EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
VPN_IF=$(ip addr | grep -E '^[0-9]+: tun' | cut -d: -f2 | tr -d ' ' | head -1)

if [ -z "$EXTERNAL_IF" ]; then
    echo "Warning: Could not detect external network interface."
    echo "Please enter your external interface name (e.g., eth0):"
    read EXTERNAL_IF
    if [ -z "$EXTERNAL_IF" ]; then
        echo "No interface specified. Using eth0 as default."
        EXTERNAL_IF="eth0"
    fi
fi

if [ -z "$VPN_IF" ]; then
    VPN_IF="tun0"
    echo "VPN interface not detected. Using $VPN_IF as default."
else
    echo "Detected VPN interface: $VPN_IF"
fi

echo "Detected external interface: $EXTERNAL_IF"

# Backup existing iptables rules
echo "Backing up current iptables rules..."
iptables-save > /tmp/iptables-backup-$(date +"%Y%m%d-%H%M%S").rules
echo "Backup saved to /tmp/iptables-backup-*.rules"

# Configure UFW for OpenVPN
echo "Configuring UFW for OpenVPN..."

# First, ensure SSH access to prevent lockout
echo "Ensuring SSH access is allowed..."
ufw allow OpenSSH

# Allow OpenVPN port
echo "Adding OpenVPN port rule..."
ufw allow $VPN_PORT/$VPN_PROTO

# Enable packet forwarding in UFW
echo "Enabling packet forwarding in UFW..."
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw

# Enable IP forwarding in UFW's configuration
if ! grep -q "net.ipv4.ip_forward=1" /etc/ufw/sysctl.conf; then
    echo "Adding IP forwarding to UFW configuration..."
    echo 'net.ipv4.ip_forward=1' >> /etc/ufw/sysctl.conf
fi

# Set up NAT masquerading in UFW
echo "Setting up NAT masquerading..."
if ! grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
    cat << EOF | sed -i '1r /dev/stdin' /etc/ufw/before.rules
# NAT table rules for OpenVPN
*nat
:POSTROUTING ACCEPT [0:0]
# Forward traffic from VPN through $EXTERNAL_IF
-A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE
COMMIT

EOF
    echo "Added NAT masquerading rules to UFW configuration."
else
    echo "NAT masquerading already configured in UFW."
fi

# Allow traffic forwarding between VPN and internet interfaces
echo "Adding routing rules for VPN traffic..."
ufw route allow in on $VPN_IF out on $EXTERNAL_IF
ufw route allow in on $EXTERNAL_IF out on $VPN_IF

# Enable the firewall if it's not already enabled
if ! ufw status | grep -q "Status: active"; then
    echo "========================= WARNING ============================="
    echo "About to enable UFW firewall. This might disconnect your SSH session"
    echo "if you're connected remotely and SSH rules aren't properly configured."
    echo "Make sure that SSH access is allowed (we've tried to add it above)."
    echo "========================= WARNING ============================="
    read -p "Continue enabling UFW? (y/n): " ENABLE_UFW
    if [[ $ENABLE_UFW =~ ^[Yy]$ ]]; then
        echo "Enabling UFW..."
        ufw --force enable
        echo "UFW enabled."
    else
        echo "UFW not enabled. You can manually enable it later with 'sudo ufw enable'."
        echo "Make sure to allow SSH first with 'sudo ufw allow OpenSSH'."
    fi
else
    echo "UFW is already active. Reloading configuration..."
    ufw reload
fi

# Verify UFW configuration
echo "UFW status:"
ufw status verbose

echo "UFW routes:"
ufw status | grep ROUTE

echo "Migration from iptables to UFW completed!"
echo "IP forwarding status:"
sysctl net.ipv4.ip_forward

echo ""
echo "Next steps:"
echo "1. Test your OpenVPN connection to make sure it works with UFW."
echo "2. If everything is working properly, consider clearing old iptables rules."
echo "3. For persistent UFW rules across reboots, ensure ufw service starts on boot:"
echo "   sudo systemctl enable ufw"

exit 0
