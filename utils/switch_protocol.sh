#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}OpenVPN Protocol Switch Tool${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "Usage: $0 [tcp|udp]"
    echo -e "Example: $0 tcp  - Switch from UDP to TCP"
    echo -e "Example: $0 udp  - Switch from TCP to UDP"
    echo
    exit 1
}

# Check command line arguments
if [ $# -ne 1 ] || [[ "$1" != "tcp" && "$1" != "udp" ]]; then
    usage
fi

TARGET_PROTOCOL="$1"

if [ "$TARGET_PROTOCOL" == "tcp" ]; then
    CURRENT_PROTOCOL="udp"
    TITLE="OpenVPN Protocol Switch Tool (UDP to TCP)"
    BACKUP_SUFFIX="udp-$(date +%Y%m%d-%H%M%S)"
else
    CURRENT_PROTOCOL="tcp"
    TITLE="OpenVPN Protocol Switch Tool (TCP to UDP)"
    BACKUP_SUFFIX="tcp-$(date +%Y%m%d-%H%M%S)"
fi

# Display header
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}$TITLE${NC}"
echo -e "${BLUE}===============================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Backup original configuration
echo -e "${YELLOW}1. Creating backup of current server configuration...${NC}"
if [ -f /etc/openvpn/server.conf ]; then
    BACKUP_FILE="/etc/openvpn/server.conf.$BACKUP_SUFFIX"
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
echo -e "${YELLOW}3. Select $TARGET_PROTOCOL port:${NC}"
read -p "   Enter $TARGET_PROTOCOL port to use (press enter to keep $CURRENT_PORT): " NEW_PORT
NEW_PORT=${NEW_PORT:-$CURRENT_PORT}

# Update the configuration file
echo -e "${YELLOW}4. Updating server configuration to use $TARGET_PROTOCOL protocol...${NC}"
sed -i "s/^proto $CURRENT_PROTOCOL/proto $TARGET_PROTOCOL/" /etc/openvpn/server.conf
if ! grep -q "^proto $TARGET_PROTOCOL" /etc/openvpn/server.conf; then
    # If the protocol line wasn't updated properly, add it
    sed -i '/^port/i proto '"$TARGET_PROTOCOL" /etc/openvpn/server.conf
fi

# Update port if different
if [ "$NEW_PORT" != "$CURRENT_PORT" ]; then
    sed -i "s/^port .*/port $NEW_PORT/" /etc/openvpn/server.conf
    echo -e "${GREEN}✅ Port updated from $CURRENT_PORT to $NEW_PORT${NC}"
fi

# Handle protocol-specific settings
if [ "$TARGET_PROTOCOL" == "tcp" ]; then
    # Add TCP-specific options if they don't exist
    if ! grep -q "tcp-nodelay" /etc/openvpn/server.conf; then
        echo "# TCP specific settings" >> /etc/openvpn/server.conf
        echo "tcp-nodelay" >> /etc/openvpn/server.conf
        echo -e "${GREEN}✅ Added TCP-specific optimization settings${NC}"
    fi
else # UDP
    # Remove TCP-specific options if they exist
    if grep -q "tcp-nodelay" /etc/openvpn/server.conf; then
        sed -i '/tcp-nodelay/d' /etc/openvpn/server.conf
        echo -e "${GREEN}✅ Removed TCP-specific settings${NC}"
    fi
fi

echo -e "${YELLOW}5. Checking firewall rules...${NC}"
# Check and update firewall if needed
if command -v ufw > /dev/null; then
    if ufw status | grep -q "active"; then
        echo -e "   ${BLUE}UFW firewall detected. Adding $TARGET_PROTOCOL rules...${NC}"
        ufw allow $NEW_PORT/$TARGET_PROTOCOL
        echo -e "${GREEN}✅ UFW rule added for port $NEW_PORT/$TARGET_PROTOCOL${NC}"
    fi
elif command -v firewall-cmd > /dev/null; then
    if firewall-cmd --state | grep -q "running"; then
        echo -e "   ${BLUE}FirewallD detected. Adding $TARGET_PROTOCOL rules...${NC}"
        firewall-cmd --zone=public --add-port=$NEW_PORT/$TARGET_PROTOCOL --permanent
        firewall-cmd --reload
        echo -e "${GREEN}✅ FirewallD rule added for port $NEW_PORT/$TARGET_PROTOCOL${NC}"
    fi
else
    echo -e "   ${BLUE}Checking iptables rules...${NC}"
    if ! iptables -L INPUT -n | grep -q "$TARGET_PROTOCOL dpt:$NEW_PORT"; then
        iptables -A INPUT -p $TARGET_PROTOCOL --dport $NEW_PORT -j ACCEPT
        echo -e "${GREEN}✅ iptables rule added for port $NEW_PORT/$TARGET_PROTOCOL${NC}"
        echo -e "   ${YELLOW}⚠️ Note: This iptables rule will not persist after reboot without saving${NC}"
        echo -e "      ${YELLOW}Consider installing iptables-persistent or similar package.${NC}"
    fi
fi

echo -e "${YELLOW}6. Restarting OpenVPN service...${NC}"
systemctl restart openvpn@server || systemctl restart openvpn
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ OpenVPN service restarted successfully.${NC}"
else
    echo -e "${RED}❌ Failed to restart OpenVPN service. Check with: systemctl status openvpn@server${NC}"
    exit 1
fi

echo -e "${YELLOW}7. Verifying OpenVPN is running with new settings...${NC}"
sleep 2
if pgrep -x "openvpn" > /dev/null; then
    RUNNING_PROTO=$(ss -tulpn | grep -i "openvpn" | grep -i "$NEW_PORT" | grep -i "$TARGET_PROTOCOL")
    if [ -n "$RUNNING_PROTO" ]; then
        echo -e "${GREEN}✅ OpenVPN is running with $TARGET_PROTOCOL protocol on port $NEW_PORT${NC}"
    else
        echo -e "${YELLOW}⚠️ OpenVPN is running but couldn't verify the protocol and port.${NC}"
        echo -e "   Current listening ports:"
        ss -tulpn | grep -i "openvpn"
    fi
else
    echo -e "${RED}❌ OpenVPN service is not running. Check logs with: journalctl -u openvpn@server${NC}"
    exit 1
fi

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Protocol switch to $TARGET_PROTOCOL completed successfully!${NC}"
echo -e "${GREEN}If you experience any issues, restore the backup:${NC}"
echo -e "${CYAN}cp $BACKUP_FILE /etc/openvpn/server.conf${NC}"
echo -e "${CYAN}systemctl restart openvpn@server${NC}"
echo -e "${GREEN}================================================${NC}"
