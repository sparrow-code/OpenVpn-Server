#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== ROUTER OS CONFIGURATION GUIDE =====${NC}"
echo -e "${YELLOW}Follow these steps after transferring the certificate files to RouterOS${NC}"
echo ""
echo -e "${GREEN}1. Import certificates using WinBox:${NC}"
echo -e "   ${CYAN}- Go to System > Certificates${NC}"
echo -e "   ${CYAN}- Import ca.crt${NC}"
echo -e "   ${CYAN}- Import CLIENT_NAME.crt${NC}"
echo -e "   ${CYAN}- Import CLIENT_NAME.key${NC}"

echo -e "\n${GREEN}2. Or use these terminal commands:${NC}"
echo -e "${CYAN}/certificate import file-name=ca.crt${NC}"
echo -e "${CYAN}/certificate import file-name=CLIENT_NAME.crt${NC}"
echo -e "${CYAN}/certificate import file-name=CLIENT_NAME.key${NC}"

echo -e "\n${GREEN}3. Set up OpenVPN client (Replace placeholders with your values):${NC}"
echo -e "${CYAN}/interface ovpn-client add \\${NC}"
echo -e "${CYAN}  name=ovpn-out \\${NC}"
echo -e "${CYAN}  connect-to=YOUR_CLOUD_SERVER_IP \\${NC}"
echo -e "${CYAN}  port=VPN_PORT \\${NC}"
echo -e "${CYAN}  user=nobody \\${NC}"
echo -e "${CYAN}  mode=ip \\${NC}"
echo -e "${CYAN}  certificate=CLIENT_NAME.crt_0 \\${NC}"
echo -e "${CYAN}  auth=sha1 \\${NC}"
echo -e "${CYAN}  cipher=aes256 \\${NC}"
echo -e "${CYAN}  add-default-route=yes${NC}"

echo -e "\n${GREEN}4. Check connection status:${NC}"
echo -e "${CYAN}/interface ovpn-client print${NC}"
echo -e "${YELLOW}NOTE: Replace CLIENT_NAME, YOUR_CLOUD_SERVER_IP and VPN_PORT with your actual values${NC}"
/ip address print