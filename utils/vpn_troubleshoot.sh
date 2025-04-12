#!/bin/bash

# Source common utilities
source "$(dirname "$0")/common.sh"

show_header "OpenVPN Server-Client Connectivity Troubleshooter"

# Check if running as root
check_root

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
    
    # Auto-detect interfaces
    VPN_IF=$(detect_vpn_interface)
    
    if [ -n "$VPN_IF" ]; then
        echo ""
        echo "VPN interface: $VPN_IF"
        echo "VPN server address: $(ip addr show dev $VPN_IF 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
    else
        error "Could not detect VPN interface. Is OpenVPN running?"
    fi
    exit 1
fi

CLIENT_IP=$1
echo "Testing connectivity to VPN client: $CLIENT_IP"
echo "----------------------------------------------"

# Auto-detect interfaces
EXTERNAL_IF=$(detect_external_interface)
VPN_IF=$(detect_vpn_interface)

if [ -z "$VPN_IF" ]; then
    failure "Could not detect VPN interface. Is OpenVPN running?"
    exit 1
fi

# Check 1: Is the VPN interface up?
echo "1. Checking VPN interface..."
if ip link show $VPN_IF | grep -q "UP"; then
    success "VPN interface $VPN_IF is UP"
else
    failure "VPN interface $VPN_IF is DOWN"
    echo "   Try restarting OpenVPN: sudo systemctl restart openvpn@server"
    exit 1
fi

# Check 2: Does the routing table have a route to the client?
echo "2. Checking routes to client..."
if ip route | grep -q "$CLIENT_IP"; then
    success "Route to client exists: $(ip route | grep "$CLIENT_IP")"
else
    info "No specific route to client found"
    echo "   Checking general VPN subnet routes..."
    
    # Get VPN subnet from server.conf
    if [ -f /etc/openvpn/server.conf ]; then
        VPN_SUBNET=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2"/"substr($3,4)}')
        if ip route | grep -q "$VPN_SUBNET"; then
            success "VPN subnet route exists: $(ip route | grep "$VPN_SUBNET")"
        else
            failure "No route to VPN subnet found"
            echo "   Adding route to VPN subnet..."
            ip route add $VPN_SUBNET dev $VPN_IF
            echo "   Route added: $VPN_SUBNET via $VPN_IF"
        fi
    else
        failure "Cannot find OpenVPN server configuration"
    fi
fi

# Check 3: Is client-to-client communication enabled?
echo "3. Checking client-to-client communication..."
if [ -f /etc/openvpn/server.conf ] && grep -q "^client-to-client" /etc/openvpn/server.conf; then
    success "client-to-client communication is enabled"
else
    info "client-to-client communication directive not found in server.conf"
    echo "   This is fine for server-to-client pings, but clients cannot ping each other"
fi

# Check 4: Basic connectivity test
echo "4. Testing basic connectivity to client..."
if ping -c 4 -W 2 $CLIENT_IP > /dev/null 2>&1; then
    success "Ping to client successful"
else
    failure "Cannot ping client"
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
        success "Client with IP $CLIENT_IP is connected according to status log"
        CLIENT_NAME=$(grep $CLIENT_IP /etc/openvpn/openvpn-status.log | awk '{print $2}')
        CLIENT_REAL_IP=$(grep $CLIENT_IP /etc/openvpn/openvpn-status.log | awk '{print $3}')
        echo "   Client name: $CLIENT_NAME"
        echo "   Client real IP: $CLIENT_REAL_IP"
    else
        failure "Client with IP $CLIENT_IP is not found in status log"
        echo "   The client might not be connected to the VPN"
    fi
else
    warning "Cannot find OpenVPN status log"
fi

# Check 6: Firewall rules
echo "6. Checking firewall rules..."
if iptables -C INPUT -i $VPN_IF -j ACCEPT &>/dev/null; then
    success "Firewall allows incoming traffic from VPN interface"
else
    failure "Firewall might be blocking incoming VPN traffic"
    echo "   Run: sudo iptables -A INPUT -i $VPN_IF -j ACCEPT"
fi

# Fix suggestions
echo ""
echo "==============================================="
echo "Suggested fixes:"
echo "-----------------------------------------------"

# Create a fix script
FIX_SCRIPT="/tmp/vpn_client_connectivity_fix.sh"
create_fix_script "$FIX_SCRIPT" "fix VPN client connectivity issues"

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
