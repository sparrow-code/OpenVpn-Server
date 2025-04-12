#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
UTILS_DIR="$SCRIPT_DIR/utils"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        echo -e "${YELLOW}Please run with sudo or as root user${NC}"
        exit 1
    fi
}

# Function to clear screen and display header
show_header() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BOLD}${PURPLE}           OpenVPN Management System${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo
}

# Function to check OpenVPN status
check_openvpn_status() {
    echo -e "${YELLOW}Checking OpenVPN Status...${NC}"
    
    if ! command -v openvpn &> /dev/null; then
        echo -e "${RED}OpenVPN is not installed on this system.${NC}"
        return 1
    fi
    
    if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
        echo -e "${GREEN}✓ OpenVPN service is running${NC}"
        
        # Check listening ports
        local PORTS=$(ss -tulpn | grep -i 'openvpn')
        if [ -n "$PORTS" ]; then
            echo -e "${GREEN}✓ Listening on: ${NC}"
            echo "$PORTS" | awk '{print "  - " $5}' | sed 's/.*://' | sort -u | while read port; do
                echo -e "  ${CYAN}- Port $port${NC}"
            done
        else
            echo -e "${YELLOW}⚠ No listening ports detected${NC}"
        fi
        
        # Check active connections if possible
        if [ -f /var/log/openvpn/status.log ]; then
            local CLIENTS=$(grep -c "CLIENT_LIST" /var/log/openvpn/status.log)
            echo -e "${GREEN}✓ Connected clients: $((CLIENTS-1))${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}✗ OpenVPN service is not running${NC}"
        return 1
    fi
}

# Function to render the main menu
main_menu() {
    show_header
    
    # Display status summary if OpenVPN is installed
    if command -v openvpn &> /dev/null; then
        echo -e "${YELLOW}OpenVPN Status:${NC}"
        systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}● Service: Running${NC}"
        else
            echo -e "${RED}● Service: Stopped${NC}"
        fi
        echo
    fi
    
    echo -e "${BOLD}Choose an option:${NC}"
    echo
    echo -e "${CYAN}1)${NC} Setup OpenVPN Server"
    echo -e "${CYAN}2)${NC} Create New Client"
    echo -e "${CYAN}3)${NC} Manage Existing Clients"
    echo -e "${CYAN}4)${NC} Server Configuration"
    echo -e "${CYAN}5)${NC} Diagnostics & Troubleshooting"
    echo -e "${CYAN}6)${NC} View OpenVPN Status"
    echo -e "${CYAN}0)${NC} Exit"
    echo
    
    read -p "Enter your choice [0-6]: " choice
    
    case $choice in
        1)
            setup_openvpn
            ;;
        2)
            create_client
            ;;
        3)
            manage_clients
            ;;
        4)
            server_configuration
            ;;
        5)
            diagnostics_menu
            ;;
        6)
            view_status
            ;;
        0)
            echo -e "${GREEN}Exiting. Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Press Enter to continue...${NC}"
            read
            main_menu
            ;;
    esac
}

# Function to set up OpenVPN
setup_openvpn() {
    show_header
    echo -e "${BOLD}${YELLOW}OpenVPN Server Setup${NC}"
    echo
    
    if command -v openvpn &> /dev/null && (systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn); then
        echo -e "${YELLOW}OpenVPN appears to be already installed and running.${NC}"
        echo -e "${YELLOW}What would you like to do?${NC}"
        echo
        echo -e "${CYAN}1)${NC} Proceed with setup anyway (may overwrite existing configuration)"
        echo -e "${CYAN}2)${NC} Return to main menu"
        echo
        
        read -p "Enter your choice [1-2]: " proceed_choice
        
        case $proceed_choice in
            1)
                echo -e "${YELLOW}Proceeding with OpenVPN setup...${NC}"
                ;;
            2)
                main_menu
                return
                ;;
            *)
                echo -e "${RED}Invalid option. Returning to main menu...${NC}"
                sleep 2
                main_menu
                return
                ;;
        esac
    fi
    
    echo -e "${YELLOW}Starting OpenVPN server installation and configuration...${NC}"
    echo -e "${YELLOW}This will install OpenVPN and set up a server with default settings.${NC}"
    echo
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    
    # Run the OpenVPN setup script
    bash "$SCRIPT_DIR/setupVpn.sh"
    
    echo
    echo -e "${GREEN}OpenVPN setup process completed.${NC}"
    read -p "Press Enter to return to main menu..."
    main_menu
}

# Function to create a new client
create_client() {
    show_header
    echo -e "${BOLD}${YELLOW}Create New OpenVPN Client${NC}"
    echo
    
    # Check if OpenVPN is installed and running
    if ! command -v openvpn &> /dev/null; then
        echo -e "${RED}Error: OpenVPN is not installed on this system.${NC}"
        echo -e "${YELLOW}Please set up OpenVPN server first.${NC}"
        echo
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    read -p "Enter client name (alphanumeric and underscores only): " client_name
    
    # Validate client name
    if ! [[ $client_name =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}Error: Client name must only contain alphanumeric characters and underscores.${NC}"
        echo
        read -p "Press Enter to try again..."
        create_client
        return
    fi
    
    echo -e "${YELLOW}Creating client certificates for '${CYAN}$client_name${YELLOW}'...${NC}"
    
    # Run the get_vpn.sh script to create client
    if [ -f "$SCRIPT_DIR/get_vpn.sh" ]; then
        bash "$SCRIPT_DIR/get_vpn.sh" "$client_name"
    else
        echo -e "${RED}Error: Client creation script not found.${NC}"
    fi
    
    echo
    echo -e "${GREEN}Client creation process completed.${NC}"
    read -p "Press Enter to return to main menu..."
    main_menu
}

# Function to manage existing clients
manage_clients() {
    show_header
    echo -e "${BOLD}${YELLOW}Manage Existing Clients${NC}"
    echo
    
    local client_dir="$HOME/client-configs"
    if [ ! -d "$client_dir" ]; then
        echo -e "${RED}Client directory not found.${NC}"
        echo -e "${YELLOW}Please set up OpenVPN server and create clients first.${NC}"
        echo
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    echo -e "${YELLOW}Existing clients:${NC}"
    echo
    
    # List all client directories and extract client names
    local client_count=0
    local client_names=()
    for dir in "$client_dir"/*; do
        if [ -d "$dir" ]; then
            client_name=$(basename "$dir")
            if [ -f "$dir/$client_name.ovpn" ] || [ -f "$dir/$client_name.crt" ]; then
                client_count=$((client_count+1))
                client_names+=("$client_name")
                echo -e "${CYAN}$client_count)${NC} $client_name"
            fi
        fi
    done
    
    if [ $client_count -eq 0 ]; then
        echo -e "${YELLOW}No clients found.${NC}"
        echo
        read -p "Press Enter to return to main menu..."
        main_menu
        return
    fi
    
    echo
    echo -e "${CYAN}R)${NC} Return to main menu"
    echo
    
    read -p "Select a client to manage [1-$client_count or R]: " client_choice
    
    if [[ $client_choice == "R" || $client_choice == "r" ]]; then
        main_menu
        return
    fi
    
    if ! [[ $client_choice =~ ^[0-9]+$ ]] || [ $client_choice -lt 1 ] || [ $client_choice -gt $client_count ]; then
        echo -e "${RED}Invalid selection.${NC}"
        echo
        read -p "Press Enter to try again..."
        manage_clients
        return
    fi
    
    selected_client="${client_names[$((client_choice-1))]}"
    
    # Show client management options
    show_header
    echo -e "${BOLD}${YELLOW}Managing Client: ${CYAN}$selected_client${NC}"
    echo
    echo -e "${CYAN}1)${NC} View client configuration"
    echo -e "${CYAN}2)${NC} Revoke client access"
    echo -e "${CYAN}3)${NC} Regenerate client configuration"
    echo -e "${CYAN}R)${NC} Return to client list"
    echo
    
    read -p "Enter your choice [1-3 or R]: " action_choice
    
    case $action_choice in
        1)
            # View client configuration
            if [ -f "$client_dir/$selected_client/$selected_client.ovpn" ]; then
                echo -e "${YELLOW}Client configuration for $selected_client:${NC}"
                echo
                cat "$client_dir/$selected_client/$selected_client.ovpn" | less
            else
                echo -e "${RED}Configuration file not found for $selected_client.${NC}"
            fi
            ;;
        2)
            # Revoke client access (placeholder - actual implementation would depend on your CA structure)
            echo -e "${YELLOW}Revoking access for client: $selected_client${NC}"
            echo -e "${RED}This functionality requires implementation specific to your CA structure.${NC}"
            ;;
        3)
            # Regenerate client config
            echo -e "${YELLOW}Regenerating configuration for client: $selected_client${NC}"
            if [ -f "$SCRIPT_DIR/get_vpn.sh" ]; then
                bash "$SCRIPT_DIR/get_vpn.sh" "$selected_client" "regenerate"
            else
                echo -e "${RED}Client creation script not found.${NC}"
            fi
            ;;
        [Rr])
            manage_clients
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    echo
    read -p "Press Enter to return to client list..."
    manage_clients
}

# Function for server configuration options
server_configuration() {
    show_header
    echo -e "${BOLD}${YELLOW}Server Configuration${NC}"
    echo
    
    echo -e "${CYAN}1)${NC} Switch to TCP protocol"
    echo -e "${CYAN}2)${NC} Switch to UDP protocol" 
    echo -e "${CYAN}3)${NC} Restart OpenVPN service"
    echo -e "${CYAN}4)${NC} Start OpenVPN service"
    echo -e "${CYAN}5)${NC} Stop OpenVPN service"
    echo -e "${CYAN}6)${NC} View server configuration"
    echo -e "${CYAN}R)${NC} Return to main menu"
    echo
    
    read -p "Enter your choice [1-6 or R]: " config_choice
    
    case $config_choice in
        1)
            # Run switch to TCP script
            echo -e "${YELLOW}Switching to TCP protocol...${NC}"
            if [ -f "$UTILS_DIR/switch_btw_protocol.sh" ]; then
                bash "$UTILS_DIR/switch_btw_protocol.sh" tcp
            else
                echo -e "${RED}Protocol switch script not found.${NC}"
            fi
            ;;
        2)
            # Run switch to UDP script
            echo -e "${YELLOW}Switching to UDP protocol...${NC}"
            if [ -f "$UTILS_DIR/switch_btw_protocol.sh" ]; then
                bash "$UTILS_DIR/switch_btw_protocol.sh" udp
            else
                echo -e "${RED}Protocol switch script not found.${NC}"
            fi
            ;;
        3)
            # Restart OpenVPN service
            echo -e "${YELLOW}Restarting OpenVPN service...${NC}"
            systemctl restart openvpn@server || systemctl restart openvpn
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}OpenVPN service restarted successfully.${NC}"
            else
                echo -e "${RED}Failed to restart OpenVPN service.${NC}"
            fi
            ;;
        4)
            # Start OpenVPN service
            echo -e "${YELLOW}Starting OpenVPN service...${NC}"
            systemctl start openvpn@server || systemctl start openvpn
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}OpenVPN service started successfully.${NC}"
            else
                echo -e "${RED}Failed to start OpenVPN service.${NC}"
            fi
            ;;
        5)
            # Stop OpenVPN service
            echo -e "${YELLOW}Stopping OpenVPN service...${NC}"
            systemctl stop openvpn@server || systemctl stop openvpn
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}OpenVPN service stopped successfully.${NC}"
            else
                echo -e "${RED}Failed to stop OpenVPN service.${NC}"
            fi
            ;;
        6)
            # View server configuration
            echo -e "${YELLOW}Server configuration:${NC}"
            echo
            if [ -f /etc/openvpn/server.conf ]; then
                cat /etc/openvpn/server.conf | less
            else
                echo -e "${RED}Server configuration file not found.${NC}"
            fi
            ;;
        [Rr])
            main_menu
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    echo
    read -p "Press Enter to return to server configuration menu..."
    server_configuration
}

# Function for diagnostics and troubleshooting menu
diagnostics_menu() {
    show_header
    echo -e "${BOLD}${YELLOW}Diagnostics & Troubleshooting${NC}"
    echo
    
    echo -e "${CYAN}1)${NC} Run full diagnostic scan"
    echo -e "${CYAN}2)${NC} Check OpenVPN service status"
    echo -e "${CYAN}3)${NC} View OpenVPN logs"
    echo -e "${CYAN}4)${NC} Check network interfaces"
    echo -e "${CYAN}5)${NC} Check firewall rules"
    echo -e "${CYAN}6)${NC} Run connection troubleshooter" 
    echo -e "${CYAN}7)${NC} Test client connectivity"
    echo -e "${CYAN}R)${NC} Return to main menu"
    echo
    
    read -p "Enter your choice [1-7 or R]: " diag_choice
    
    case $diag_choice in
        1)
            # Run full diagnostics script
            echo -e "${YELLOW}Running full diagnostic scan...${NC}"
            if [ -f "$UTILS_DIR/vpn_diagnostics.sh" ]; then
                bash "$UTILS_DIR/vpn_diagnostics.sh"
            else
                echo -e "${RED}Diagnostics script not found.${NC}"
            fi
            ;;
        2)
            # Check OpenVPN service status
            echo -e "${YELLOW}Checking OpenVPN service status...${NC}"
            echo
            systemctl status openvpn@server || systemctl status openvpn
            ;;
        3)
            # View OpenVPN logs
            echo -e "${YELLOW}OpenVPN logs:${NC}"
            echo
            if [ -f /var/log/openvpn.log ]; then
                tail -n 50 /var/log/openvpn.log | less
            elif [ -f /var/log/syslog ]; then
                grep -i openvpn /var/log/syslog | tail -n 50 | less
            else
                journalctl -u openvpn@server -n 50 | less
            fi
            ;;
        4)
            # Check network interfaces
            echo -e "${YELLOW}Network interfaces:${NC}"
            echo
            ip a | grep -E "inet|tun|tap"
            echo
            echo -e "${YELLOW}Routing table:${NC}"
            ip route
            ;;
        5)
            # Check firewall rules
            echo -e "${YELLOW}Firewall rules:${NC}"
            echo
            if command -v ufw &> /dev/null; then
                ufw status
            elif command -v firewall-cmd &> /dev/null; then
                firewall-cmd --list-all
            else
                iptables -L -n -v
            fi
            ;;
        6)
            # Run troubleshooter script
            echo -e "${YELLOW}Running connection troubleshooter...${NC}"
            if [ -f "$UTILS_DIR/vpn_troubleshoot.sh" ]; then
                bash "$UTILS_DIR/vpn_troubleshoot.sh"
            else
                echo -e "${RED}Troubleshooter script not found.${NC}"
            fi
            ;;
        7)
            # Test client connectivity (placeholder)
            echo -e "${YELLOW}Testing client connectivity...${NC}"
            echo
            echo -e "${CYAN}This would typically ping a client or check their connection status.${NC}"
            echo -e "${CYAN}Implementation would depend on your specific network setup.${NC}"
            ;;
        [Rr])
            main_menu
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    echo
    read -p "Press Enter to return to diagnostics menu..."
    diagnostics_menu
}

# Function to view detailed OpenVPN status
view_status() {
    show_header
    echo -e "${BOLD}${YELLOW}OpenVPN Status${NC}"
    echo
    
    check_openvpn_status
    
    if [ -f /var/log/openvpn/status.log ]; then
        echo
        echo -e "${YELLOW}Connected clients:${NC}"
        echo
        grep "CLIENT_LIST" /var/log/openvpn/status.log | tail -n +2 | while read -r line; do
            client=$(echo "$line" | awk '{print $2}')
            ip=$(echo "$line" | awk '{print $3}')
            connected_since=$(echo "$line" | awk '{print $5, $6, $7, $8}')
            echo -e "${CYAN}$client${NC} - IP: $ip - Connected since: $connected_since"
        done
    else
        echo
        echo -e "${YELLOW}Cannot find OpenVPN status log. Detailed client information not available.${NC}"
    fi
    
    echo
    echo -e "${YELLOW}Server configuration summary:${NC}"
    if [ -f /etc/openvpn/server.conf ]; then
        echo -e "Protocol: ${CYAN}$(grep -E "^proto " /etc/openvpn/server.conf | awk '{print $2}')${NC}"
        echo -e "Port: ${CYAN}$(grep -E "^port " /etc/openvpn/server.conf | awk '{print $2}')${NC}"
        echo -e "Cipher: ${CYAN}$(grep -E "^cipher " /etc/openvpn/server.conf | awk '{print $2}')${NC}"
        
        if grep -q "^push.*redirect-gateway" /etc/openvpn/server.conf; then
            echo -e "Routing: ${CYAN}All traffic through VPN${NC}"
        else
            echo -e "Routing: ${CYAN}Split tunnel${NC}"
        fi
    else
        echo -e "${RED}Server configuration file not found.${NC}"
    fi
    
    echo
    read -p "Press Enter to return to main menu..."
    main_menu
}

# Main program
clear
check_root
main_menu
