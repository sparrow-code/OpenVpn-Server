#!/bin/bash

# Show header
echo "==============================================="
echo "      Configure UFW for OpenVPN (No iptables)"
echo "==============================================="

# Detect external interface
EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -n1)
if [ -z "$EXTERNAL_IF" ]; then
    echo "Could not detect external network interface."
    read -p "Enter your external interface (e.g., eth0): " EXTERNAL_IF
fi
echo "External interface: $EXTERNAL_IF"

# Detect VPN interface
VPN_IF=$(ip -o link show | grep -oP '(?<=: )(tun[0-9]+|tap[0-9]+)' | head -n1)
if [ -z "$VPN_IF" ]; then
    VPN_IF="tun0"
    echo "VPN interface not detected. Using $VPN_IF as default."
else
    echo "Detected VPN interface: $VPN_IF"
fi

# Detect OpenVPN port/protocol
if [ -f "/etc/openvpn/server.conf" ]; then
    VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
    VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}')
else
    read -p "Enter OpenVPN port [default 1194]: " VPN_PORT
    VPN_PORT=${VPN_PORT:-1194}
    read -p "Enter OpenVPN protocol (udp/tcp) [default udp]: " VPN_PROTO
    VPN_PROTO=${VPN_PROTO:-udp}
fi

echo "OpenVPN port: $VPN_PORT/$VPN_PROTO"

# Detect SSH port
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi
echo "Detected SSH port: $SSH_PORT"

# Ensure UFW is installed and enabled
if ! command -v ufw &>/dev/null; then
    echo "UFW is not installed. Installing..."
    apt update && apt install -y ufw
fi

echo "Enabling UFW..."
ufw --force enable

# Always allow SSH port
echo "Allowing SSH port $SSH_PORT..."
ufw allow $SSH_PORT/tcp

# Allow OpenVPN port
echo "Allowing OpenVPN port $VPN_PORT/$VPN_PROTO..."
ufw allow $VPN_PORT/$VPN_PROTO

# Set UFW forwarding policy to ACCEPT
echo "Setting UFW forwarding policy to ACCEPT..."
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw

# Add NAT masquerading to /etc/ufw/before.rules if not present
if ! grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
    echo "Adding NAT masquerading to /etc/ufw/before.rules..."
    sed -i '1i # NAT for OpenVPN\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/24 -o '"$EXTERNAL_IF"' -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
fi

# Allow VPN routing
echo "Allowing VPN routing..."
ufw route allow in on $VPN_IF out on $EXTERNAL_IF

# Reload UFW to apply changes
echo "Reloading UFW..."
ufw reload

echo "==============================================="
echo "UFW is now configured for OpenVPN."
echo "SSH access is allowed on port $SSH_PORT."
echo "OpenVPN access is allowed on port $VPN_PORT/$VPN_PROTO."
echo "NAT and forwarding are enabled."
echo "==============================================="
