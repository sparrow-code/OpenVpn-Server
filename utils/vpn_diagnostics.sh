#!/bin/bash

# Source common utilities
source "$(dirname "$0")/common.sh"

# Display header
show_header "OpenVPN Server Diagnostics"

# Check if running as root
check_root

# Initialize variables to track issues
ISSUES_FOUND=false

# Detect external interface
EXTERNAL_IF=$(detect_external_interface)
if [ -z "$EXTERNAL_IF" ]; then
    error "Could not detect external network interface."
    error "Please specify your external interface manually by editing this script."
    exit 1
fi

# Detect VPN interface
VPN_IF=$(detect_vpn_interface)

if [ -z "$VPN_IF" ]; then
    error "Could not detect VPN interface (tun/tap)."
    error "Make sure OpenVPN is running and a VPN tunnel is established."
    exit 1
fi

echo -e "${BLUE}Detected network interfaces:${NC}"
echo -e "- External interface: ${GREEN}$EXTERNAL_IF${NC}"
echo -e "- VPN interface: ${GREEN}$VPN_IF${NC}"
echo -e "${BLUE}----------------------------------------------${NC}"

# 1. Check if OpenVPN service is running
echo "Checking OpenVPN service status..."
if check_openvpn_running; then
    success "OpenVPN service is running."
else
    failure "OpenVPN service is NOT running."
    echo "   Try starting it with: sudo systemctl start openvpn@server"
    echo "   Or check logs with: sudo journalctl -u openvpn@server"
    ISSUES_FOUND=true
    exit 1
fi

# 2. Check if IP forwarding is enabled
echo "Checking IP forwarding..."
if [[ $(sysctl net.ipv4.ip_forward | awk '{print $3}') -eq 1 ]]; then
    success "IP forwarding is enabled."
else
    failure "IP forwarding is NOT enabled."
    echo "   Enable it temporarily with: sudo sysctl -w net.ipv4.ip_forward=1"
    echo "   Enable it permanently by adding 'net.ipv4.ip_forward=1' to /etc/sysctl.conf"
    echo "   and running: sudo sysctl -p"
    ISSUES_FOUND=true
    exit 1
fi

# 3. Check firewall rules for VPN traffic
echo "Checking firewall rules..."

# Check NAT rule
if iptables -t nat -C POSTROUTING -o $EXTERNAL_IF -j MASQUERADE &>/dev/null; then
    success "NAT rule for VPN traffic is properly configured."
else
    failure "NAT rule for VPN traffic is missing."
    echo "   Add it using: sudo iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE"
    NAT_MISSING=true
    ISSUES_FOUND=true
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
    success "Firewall forwarding rules are properly configured."
else
    failure "Some firewall forwarding rules are missing:"
    
    if ! $FORWARD_RULE1_OK; then
        echo "   Missing rule: sudo iptables -A FORWARD -i $VPN_IF -o $EXTERNAL_IF -j ACCEPT"
    fi
    
    if ! $FORWARD_RULE2_OK; then
        echo "   Missing rule: sudo iptables -A FORWARD -i $EXTERNAL_IF -o $VPN_IF -j ACCEPT"
    fi
    
    echo "   These rules are needed to allow traffic forwarding between VPN clients and the internet."
    FIREWALL_MISSING=true
    ISSUES_FOUND=true
fi

# 4. Check DNS resolution
echo "Checking DNS resolution..."
if ping -c 1 8.8.8.8 &>/dev/null; then
    success "Internet connectivity is working."
else
    failure "Internet connectivity is NOT working."
    echo "   Check your server's internet connection with: ping 8.8.8.8"
    ISSUES_FOUND=true
    exit 1
fi

if nslookup google.com &>/dev/null; then
    success "DNS resolution is working."
else
    failure "DNS resolution is NOT working."
    echo "   Check your DNS configuration in /etc/resolv.conf"
    echo "   You might need to add 'push \"dhcp-option DNS 8.8.8.8\"' to your OpenVPN server config"
    ISSUES_FOUND=true
    exit 1
fi

# 5. Test VPN client connectivity
echo "Checking VPN tunnel..."
VPN_IP=$(ip addr show dev $VPN_IF 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [[ -n "$VPN_IP" ]]; then
    success "VPN tunnel is up with IP: $VPN_IP"
    
    # Check for connected clients
    if [ -f /etc/openvpn/openvpn-status.log ]; then
        CLIENT_COUNT=$(grep -c "^CLIENT_LIST" /etc/openvpn/openvpn-status.log)
        if [ "$CLIENT_COUNT" -gt 0 ]; then
            success "$CLIENT_COUNT clients currently connected"
            echo "   Connected clients:"
            grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | awk '{print "   - " $2 " (" $3 ")" }'
        else
            info "No clients currently connected to the VPN"
        fi
    else
        info "Cannot check client connections (status log not found)"
    fi
else
    failure "VPN tunnel is NOT properly established."
    echo "   Check OpenVPN server configuration and logs"
    ISSUES_FOUND=true
    exit 1
fi

# 6. Test internet access through VPN
echo "Testing internet access through VPN..."
if curl -s --interface $VPN_IF https://ifconfig.me &>/dev/null; then
    success "Internet access through VPN is working."
else
    failure "Internet access through VPN is NOT working."
    if [[ -n "$NAT_MISSING" || -n "$FIREWALL_MISSING" ]]; then
        echo "   Fix the firewall rules mentioned above and try again."
    else
        echo "   Check that your routing is correctly set up."
        echo "   Verify server.conf includes: push \"redirect-gateway def1 bypass-dhcp\""
    fi
fi

# Additional checks for OpenVPN configuration
echo "Checking OpenVPN server configuration..."
if [ -f /etc/openvpn/server.conf ]; then
    success "OpenVPN server configuration file exists"
    
    # Check for essential configuration directives
    CONFIG_ISSUES=()
    
    if ! grep -q "^dev tun" /etc/openvpn/server.conf; then
        CONFIG_ISSUES+=("Missing or incorrect 'dev tun' directive")
    fi
    
    if ! grep -q "^server [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" /etc/openvpn/server.conf; then
        CONFIG_ISSUES+=("Missing or incorrect 'server' directive (VPN subnet)")
    fi
    
    if ! grep -q "redirect-gateway" /etc/openvpn/server.conf; then
        CONFIG_ISSUES+=("Missing 'redirect-gateway' directive - clients may not route all traffic through VPN")
    fi
    
    if ! grep -q "dhcp-option DNS" /etc/openvpn/server.conf; then
        CONFIG_ISSUES+=("Missing DNS configuration - clients may have DNS resolution issues")
    fi
    
    if [ ${#CONFIG_ISSUES[@]} -eq 0 ]; then
        success "Server configuration appears to be valid"
    else
        warn "Some potential issues with server configuration:"
        for issue in "${CONFIG_ISSUES[@]}"; do
            echo -e "   ${YELLOW}- $issue${NC}"
        done
        ISSUES_FOUND=true
    fi
else
    failure "OpenVPN server configuration file not found"
    echo "   Expected location: /etc/openvpn/server.conf"
    ISSUES_FOUND=true
fi

# Check for recent errors in logs
echo -e "${BLUE}Checking OpenVPN logs for errors...${NC}"
if [ -f /var/log/syslog ]; then
    RECENT_ERRORS=$(grep -i "openvpn.*error" /var/log/syslog | tail -n 5)
    if [ -n "$RECENT_ERRORS" ]; then
        warn "Recent errors found in OpenVPN logs:"
        echo "$RECENT_ERRORS" | while read -r line; do
            echo "   $line"
        done
        ISSUES_FOUND=true
    else
        success "No recent errors found in logs"
    fi
else
    info "Cannot check logs (syslog not found)"
fi

# Create auto-fix script if issues were found
if $ISSUES_FOUND || [[ -n "$NAT_MISSING" ]] || [[ -n "$FIREWALL_MISSING" ]]; then
    FIX_SCRIPT="/tmp/fix_vpn_issues.sh"
    create_fix_script "$FIX_SCRIPT" "fix VPN configuration issues"
    
    if [[ $(sysctl net.ipv4.ip_forward | awk '{print $3}') -ne 1 ]]; then
        echo "echo 'Enabling IP forwarding...'" >> $FIX_SCRIPT
        echo "sysctl -w net.ipv4.ip_forward=1" >> $FIX_SCRIPT
        echo "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf" >> $FIX_SCRIPT
        echo "sysctl -p" >> $FIX_SCRIPT
    fi
    
    if [[ -n "$NAT_MISSING" ]]; then
        echo "echo 'Adding NAT rule...'" >> $FIX_SCRIPT
        echo "iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE" >> $FIX_SCRIPT
    fi
    
    if ! $FORWARD_RULE1_OK; then
        echo "echo 'Adding forwarding rule from VPN to internet...'" >> $FIX_SCRIPT
        echo "iptables -A FORWARD -i $VPN_IF -o $EXTERNAL_IF -j ACCEPT" >> $FIX_SCRIPT
    fi
    
    if ! $FORWARD_RULE2_OK; then
        echo "echo 'Adding forwarding rule from internet to VPN...'" >> $FIX_SCRIPT
        echo "iptables -A FORWARD -i $EXTERNAL_IF -o $VPN_IF -j ACCEPT" >> $FIX_SCRIPT
    fi
    
    echo "echo 'To make these iptables rules permanent, run:'" >> $FIX_SCRIPT
    echo "echo 'sudo apt install iptables-persistent && sudo netfilter-persistent save'" >> $FIX_SCRIPT
    echo "echo 'All issues have been fixed!'" >> $FIX_SCRIPT
    
    echo
    echo "📝 An automatic fix script has been created at $FIX_SCRIPT"
    echo "   Run it with: sudo bash $FIX_SCRIPT"
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

exit 0
