#!/bin/bash

# Source common utilities
source "$(dirname "$0")/common.sh"

# Function to print usage
usage() {
    show_header "OpenVPN Protocol Switch Tool"
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
    TITLE="OpenVPN Protocol Switch Tool (UDP to TCP)"
else
    TITLE="OpenVPN Protocol Switch Tool (TCP to UDP)"
fi

# Display header
show_header "$TITLE"

# Check if running as root
check_root

# Get current port
CURRENT_PORT=$(get_server_config_param "port")
if [ -z "$CURRENT_PORT" ]; then
    CURRENT_PORT="1194" # Default if not specified
fi

echo -e "${YELLOW}1. Current configuration:${NC}"
echo -e "   Protocol: ${GREEN}$(get_server_config_param "proto")${NC}"
echo -e "   Port: ${GREEN}$CURRENT_PORT${NC}"

# Ask for new port or keep the same
echo -e "${YELLOW}2. Select $TARGET_PROTOCOL port:${NC}"
read -p "   Enter $TARGET_PROTOCOL port to use (press enter to keep $CURRENT_PORT): " NEW_PORT
NEW_PORT=${NEW_PORT:-$CURRENT_PORT}

# Update the protocol in the configuration file
echo -e "${YELLOW}3. Updating server configuration to use $TARGET_PROTOCOL protocol...${NC}"
switch_protocol "$TARGET_PROTOCOL" "$CURRENT_PORT" "$NEW_PORT"

echo -e "${YELLOW}4. Checking firewall rules...${NC}"
update_firewall_for_protocol "$TARGET_PROTOCOL" "$NEW_PORT"

echo -e "${YELLOW}5. Restarting OpenVPN service...${NC}"
restart_openvpn
if [ $? -ne 0 ]; then
    exit 1
fi

echo -e "${YELLOW}6. Verifying new configuration...${NC}"
verify_openvpn_protocol "$TARGET_PROTOCOL" "$NEW_PORT"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Protocol switch to $TARGET_PROTOCOL completed successfully!${NC}"
echo -e "${GREEN}If you experience any issues, restore the backup:${NC}"
echo -e "${CYAN}cp /etc/openvpn/server.conf.$(date +%Y%m%d)* /etc/openvpn/server.conf${NC}"
echo -e "${CYAN}systemctl restart openvpn@server${NC}"
echo -e "${GREEN}================================================${NC}"

exit 0
