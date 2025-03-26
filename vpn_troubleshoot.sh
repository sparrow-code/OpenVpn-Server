#!/bin/bash

echo "==============================================="
echo "OpenVPN Server-Client Connectivity Troubleshooter"
echo "==============================================="

# Function to detect the primary external interface
detect_external_interface() {
    ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -n1
}

# Function to detect VPN interface
detect_vpn_interface() {
    VPN_IF=$(ip -o link show | grep -oP '(?<=\d: )(tun\d+)|(tap\d+)' | head -n 1)
    echo "$VPN_IF"
}

# Auto-detect interfaces
EXTERNAL_IF=$(detect_external_interface)
VPN_IF=$(detect_vpn_interface)

if [ -z "$VPN_IF" ]; then
    echo "❌ Could not detect VPN interface. Is OpenVPN running?"
    exit 1
fi

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <client_vpn_ip>"
    echo "Example: $0 10.8.0.6"
    echo ""
    echo "Current VPN clients:"
    
    if [ -f /etc/openvpn/openvpn-status.log ]; then
        echo "Connected clients from status log:"
        grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | awk '{print "- " $2 " (" $3 ")" }'
    fi
    
    echo ""
    echo "VPN interface: $VPN_IF"
    echo "VPN server address: $(ip addr show dev $VPN_IF | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
    exit 1
fi

CLIENT_IP=$1
echo "Testing connectivity to VPN client: $CLIENT_IP"
echo "----------------------------------------------"

# Check 1: Is the VPN interface up?
echo "1. Checking VPN interface..."
if ip link show $VPN_IF | grep -q "UP"; then
    echo "✅ VPN interface $VPN_IF is UP"
else
    echo "❌ VPN interface $VPN_IF is DOWN"
    echo "   Try restarting OpenVPN: sudo systemctl restart openvpn@server"
    exit 1
fi

# Check 2: Does the routing table have a route to the client?
echo "2. Checking routes to client..."
if ip route | grep -q "$CLIENT_IP"; then
    echo "✅ Route to client exists: $(ip route | grep "$CLIENT_IP")"
else
    echo "⚠️ No specific route to client found"
    echo "   Checking general VPN subnet routes..."
    
    # Get VPN subnet from server.conf
    if [ -f /etc/openvpn/server.conf ]; then
        VPN_SUBNET=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2"/"substr($3,4)}')
        if ip route | grep -q "$VPN_SUBNET"; then
            echo "✅ VPN subnet route exists: $(ip route | grep "$VPN_SUBNET")"
        else
            echo "❌ No route to VPN subnet found"
            echo "   Adding route to VPN subnet..."
            ip route add $VPN_SUBNET dev $VPN_IF
            echo "   Route added: $VPN_SUBNET via $VPN_IF"
        fi
    else
        echo "❌ Cannot find OpenVPN server configuration"
    fi
fi

# Check 3: Is client-to-client communication enabled?
echo "3. Checking client-to-client communication..."
if [ -f /etc/openvpn/server.conf ] && grep -q "^client-to-client" /etc/openvpn/server.conf; then
    echo "✅ client-to-client communication is enabled"
else
    echo "⚠️ client-to-client communication directive not found in server.conf"
    echo "   This is fine for server-to-client pings, but clients cannot ping each other"
fi

# Check 4: Basic connectivity test
echo "4. Testing basic connectivity to client..."
if ping -c 4 -W 2 $CLIENT_IP > /dev/null 2>&1; then
    echo "✅ Ping to client successful"
else
    echo "❌ Cannot ping client"
    echo "   Possible causes:"
    echo "   1. Client firewall is blocking ICMP packets"
    echo "   2. Client is not properly connected to VPN"
    echo "   3. Routing issues between server and client"
    
    # Further diagnostics
    # Try traceroute if available
    if command -v traceroute > /dev/null; then
        echo ""
        echo "Traceroute to client:"
        traceroute -n -w 1 -m 5 $CLIENT_IP
    fi
fi

# Check 5: Is the client actually connected?
echo "5. Checking if client is connected..."
if [ -f /etc/openvpn/openvpn-status.log ]; then
    if grep -q $CLIENT_IP /etc/openvpn/openvpn-status.log; then
        echo "✅ Client with IP $CLIENT_IP is connected according to status log"
        CLIENT_NAME=$(grep $CLIENT_IP /etc/openvpn/openvpn-status.log | awk '{print $2}')
        CLIENT_REAL_IP=$(grep $CLIENT_IP /etc/openvpn/openvpn-status.log | awk '{print $3}')
        echo "   Client name: $CLIENT_NAME"
        echo "   Client real IP: $CLIENT_REAL_IP"
    else
        echo "❌ Client with IP $CLIENT_IP is not found in status log"
        echo "   The client might not be connected to the VPN"
    fi
else
    echo "⚠️ Cannot find OpenVPN status log"
fi

# Check 6: Firewall rules
echo "6. Checking firewall rules..."
if iptables -C INPUT -i $VPN_IF -j ACCEPT &>/dev/null; then
    echo "✅ Firewall allows incoming traffic from VPN interface"
else
    echo "❌ Firewall might be blocking incoming VPN traffic"
    echo "   Run: sudo iptables -A INPUT -i $VPN_IF -j ACCEPT"
fi

# Fix suggestions
echo ""
echo "==============================================="
echo "Suggested fixes:"
echo "-----------------------------------------------"

# Create a fix script
FIX_SCRIPT="/tmp/vpn_client_connectivity_fix.sh"
echo "#!/bin/bash" > $FIX_SCRIPT
echo "# Auto-generated script to fix VPN client connectivity issues" >> $FIX_SCRIPT

# 1. Add iptables rules if needed
if ! iptables -C INPUT -i $VPN_IF -j ACCEPT &>/dev/null; then
    echo "echo 'Adding firewall rule to allow incoming VPN traffic...'" >> $FIX_SCRIPT
    echo "iptables -A INPUT -i $VPN_IF -j ACCEPT" >> $FIX_SCRIPT
    echo "Added: iptables rule to allow traffic from VPN"
fi

# 2. Add route if needed
if ! ip route | grep -q "$CLIENT_IP"; then
    echo "echo 'Adding direct route to client...'" >> $FIX_SCRIPT
    echo "ip route add $CLIENT_IP dev $VPN_IF" >> $FIX_SCRIPT
    echo "Added: direct route to client"
fi

# 3. Enable client-to-client if needed
if [ -f /etc/openvpn/server.conf ] && ! grep -q "^client-to-client" /etc/openvpn/server.conf; then
    echo "echo 'Enabling client-to-client communication...'" >> $FIX_SCRIPT
    echo "sed -i '/^server/a client-to-client' /etc/openvpn/server.conf" >> $FIX_SCRIPT
    echo "echo 'Restarting OpenVPN to apply changes...'" >> $FIX_SCRIPT
    echo "systemctl restart openvpn@server" >> $FIX_SCRIPT
    echo "Added: client-to-client directive to server.conf"
fi

# Make the fix script executable
chmod +x $FIX_SCRIPT

echo ""
echo "Instructions for client-side:"
echo "1. Check if the client firewall allows incoming ICMP packets (ping)"
echo "2. For Windows clients, try: netsh advfirewall firewall add rule name=\"Allow ICMP\" protocol=icmpv4:8,any dir=in action=allow"
echo "3. For Linux clients, try: sudo iptables -A INPUT -p icmp -j ACCEPT"
echo ""
echo "To apply server-side fixes automatically, run:"
echo "sudo bash $FIX_SCRIPT"
echo "==============================================="

exit 0
