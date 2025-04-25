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

# Check if UFW is being used
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo "UFW firewall is active, checking rules..."
    
    # Check if OpenVPN port is allowed
    if ufw status | grep -q "$VPN_PORT/$VPN_PROTO"; then
        success "UFW allows OpenVPN port $VPN_PORT/$VPN_PROTO"
    else
        failure "UFW might be blocking OpenVPN traffic"
        echo "   Run: sudo ufw allow $VPN_PORT/$VPN_PROTO"
        echo "   Add rule to $FIX_SCRIPT"
        echo "ufw allow $VPN_PORT/$VPN_PROTO" >> $FIX_SCRIPT
    fi
    
    # Check for routing rules
    if ufw status | grep -q "tun0"; then
        success "UFW has routing rules for VPN interface"
    else
        failure "UFW might be blocking VPN routing"
        echo "   Run: sudo ufw route allow in on $VPN_IF out on $EXTERNAL_IF"
        echo "ufw route allow in on $VPN_IF out on $EXTERNAL_IF" >> $FIX_SCRIPT
    fi
    
    # Check UFW forwarding policy
    if grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
        success "UFW forwarding policy is set to ACCEPT"
    else
        failure "UFW forwarding policy is not set to ACCEPT"
        echo "echo 'Setting UFW forwarding policy to ACCEPT...'" >> $FIX_SCRIPT
        echo "sed -i 's/DEFAULT_FORWARD_POLICY=\"DROP\"/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/g' /etc/default/ufw" >> $FIX_SCRIPT
    fi
    
    # Check NAT rules in before.rules
    if grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
        success "UFW has NAT masquerading rules for VPN"
    else
        failure "UFW does not have NAT masquerading rules for VPN"
        echo "echo 'Adding NAT rules to UFW...'" >> $FIX_SCRIPT
        echo "cat << EOF | sed -i '1r /dev/stdin' /etc/ufw/before.rules" >> $FIX_SCRIPT
        echo "# NAT for OpenVPN" >> $FIX_SCRIPT
        echo "*nat" >> $FIX_SCRIPT
        echo ":POSTROUTING ACCEPT [0:0]" >> $FIX_SCRIPT
        echo "-A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE" >> $FIX_SCRIPT
        echo "COMMIT" >> $FIX_SCRIPT
        echo "EOF" >> $FIX_SCRIPT
        echo "ufw reload" >> $FIX_SCRIPT
    fi
else
    # UFW not active, suggest enabling it
    failure "UFW is not active. Please enable UFW for proper firewall management with OpenVPN."
    echo "   To enable UFW, run: sudo ufw --force enable"
    echo "   Then configure UFW for OpenVPN using: sudo bash $(dirname "$0")/migrate_to_ufw.sh"
fi

# Fix suggestions
echo ""
echo "==============================================="
echo "Suggested fixes:"
echo "-----------------------------------------------"

# Create a fix script
FIX_SCRIPT="/tmp/vpn_client_connectivity_fix.sh"
create_fix_script "$FIX_SCRIPT" "fix VPN client connectivity issues"

# 1. Suggest UFW configuration if needed
echo "echo 'Please ensure UFW is enabled and configured for OpenVPN.'" >> $FIX_SCRIPT
echo "echo 'Run: sudo ufw --force enable'" >> $FIX_SCRIPT
echo "echo 'Then configure UFW for OpenVPN using: sudo bash $(dirname "$0")/migrate_to_ufw.sh'" >> $FIX_SCRIPT

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
echo "3. For Linux clients, ensure firewall allows ICMP if needed."
echo ""
echo "To apply server-side fixes automatically, run:"
echo "sudo bash $FIX_SCRIPT"
echo "==============================================="

exit 0
