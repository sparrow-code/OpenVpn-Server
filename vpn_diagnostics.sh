#!/bin/bash

echo "Starting VPN server diagnostics..."

# 1. Check if OpenVPN service is running
echo "Checking OpenVPN service status..."
if systemctl is-active --quiet openvpn; then
    echo "OpenVPN service is running."
else
    echo "OpenVPN service is NOT running. Please start it using: systemctl start openvpn"
    exit 1
fi

# 2. Check if IP forwarding is enabled
echo "Checking IP forwarding..."
if [[ $(sysctl net.ipv4.ip_forward | awk '{print $3}') -eq 1 ]]; then
    echo "IP forwarding is enabled."
else
    echo "IP forwarding is NOT enabled. Enable it by running: sysctl -w net.ipv4.ip_forward=1"
    exit 1
fi

# 3. Check firewall rules for VPN traffic
echo "Checking firewall rules..."
if iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE &>/dev/null; then
    echo "NAT rule for VPN traffic is configured."
else
    echo "NAT rule for VPN traffic is missing. Add it using: iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
    exit 1
fi

if iptables -C FORWARD -i tun0 -o eth0 -j ACCEPT &>/dev/null && \
   iptables -C FORWARD -i eth0 -o tun0 -j ACCEPT &>/dev/null; then
    echo "Firewall rules for forwarding VPN traffic are configured."
else
    echo "Firewall rules for forwarding VPN traffic are missing. Add them using:"
    echo "iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT"
    echo "iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT"
    exit 1
fi

# 4. Check DNS resolution
echo "Checking DNS resolution..."
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "Internet connectivity is working."
else
    echo "Internet connectivity is NOT working. Check your server's internet connection."
    exit 1
fi

if nslookup google.com &>/dev/null; then
    echo "DNS resolution is working."
else
    echo "DNS resolution is NOT working. Check your DNS configuration."
    exit 1
fi

# 5. Test VPN client connectivity
echo "Testing VPN client connectivity..."
VPN_IP=$(ifconfig tun0 | grep 'inet ' | awk '{print $2}')
if [[ -n "$VPN_IP" ]]; then
    echo "VPN tunnel is up with IP: $VPN_IP"
else
    echo "VPN tunnel is NOT up. Check your OpenVPN configuration."
    exit 1
fi

# 6. Test internet access through VPN
echo "Testing internet access through VPN..."
if curl -s --interface tun0 https://ifconfig.me &>/dev/null; then
    echo "Internet access through VPN is working."
else
    echo "Internet access through VPN is NOT working. Check your routing and NAT configuration."
    exit 1
fi

echo "All checks passed. VPN server is configured properly."
