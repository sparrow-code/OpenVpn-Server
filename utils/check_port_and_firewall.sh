#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OpenVPN Port and Firewall Check ===${NC}"
echo

# Check if OpenVPN is installed
if ! command -v openvpn &> /dev/null; then
    echo -e "${RED}OpenVPN is not installed.${NC}"
    exit 1
fi

# Detect OpenVPN port and protocol from configuration
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

# Check if port is listening
echo -e "\n${YELLOW}Checking if OpenVPN is listening on port $VPN_PORT...${NC}"
if netstat -tuln | grep -q ":$VPN_PORT "; then
    echo -e "${GREEN}✓ OpenVPN is listening on port $VPN_PORT.${NC}"
else
    echo -e "${RED}✗ OpenVPN is NOT listening on port $VPN_PORT.${NC}"
    echo -e "  Check if OpenVPN service is running:"
    echo -e "  ${CYAN}systemctl status openvpn@server${NC}"
fi

# Check UFW status
echo -e "\n${YELLOW}Checking UFW status...${NC}"
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}✓ UFW is active.${NC}"
        
        # Check for OpenVPN port rule
        if ufw status | grep -q "$VPN_PORT/$VPN_PROTO"; then
            echo -e "${GREEN}✓ UFW has a rule for port $VPN_PORT/$VPN_PROTO.${NC}"
        else
            echo -e "${RED}✗ No UFW rule found for port $VPN_PORT/$VPN_PROTO.${NC}"
            echo -e "  Add rule with: ${CYAN}sudo ufw allow $VPN_PORT/$VPN_PROTO${NC}"
        fi
    else
        echo -e "${YELLOW}! UFW is not active.${NC}"
    fi
else
    echo -e "${YELLOW}! UFW is not installed.${NC}"
fi

# Check UFW configuration for NAT and forwarding if active
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo -e "\n${YELLOW}Checking UFW NAT and forwarding rules...${NC}"
    if grep -q "POSTROUTING -s 10.8.0.0/24" /etc/ufw/before.rules; then
        echo -e "${GREEN}✓ UFW NAT masquerading is configured.${NC}"
    else
        echo -e "${RED}✗ UFW NAT masquerading is NOT configured.${NC}"
        echo -e "  Run the migration script to configure: ${CYAN}sudo bash $(dirname "$0")/migrate_to_ufw.sh${NC}"
    fi
    if grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw; then
        echo -e "${GREEN}✓ UFW forwarding policy is set to ACCEPT.${NC}"
    else
        echo -e "${RED}✗ UFW forwarding policy is NOT set to ACCEPT.${NC}"
        echo -e "  Update with: ${CYAN}sudo sed -i 's/DEFAULT_FORWARD_POLICY=\"DROP\"/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/g' /etc/default/ufw && sudo ufw reload${NC}"
    fi
else
    echo -e "\n${YELLOW}UFW is not active or installed...${NC}"
    echo -e "${RED}✗ Please install and enable UFW for proper firewall management.${NC}"
    echo -e "  Install with: ${CYAN}sudo apt update && sudo apt install -y ufw${NC}"
    echo -e "  Enable with: ${CYAN}sudo ufw --force enable${NC}"
    echo -e "  Configure for OpenVPN with: ${CYAN}sudo bash $(dirname "$0")/migrate_to_ufw.sh${NC}"
fi

# Test port from inside the server
echo -e "\n${YELLOW}Testing port $VPN_PORT locally...${NC}"
if command -v nc &> /dev/null; then
    if nc -z -v 127.0.0.1 $VPN_PORT 2>&1 | grep -q "succeeded"; then
        echo -e "${GREEN}✓ Port $VPN_PORT is accessible locally.${NC}"
    else
        echo -e "${RED}✗ Port $VPN_PORT is NOT accessible locally.${NC}"
    fi
elif command -v telnet &> /dev/null; then
    echo -e "Use telnet to test locally: ${CYAN}telnet 127.0.0.1 $VPN_PORT${NC}"
else
    echo -e "${YELLOW}! Neither nc nor telnet is installed for local port testing.${NC}"
fi

# Check external IP
echo -e "\n${YELLOW}Verifying external IP address...${NC}"
ACTUAL_IP=$(curl -s https://api.ipify.org 2>/dev/null || wget -qO- https://api.ipify.org 2>/dev/null)
if [ -n "$ACTUAL_IP" ]; then
    echo -e "Your server's public IP: ${CYAN}$ACTUAL_IP${NC}"
    echo -e "IP in client config: ${CYAN}160.191.14.58${NC}"
    
    if [ "$ACTUAL_IP" != "160.191.14.58" ]; then
        echo -e "${RED}✗ IP mismatch! Client configuration has incorrect server IP.${NC}"
        echo -e "  Update the client configuration with the correct IP: ${CYAN}$ACTUAL_IP${NC}"
    else
        echo -e "${GREEN}✓ Client configuration has the correct server IP.${NC}"
    fi
else
    echo -e "${YELLOW}! Could not determine your public IP address.${NC}"
fi

echo -e "\n${BLUE}=== Test Complete ===${NC}"