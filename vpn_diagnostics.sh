#!/bin/bash

echo "==============================================="
echo "Starting VPN server diagnostics..."
echo "==============================================="

# Function to detect the primary external interface
detect_external_interface() {
    # Try to detect the interface with the default route
    DEFAULT_ROUTE_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)')
    
    # If that fails, try to find an interface with a public IP
    if [ -z "$DEFAULT_ROUTE_IF" ]; then
        for iface in $(ip -o link show | grep -v "lo" | awk -F': ' '{print $2}'); do
            # Skip virtual interfaces
            if [[ "$iface" == "tun"* ]] || [[ "$iface" == "tap"* ]] || [[ "$iface" == "docker"* ]] || [[ "$iface" == "br-"* ]] || [[ "$iface" == "veth"* ]]; then
                continue
            fi
            
            # Check if interface has an IP
            IP=$(ip -4 addr show dev "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
            if [ -n "$IP" ]; then
                DEFAULT_ROUTE_IF="$iface"
                break
            fi
        done
    fi
    
    echo "$DEFAULT_ROUTE_IF"
}

# Detect OpenVPN interface
detect_vpn_interface() {
    VPN_IF=$(ip -o link show | grep -oP '(?<=\d: )(tun\d+)|(tap\d+)' | head -n 1)
    echo "$VPN_IF"
}

# Detect external interface
EXTERNAL_IF=$(detect_external_interface)
if [ -z "$EXTERNAL_IF" ]; then
    echo "ERROR: Could not detect external network interface."
    echo "Please specify your external interface manually by editing this script."
    exit 1
fi

# Detect VPN interface
VPN_IF=$(detect_vpn_interface)
if [ -z "$VPN_IF" ]; then
    echo "ERROR: Could not detect VPN interface (tun/tap)."
    echo "Make sure OpenVPN is running and a VPN tunnel is established."
    exit 1
fi

echo "Detected network interfaces:"
echo "- External interface: $EXTERNAL_IF"
echo "- VPN interface: $VPN_IF"
echo "----------------------------------------------"

# 1. Check if OpenVPN service is running
echo "Checking OpenVPN service status..."
if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
    echo "✅ OpenVPN service is running."
else
    echo "❌ OpenVPN service is NOT running."
    echo "   Try starting it with: sudo systemctl start openvpn@server"
    echo "   Or check logs with: sudo journalctl -u openvpn@server"
    exit 1
fi

# 2. Check if IP forwarding is enabled
echo "Checking IP forwarding..."
if [[ $(sysctl net.ipv4.ip_forward | awk '{print $3}') -eq 1 ]]; then
    echo "✅ IP forwarding is enabled."
else
    echo "❌ IP forwarding is NOT enabled."
    echo "   Enable it temporarily with: sudo sysctl -w net.ipv4.ip_forward=1"
    echo "   Enable it permanently by adding 'net.ipv4.ip_forward=1' to /etc/sysctl.conf"
    echo "   and running: sudo sysctl -p"
    exit 1
fi

# 3. Check firewall rules for VPN traffic
echo "Checking firewall rules..."

# Check NAT rule
if iptables -t nat -C POSTROUTING -o $EXTERNAL_IF -j MASQUERADE &>/dev/null; then
    echo "✅ NAT rule for VPN traffic is properly configured."
else
    echo "❌ NAT rule for VPN traffic is missing."
    echo "   Add it using: sudo iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE"
    NAT_MISSING=true
fi

# Check forwarding rules
FORWARD_RULE1_OK=false
FORWARD_RULE2_OK=false

if iptables -C FORWARD -i $VPN_IF -o $EXTERNAL_IF -j ACCEPT &>/dev/null; then
    FORWARD_RULE1_OK=true
fi

if iptables -C FORWARD -i $EXTERNAL_IF -o $VPN_IF -j ACCEPT &>/dev/null; then
    FORWARD_RULE2_OK=true
fi

if $FORWARD_RULE1_OK && $FORWARD_RULE2_OK; then
    echo "✅ Firewall forwarding rules are properly configured."
else
    echo "❌ Some firewall forwarding rules are missing:"
    
    if ! $FORWARD_RULE1_OK; then
        echo "   Missing rule: sudo iptables -A FORWARD -i $VPN_IF -o $EXTERNAL_IF -j ACCEPT"
    fi
    
    if ! $FORWARD_RULE2_OK; then
        echo "   Missing rule: sudo iptables -A FORWARD -i $EXTERNAL_IF -o $VPN_IF -j ACCEPT"
    fi
    
    echo "   These rules are needed to allow traffic forwarding between VPN clients and the internet."
    FIREWALL_MISSING=true
fi

# 4. Check DNS resolution
echo "Checking DNS resolution..."
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "✅ Internet connectivity is working."
else
    echo "❌ Internet connectivity is NOT working."
    echo "   Check your server's internet connection with: ping 8.8.8.8"
    exit 1
fi

if nslookup google.com &>/dev/null; then
    echo "✅ DNS resolution is working."
else
    echo "❌ DNS resolution is NOT working."
    echo "   Check your DNS configuration in /etc/resolv.conf"
    echo "   You might need to add 'push \"dhcp-option DNS 8.8.8.8\"' to your OpenVPN server config"
    exit 1
fi

# 5. Test VPN client connectivity
echo "Checking VPN tunnel..."
VPN_IP=$(ip addr show dev $VPN_IF | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [[ -n "$VPN_IP" ]]; then
    echo "✅ VPN tunnel is up with IP: $VPN_IP"
else
    echo "❌ VPN tunnel is NOT up."
    echo "   Check your OpenVPN configuration in /etc/openvpn/server.conf"
    echo "   Look for errors in log: sudo journalctl -u openvpn@server"
    exit 1
fi

# 6. Test internet access through VPN
echo "Testing internet access through VPN..."
if curl -s --interface $VPN_IF https://ifconfig.me &>/dev/null; then
    echo "✅ Internet access through VPN is working."
else
    echo "❌ Internet access through VPN is NOT working."
    if [[ -n "$NAT_MISSING" || -n "$FIREWALL_MISSING" ]]; then
        echo "   Fix the firewall rules mentioned above and try again."
    else
        echo "   Check that your routing is correctly set up."
        echo "   Verify server.conf includes: push \"redirect-gateway def1 bypass-dhcp\""
    fi
fi

# Summary and recommendations
echo "----------------------------------------------"
if [[ -n "$NAT_MISSING" || -n "$FIREWALL_MISSING" ]]; then
    echo "⚠️ VPN configuration has issues that need to be fixed."
    echo "Please run the following commands to fix the firewall configuration:"
    
    if [[ -n "$NAT_MISSING" ]]; then
        echo "sudo iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE"
    fi
    
    if ! $FORWARD_RULE1_OK; then
        echo "sudo iptables -A FORWARD -i $VPN_IF -o $EXTERNAL_IF -j ACCEPT"
    fi
    
    if ! $FORWARD_RULE2_OK; then
        echo "sudo iptables -A FORWARD -i $EXTERNAL_IF -o $VPN_IF -j ACCEPT"
    fi
    
    echo
    echo "To make these changes permanent, install iptables-persistent:"
    echo "sudo apt install iptables-persistent"
    echo "After adding the rules, save them with: sudo netfilter-persistent save"
else
    echo "✅ All checks passed. VPN server is configured properly!"
fi
echo "==============================================="
