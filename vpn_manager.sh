#!/bin/bash

# Source common utilities
source "$(dirname "$0")/utils/common.sh"

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

# Function for diagnostics and troubleshooting
diagnostics_menu() {
    show_header
    echo -e "${BOLD}${YELLOW}OpenVPN Diagnostics & Troubleshooting${NC}"
    echo
    
    echo -e "${BOLD}Choose an option:${NC}"
    echo
    echo -e "${CYAN}1)${NC} Run Server Diagnostics"
    echo -e "${CYAN}2)${NC} Troubleshoot Client Connection"
    echo -e "${CYAN}3)${NC} Switch between TCP/UDP Protocol"
    echo -e "${CYAN}4)${NC} Configure VPN Killswitch"
    echo -e "${CYAN}0)${NC} Return to Main Menu"
    echo
    
    read -p "Enter your choice [0-4]: " diag_choice
    
    case $diag_choice in
        1)
            echo -e "${YELLOW}Running server diagnostics...${NC}"
            bash "$UTILS_DIR/vpn_diagnostics.sh"
            read -p "Press Enter to continue..."
            diagnostics_menu
            ;;
        2)
            show_header
            echo -e "${BOLD}${YELLOW}Client Connection Troubleshooter${NC}"
            echo
            echo -e "This tool helps diagnose connectivity issues between the server and specific client."
            echo -e "You'll need the client's VPN IP address (usually starts with 10.8.0.x)."
            echo
            
            if [ -f /etc/openvpn/openvpn-status.log ]; then
                echo -e "${CYAN}Connected clients:${NC}"
                grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | awk '{print "  - " $2 ": " $4}' | sed 's/:.*:/: /'
                echo
            fi
            
            read -p "Enter client's VPN IP to troubleshoot: " client_ip
            if [[ $client_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                bash "$UTILS_DIR/vpn_troubleshoot.sh" "$client_ip"
            else
                echo -e "${RED}Invalid IP address format.${NC}"
            fi
            read -p "Press Enter to continue..."
            diagnostics_menu
            ;;
        3)
            show_header
            echo -e "${BOLD}${YELLOW}Protocol Switching Utility${NC}"
            echo
            
            current_proto=$(grep "^proto " /etc/openvpn/server.conf 2>/dev/null | awk '{print $2}')
            if [ -z "$current_proto" ]; then
                current_proto="unknown"
            fi
            echo -e "${YELLOW}Current protocol:${NC} ${GREEN}$current_proto${NC}"
            echo
            
            if [ "$current_proto" == "udp" ]; then
                echo -e "${CYAN}1)${NC} Switch to TCP (more reliable, slower)"
                echo -e "${CYAN}0)${NC} Cancel"
                echo
                read -p "Enter your choice [0-1]: " proto_choice
                
                if [ "$proto_choice" == "1" ]; then
                    bash "$UTILS_DIR/switch_btw_protocol.sh" tcp
                fi
            elif [ "$current_proto" == "tcp" ]; then
                echo -e "${CYAN}1)${NC} Switch to UDP (faster, less reliable)"
                echo -e "${CYAN}0)${NC} Cancel"
                echo
                read -p "Enter your choice [0-1]: " proto_choice
                
                if [ "$proto_choice" == "1" ]; then
                    bash "$UTILS_DIR/switch_btw_protocol.sh" udp
                fi
            else
                echo -e "${RED}Unable to detect current protocol.${NC}"
                echo -e "${YELLOW}You can manually specify the protocol to use:${NC}"
                echo
                echo -e "${CYAN}1)${NC} Set to UDP"
                echo -e "${CYAN}2)${NC} Set to TCP"
                echo -e "${CYAN}0)${NC} Cancel"
                echo
                read -p "Enter your choice [0-2]: " proto_choice
                
                case $proto_choice in
                    1)
                        bash "$UTILS_DIR/switch_btw_protocol.sh" udp
                        ;;
                    2)
                        bash "$UTILS_DIR/switch_btw_protocol.sh" tcp
                        ;;
                esac
            fi
            read -p "Press Enter to continue..."
            diagnostics_menu
            ;;
        4)
            show_header
            echo -e "${BOLD}${YELLOW}VPN Killswitch Configuration${NC}"
            echo
            echo -e "VPN Killswitch prevents traffic leaks by blocking all internet access"
            echo -e "if the VPN connection drops unexpectedly."
            echo
            echo -e "${CYAN}1)${NC} Enable Killswitch"
            echo -e "${CYAN}2)${NC} Disable Killswitch"
            echo -e "${CYAN}3)${NC} Check Killswitch Status"
            echo -e "${CYAN}0)${NC} Return to Diagnostics Menu"
            echo
            
            read -p "Enter your choice [0-3]: " ks_choice
            
            case $ks_choice in
                1)
                    bash "$UTILS_DIR/vpn_killswitch.sh" enable
                    ;;
                2)
                    bash "$UTILS_DIR/vpn_killswitch.sh" disable
                    ;;
                3)
                    bash "$UTILS_DIR/vpn_killswitch.sh" status
                    ;;
            esac
            read -p "Press Enter to continue..."
            diagnostics_menu
            ;;
        0)
            main_menu
            ;;
        *)
            echo -e "${RED}Invalid option. Press Enter to continue...${NC}"
            read
            diagnostics_menu
            ;;
    esac
}

# Function to create a new client
create_client() {
    show_header
    echo -e "${BOLD}${YELLOW}Create New OpenVPN Client${NC}"
    echo
    
    # Check if OpenVPN is installed and running
    if ! command -v openvpn &> /dev/null; then
        echo -e "${RED}OpenVPN is not installed.${NC}"
        echo -e "${RED}Please set up the OpenVPN server first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Get client name
    read -p "Enter name for the new client: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Client name cannot be empty.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Check if client already exists
    if [ -f "$HOME/easy-rsa/pki/issued/$client_name.crt" ]; then
        echo -e "${YELLOW}Certificate for $client_name already exists.${NC}"
        read -p "Do you want to regenerate it? (y/n): " regen
        case $regen in
            [Yy]*)
                echo -e "${YELLOW}Regenerating certificate for $client_name...${NC}"
                # Revoke old certificate
                cd "$HOME/easy-rsa"
                ./easyrsa --batch revoke "$client_name"
                ./easyrsa gen-crl
                ;;
            *)
                echo -e "${RED}Operation cancelled.${NC}"
                read -p "Press Enter to continue..."
                return
                ;;
        esac
    fi
    
    # Generate new certificate
    cd "$HOME/easy-rsa"
    echo -e "${YELLOW}Generating new certificate for $client_name...${NC}"
    if ./easyrsa --batch build-client-full "$client_name" nopass; then
        echo -e "${GREEN}Certificate for $client_name generated successfully.${NC}"
    else
        echo -e "${RED}Failed to generate certificate.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Create client directory
    client_dir="$HOME/client-configs/$client_name"
    mkdir -p "$client_dir"
    
    # Copy certificate files
    cp "$HOME/easy-rsa/pki/ca.crt" "$client_dir/"
    cp "$HOME/easy-rsa/pki/issued/$client_name.crt" "$client_dir/"
    cp "$HOME/easy-rsa/pki/private/$client_name.key" "$client_dir/"
    
    # Display success message
    echo
    echo -e "${GREEN}Client certificates created successfully!${NC}"
    echo -e "${YELLOW}Certificate files are in:${NC} ${CYAN}$client_dir/${NC}"
    
    # Ask if they want to generate OVPN file
    read -p "Do you want to generate an .ovpn file for this client? (y/n): " gen_ovpn
    case $gen_ovpn in
        [Yy]*)
            # Call get_vpn.sh with appropriate parameters
            "$SCRIPT_DIR/get_vpn.sh" "$client_name"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Function to manage existing clients
manage_clients() {
    show_header
    echo -e "${BOLD}${YELLOW}Manage OpenVPN Clients${NC}"
    echo
    
    # Check if OpenVPN is installed and running
    if ! command -v openvpn &> /dev/null; then
        echo -e "${RED}OpenVPN is not installed.${NC}"
        echo -e "${RED}Please set up the OpenVPN server first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # List existing clients
    if [ -d "$HOME/easy-rsa/pki/issued" ]; then
        clients=$(ls "$HOME/easy-rsa/pki/issued" | grep -v "server.crt" | sed 's/.crt$//')
        echo -e "${YELLOW}Existing clients:${NC}"
        
        if [ -z "$clients" ]; then
            echo -e "${RED}No clients found.${NC}"
            read -p "Press Enter to continue..."
            return
        fi
        
        # List clients with numbers
        i=1
        for client in $clients; do
            echo -e "${CYAN}$i)${NC} $client"
            i=$((i+1))
        done
        echo
    else
        echo -e "${RED}No client certificates found.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Display options
    echo -e "${BOLD}Choose an option:${NC}"
    echo -e "${CYAN}1)${NC} Revoke a client certificate"
    echo -e "${CYAN}2)${NC} Generate .ovpn file for a client"
    echo -e "${CYAN}3)${NC} View client connection status"
    echo -e "${CYAN}0)${NC} Return to main menu"
    echo
    
    read -p "Enter your choice [0-3]: " client_opt
    
    case $client_opt in
        1)
            # Revoke client
            read -p "Enter the number of the client to revoke: " client_num
            client_to_revoke=$(echo "$clients" | sed -n "${client_num}p")
            
            if [ -z "$client_to_revoke" ]; then
                echo -e "${RED}Invalid client selection.${NC}"
                read -p "Press Enter to continue..."
                manage_clients
                return
            fi
            
            echo -e "${RED}WARNING: This will permanently revoke access for $client_to_revoke.${NC}"
            read -p "Are you sure you want to continue? (y/n): " revoke_confirm
            
            case $revoke_confirm in
                [Yy]*)
                    cd "$HOME/easy-rsa"
                    if ./easyrsa --batch revoke "$client_to_revoke"; then
                        ./easyrsa gen-crl
                        echo -e "${GREEN}Certificate for $client_to_revoke has been revoked.${NC}"
                        # Copy the updated CRL to the OpenVPN directory
                        cp -f "$HOME/easy-rsa/pki/crl.pem" /etc/openvpn/
                        # Ensure proper permissions
                        chmod 644 /etc/openvpn/crl.pem
                    else
                        echo -e "${RED}Failed to revoke certificate.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}Operation cancelled.${NC}"
                    ;;
            esac
            ;;
        2)
            # Generate OVPN file
            read -p "Enter the number of the client to generate OVPN for: " client_num
            client_for_ovpn=$(echo "$clients" | sed -n "${client_num}p")
            
            if [ -z "$client_for_ovpn" ]; then
                echo -e "${RED}Invalid client selection.${NC}"
                read -p "Press Enter to continue..."
                manage_clients
                return
            fi
            
            # Call get_vpn.sh with appropriate parameters
            "$SCRIPT_DIR/get_vpn.sh" "$client_for_ovpn"
            ;;
        3)
            # View client connection status
            if [ -f /etc/openvpn/openvpn-status.log ]; then
                echo -e "${YELLOW}Connected clients:${NC}"
                grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | while read -r line; do
                    client_name=$(echo "$line" | awk '{print $2}')
                    client_ip=$(echo "$line" | awk '{print $4}' | sed 's/:.*$//')
                    client_real_ip=$(echo "$line" | awk '{print $3}' | sed 's/:.*$//')
                    connected_since=$(echo "$line" | awk '{print $8 " " $9}')
                    echo -e "${CYAN}$client_name${NC}"
                    echo -e "  - VPN IP: $client_ip"
                    echo -e "  - Real IP: $client_real_ip"
                    echo -e "  - Connected since: $connected_since"
                    echo
                done
            else
                echo -e "${YELLOW}No status log found or no clients currently connected.${NC}"
            fi
            ;;
        0)
            main_menu
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
    manage_clients
}

# Function for server configuration
server_configuration() {
    show_header
    echo -e "${BOLD}${YELLOW}OpenVPN Server Configuration${NC}"
    echo
    
    # Check if OpenVPN is installed
    if ! command -v openvpn &> /dev/null; then
        echo -e "${RED}OpenVPN is not installed.${NC}"
        echo -e "${RED}Please set up the OpenVPN server first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Display current configuration
    current_port=$(get_server_config_param "port")
    current_proto=$(get_server_config_param "proto")
    current_subnet=$(grep "^server " /etc/openvpn/server.conf 2>/dev/null | awk '{print $2 "/" substr($3, index($3, ".") + 1)}')
    
    echo -e "${YELLOW}Current configuration:${NC}"
    echo -e "  Port: ${GREEN}$current_port${NC}"
    echo -e "  Protocol: ${GREEN}$current_proto${NC}"
    echo -e "  VPN Subnet: ${GREEN}$current_subnet${NC}"
    echo
    
    # Configuration options
    echo -e "${BOLD}Choose an option:${NC}"
    echo -e "${CYAN}1)${NC} Change port"
    echo -e "${CYAN}2)${NC} Switch protocol (UDP/TCP)"
    echo -e "${CYAN}3)${NC} Modify server.conf manually"
    echo -e "${CYAN}4)${NC} Restart OpenVPN service"
    echo -e "${CYAN}0)${NC} Return to main menu"
    echo
    
    read -p "Enter your choice [0-4]: " config_choice
    
    case $config_choice in
        1)
            # Change port
            read -p "Enter new port number: " new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                backup_server_config
                sed -i "s/^port .*/port $new_port/" /etc/openvpn/server.conf
                echo -e "${GREEN}Port updated to $new_port.${NC}"
                echo -e "${YELLOW}Remember to update your firewall rules.${NC}"
                read -p "Do you want to restart OpenVPN to apply changes? (y/n): " restart
                case $restart in
                    [Yy]*)
                        restart_openvpn
                        ;;
                esac
            else
                echo -e "${RED}Invalid port number.${NC}"
            fi
            ;;
        2)
            # Switch protocol (call dedicated script)
            if [ "$current_proto" == "udp" ]; then
                bash "$UTILS_DIR/switch_btw_protocol.sh" tcp
            else
                bash "$UTILS_DIR/switch_btw_protocol.sh" udp
            fi
            ;;
        3)
            # Edit server.conf manually
            if command -v nano &>/dev/null; then
                nano /etc/openvpn/server.conf
            elif command -v vim &>/dev/null; then
                vim /etc/openvpn/server.conf
            else
                echo -e "${RED}No suitable text editor found.${NC}"
            fi
            
            read -p "Do you want to restart OpenVPN to apply changes? (y/n): " restart
            case $restart in
                [Yy]*)
                    restart_openvpn
                    ;;
            esac
            ;;
        4)
            # Restart OpenVPN service
            restart_openvpn
            ;;
        0)
            main_menu
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
    server_configuration
}

# Function to view detailed status
view_status() {
    show_header
    echo -e "${BOLD}${YELLOW}OpenVPN Server Status${NC}"
    echo
    
    # Check OpenVPN service status
    echo -e "${YELLOW}Service Status:${NC}"
    if systemctl is-active --quiet openvpn@server; then
        echo -e "${GREEN}● OpenVPN server is running${NC}"
    elif systemctl is-active --quiet openvpn; then
        echo -e "${GREEN}● OpenVPN service is running${NC}"
    else
        echo -e "${RED}✗ OpenVPN service is not running${NC}"
        systemctl status openvpn@server --no-pager -l | head -n 20
        read -p "Press Enter to continue..."
        return
    fi
    
    # Interface info
    VPN_IF=$(detect_vpn_interface)
    if [ -n "$VPN_IF" ]; then
        echo
        echo -e "${YELLOW}Interface Information:${NC}"
        ip addr show dev $VPN_IF
    fi
    
    # Connected clients
    echo
    echo -e "${YELLOW}Connected Clients:${NC}"
    if [ -f /etc/openvpn/openvpn-status.log ]; then
        client_count=$(grep -c "^CLIENT_LIST" /etc/openvpn/openvpn-status.log)
        if [ "$client_count" -gt 0 ]; then
            echo -e "${GREEN}$client_count clients connected${NC}"
            echo
            echo -e "${CYAN}Name                 VPN IP       Real IP             Connected Since${NC}"
            echo -e "${CYAN}----                 ------       -------             ---------------${NC}"
            grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | while read -r line; do
                client=$(echo "$line" | awk '{print $2}')
                vpn_ip=$(echo "$line" | awk '{print $4}' | sed 's/:.*$//')
                real_ip=$(echo "$line" | awk '{print $3}' | sed 's/:.*$//')
                connected_since=$(echo "$line" | awk '{print $8 " " $9}')
                printf "%-20s %-12s %-20s %s\n" "$client" "$vpn_ip" "$real_ip" "$connected_since"
            done
        else
            echo -e "${YELLOW}No clients currently connected${NC}"
        fi
    else
        echo -e "${RED}Status log not found${NC}"
    fi
    
    # Network info
    echo
    echo -e "${YELLOW}Network Configuration:${NC}"
    routing_entries=$(ip route | grep -E 'tun|tap')
    echo "$routing_entries"
    
    # Configuration
    echo
    echo -e "${YELLOW}Server Configuration:${NC}"
    if [ -f /etc/openvpn/server.conf ]; then
        echo -e "Port: $(get_server_config_param "port")"
        echo -e "Protocol: $(get_server_config_param "proto")"
        echo -e "Cipher: $(get_server_config_param "cipher")"
        echo -e "Network: $(grep "^server" /etc/openvpn/server.conf | awk '{print $2"/"substr($3,5)}')"
        echo -e "Client-to-client: $(grep -q "^client-to-client" /etc/openvpn/server.conf && echo Enabled || echo Disabled)"
    else
        echo -e "${RED}Server configuration file not found${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Function to set up OpenVPN
setup_openvpn() {
    # This function would call the setupVpn.sh script
    show_header
    
    # Check if script exists
    if [ -f "$SCRIPT_DIR/setupVpn.sh" ]; then
        echo -e "${YELLOW}Launching OpenVPN setup script...${NC}"
        bash "$SCRIPT_DIR/setupVpn.sh"
    else
        echo -e "${RED}Setup script not found.${NC}"
        echo -e "${RED}Expected path: $SCRIPT_DIR/setupVpn.sh${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Main program
clear
check_root
main_menu
