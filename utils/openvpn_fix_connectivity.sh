#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

echo -e "${BLUE}=== OpenVPN Connectivity Fix ===${NC}"
echo -e "${YELLOW}This script will fix common OpenVPN connectivity issues${NC}"
echo

# Detect OpenVPN configuration
if [ -f "/etc/openvpn/server.conf" ]; then
    VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
    VPN_PROTO=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}')
    
    echo -e "OpenVPN Configuration:"
    echo -e "  Port: ${CYAN}$VPN_PORT${NC}"
    echo -e "  Protocol: ${CYAN}$VPN_PROTO${NC}"
else
    echo -e "${RED}OpenVPN server configuration not found.${NC}"
    exit 1
fi

# Detect external interface
EXTERNAL_IF=$(ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$EXTERNAL_IF" ]; then
    echo -e "${RED}Could not detect external network interface.${NC}"
    echo -e "Please specify your external interface manually:"
    read -p "External interface name (e.g., eth0): " EXTERNAL_IF
fi

echo -e "External interface: ${CYAN}$EXTERNAL_IF${NC}"

# Step 1: Ensure OpenVPN service is running
echo -e "\n${YELLOW}1. Ensuring OpenVPN service is running...${NC}"
systemctl restart openvpn@server
if systemctl is-active --quiet openvpn@server; then
    echo -e "${GREEN}✓ OpenVPN service is running.${NC}"
else
    echo -e "${RED}✗ Failed to start OpenVPN service.${NC}"
    echo -e "Checking logs for errors:"
    journalctl -u openvpn@server --no-pager -n 20
fi

# Step 2: Fix IP forwarding
echo -e "\n${YELLOW}2. Configuring IP forwarding...${NC}"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl -w net.ipv4.ip_forward=1
echo -e "${GREEN}✓ IP forwarding enabled.${NC}"

# Step 3: Configure firewall for OpenVPN
echo -e "\n${YELLOW}3. Configuring firewall for OpenVPN...${NC}"

# Check if UFW is installed and enabled
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo -e "UFW is active, adding OpenVPN rules..."
    
    # Add OpenVPN port rule
    ufw allow $VPN_PORT/$VPN_PROTO
    
    # Allow VPN traffic routing
    if ! grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
        echo -e "${GREEN}✓ UFW forwarding policy set to ACCEPT.${NC}"
    else
        echo -e "${GREEN}✓ UFW forwarding policy already set to ACCEPT.${NC}"
    fi
    
    # Set up NAT in UFW
    if ! grep -q "net.ipv4.ip_forward=1" /etc/ufw/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/ufw/sysctl.conf
        echo -e "${GREEN}✓ IP forwarding added to UFW sysctl config.${NC}"
    fi
    
    # Add UFW masquerading rules if not present
    if ! grep -q "POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE" /etc/ufw/before.rules; then
        cat << EOF | sed -i "1r /dev/stdin" /etc/ufw/before.rules
# NAT for OpenVPN
*nat
:POSTROUTING ACCEPT [0:0]
# Forward VPN traffic
-A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE
COMMIT
EOF
        echo -e "${GREEN}✓ NAT masquerading added to UFW rules.${NC}"
    fi
    
    # Enable route forwarding in UFW
    ufw route allow in on tun0 out on $EXTERNAL_IF
    
    # Reload UFW
    ufw reload
    echo -e "${GREEN}✓ UFW rules applied and reloaded.${NC}"
else
    # Using iptables directly
    echo -e "UFW not active, using iptables directly..."
    
    # Clear any existing conflicting rules
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i tun0 -o $EXTERNAL_IF -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $EXTERNAL_IF -o tun0 -j ACCEPT 2>/dev/null || true
    
    # Add NAT and forwarding rules
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $EXTERNAL_IF -j MASQUERADE
    iptables -A FORWARD -i tun0 -o $EXTERNAL_IF -j ACCEPT
    iptables -A FORWARD -i $EXTERNAL_IF -o tun0 -j ACCEPT
    
    # Allow OpenVPN port
    iptables -A INPUT -i $EXTERNAL_IF -p $VPN_PROTO --dport $VPN_PORT -j ACCEPT
    
    echo -e "${GREEN}✓ iptables rules applied.${NC}"
    echo -e "${YELLOW}! Remember these rules will be lost on reboot unless you save them.${NC}"
    echo -e "  ${CYAN}To make iptables rules persistent, install: apt install iptables-persistent${NC}"
    echo -e "  ${CYAN}Then save rules with: netfilter-persistent save${NC}"
fi

# Step 4: Fix permissions and check OpenVPN config
echo -e "\n${YELLOW}4. Checking OpenVPN configuration...${NC}"

# Fix common configuration issues
if [ -f "/etc/openvpn/server.conf" ]; then
    # Ensure client-to-client is enabled for router access
    if ! grep -q "^client-to-client" /etc/openvpn/server.conf; then
        echo "client-to-client" >> /etc/openvpn/server.conf
        echo -e "${GREEN}✓ Enabled client-to-client communication.${NC}"
    fi
    
    # Ensure push redirect-gateway is present
    if ! grep -q "push \"redirect-gateway def1" /etc/openvpn/server.conf; then
        echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf
        echo -e "${GREEN}✓ Added redirect-gateway directive.${NC}"
    fi
    
    # Add explicit push route for the VPN subnet if needed
    if ! grep -q "push \"route 10.8.0.0" /etc/openvpn/server.conf; then
        echo 'push "route 10.8.0.0 255.255.255.0"' >> /etc/openvpn/server.conf
        echo -e "${GREEN}✓ Added explicit route for VPN subnet.${NC}"
    fi
    
    # Verify permissions
    chmod 600 /etc/openvpn/server.key
    echo -e "${GREEN}✓ Server key permissions set properly.${NC}"
fi

# Step 5: Restart OpenVPN service to apply all changes
echo -e "\n${YELLOW}5. Applying changes by restarting OpenVPN...${NC}"
systemctl restart openvpn@server
sleep 3
if systemctl is-active --quiet openvpn@server; then
    echo -e "${GREEN}✓ OpenVPN service restarted successfully.${NC}"
else
    echo -e "${RED}✗ Failed to restart OpenVPN service. Check logs:${NC}"
    journalctl -u openvpn@server --no-pager -n 20
fi

# Step 6: Verify the VPN is listening on expected port
echo -e "\n${YELLOW}6. Verifying OpenVPN is listening...${NC}"
if netstat -tuln | grep -q ":$VPN_PORT "; then
    echo -e "${GREEN}✓ OpenVPN is listening on port $VPN_PORT.${NC}"
else
    echo -e "${RED}✗ OpenVPN is NOT listening on port $VPN_PORT.${NC}"
    echo -e "  Check if there's another service using this port:${NC}"
    netstat -tuln | grep -P ":$VPN_PORT\\s"
fi

echo -e "\n${BLUE}=== Fix Complete ===${NC}"
echo -e "${YELLOW}Please try connecting again with your OpenVPN client.${NC}"
echo -e "${YELLOW}If you still have issues, check the client logs for more information.${NC}"
echo

# Show connection instructions
echo -e "${CYAN}Connection Instructions:${NC}"
echo -e "1. Make sure your client configuration (.ovpn file) has the correct server IP"
echo -e "2. Make sure the protocol matches: ${CYAN}$VPN_PROTO${NC}"
echo -e "3. Ensure no firewall is blocking port ${CYAN}$VPN_PORT${NC} on the client side"
echo

# Display important info
CURRENT_IP=$(curl -s https://api.ipify.org 2>/dev/null || wget -qO- https://api.ipify.org 2>/dev/null)
if [ -n "$CURRENT_IP" ]; then
    echo -e "${GREEN}Server's current public IP: ${CYAN}$CURRENT_IP${NC}"
fi

exit 0