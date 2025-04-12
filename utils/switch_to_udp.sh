#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}OpenVPN Protocol Switch Tool (TCP to UDP)${NC}"
echo -e "${BLUE}===============================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Backup original configuration
echo -e "${YELLOW}1. Creating backup of current server configuration...${NC}"
if [ -f /etc/openvpn/server.conf ]; then
    BACKUP_FILE="/etc/openvpn/server.conf.tcp-$(date +%Y%m%d-%H%M%S)"
    cp /etc/openvpn/server.conf "$BACKUP_FILE"
    echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
else
    echo -e "${RED}❌ ERROR: Server configuration file not found at /etc/openvpn/server.conf${NC}"
    exit 1
fi

# Get current port
CURRENT_PORT=$(grep -E "^port " /etc/openvpn/server.conf | awk '{print $2}')
if [ -z "$CURRENT_PORT" ]; then
    CURRENT_PORT="1194" # Default if not specified
fi

echo -e "${YELLOW}2. Current configuration:${NC}"
echo -e "   Protocol: ${GREEN}$(grep -E "^proto " /etc/openvpn/server.conf | awk '{print $2}')${NC}"
echo -e "   Port: ${GREEN}$CURRENT_PORT${NC}"

# Ask for new port or keep the same
echo -e "${YELLOW}3. Select UDP port:${NC}"
read -p "   Enter UDP port to use (press enter to keep $CURRENT_PORT): " NEW_PORT
NEW_PORT=${NEW_PORT:-$CURRENT_PORT}

# Update the configuration file
echo -e "${YELLOW}4. Updating server configuration to use UDP protocol...${NC}"
sed -i 's/^proto tcp/proto udp/' /etc/openvpn/server.conf
if ! grep -q "^proto udp" /etc/openvpn/server.conf; then
    # If the protocol line wasn't updated properly, add it
    sed -i '/^port/i proto udp' /etc/openvpn/server.conf
fi

# Update port if different
if [ "$NEW_PORT" != "$CURRENT_PORT" ]; then
    sed -i "s/^port .*/port $NEW_PORT/" /etc/openvpn/server.conf
    echo -e "${GREEN}✅ Port updated from $CURRENT_PORT to $NEW_PORT${NC}"
fi

# Remove TCP-specific options if they exist
if grep -q "tcp-nodelay" /etc/openvpn/server.conf; then
    sed -i '/tcp-nodelay/d' /etc/openvpn/server.conf
    echo -e "${GREEN}✅ Removed TCP-specific settings${NC}"
    sed -i '/# TCP specific settings/d' /etc/openvpn/server.conf
    echo "✅ Removed TCP-specific settings"
fi

echo "5. Checking firewall rules..."
# Check and update firewall if needed
if command -v ufw > /dev/null; then
    if ufw status | grep -q "active"; then
        echo "   UFW firewall detected. Adding UDP rules..."
        ufw allow $NEW_PORT/udp
        echo "✅ UFW rule added for port $NEW_PORT/udp"
    fi
elif command -v firewall-cmd > /dev/null; then
    if firewall-cmd --state | grep -q "running"; then
        echo "   FirewallD detected. Adding UDP rules..."
        firewall-cmd --zone=public --add-port=$NEW_PORT/udp --permanent
        firewall-cmd --reload
        echo "✅ FirewallD rule added for port $NEW_PORT/udp"
    fi
else
    echo "   Checking iptables rules..."
    if ! iptables -L INPUT -n | grep -q "udp dpt:$NEW_PORT"; then
        iptables -A INPUT -p udp --dport $NEW_PORT -j ACCEPT
        echo "✅ iptables rule added for port $NEW_PORT/udp"
        echo "   ⚠️ Note: This iptables rule will not persist after reboot without saving"
        echo "      Consider installing iptables-persistent or similar package."
    fi
fi

echo "6. Restarting OpenVPN service..."
systemctl restart openvpn@server || systemctl restart openvpn
if [ $? -eq 0 ]; then
    echo "✅ OpenVPN service restarted successfully."
else
    echo "❌ Failed to restart OpenVPN service. Check with: systemctl status openvpn@server"
    exit 1
fi

echo "7. Verifying OpenVPN is running with new settings..."
sleep 2
if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
    echo "✅ OpenVPN service is running."
    if grep -q "^proto udp" /etc/openvpn/server.conf && netstat -tulpn | grep -q ":$NEW_PORT.*openvpn"; then
        echo "✅ OpenVPN is listening on UDP port $NEW_PORT"
    else
        echo "❌ OpenVPN may not be properly configured for UDP on port $NEW_PORT."
        echo "   Check with: netstat -tulpn | grep openvpn"
    fi
else
    echo "❌ OpenVPN service is not running! Please check logs: journalctl -u openvpn@server"
    echo "   You may need to revert to the backup configuration: $BACKUP_FILE"
fi

echo "==============================================="
echo "Next steps: Update client configurations"
echo "==============================================="
echo "You need to update all client (.ovpn) files to use UDP protocol:"
echo "1. Change 'proto tcp' to 'proto udp'"
echo "2. Make sure the port is set to: $NEW_PORT"
echo ""
echo "To automatically update existing .ovpn files in a directory:"
echo "find /path/to/client/configs -name \"*.ovpn\" -exec sed -i 's/^proto tcp/proto udp/g' {} \;"
echo "find /path/to/client/configs -name \"*.ovpn\" -exec sed -i 's/^port .*/port $NEW_PORT/g' {} \;"
echo ""
echo "If you run the get_vpn.sh script again, new client configs will use UDP."
echo "==============================================="
