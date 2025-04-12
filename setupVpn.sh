#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OpenVPN Server Setup Script ===${NC}"
echo -e "${GREEN}This script will help you set up an OpenVPN server on your cloud machine.${NC}"

# Source function files
source "$(dirname "$0")/functions/utils.sh"
source "$(dirname "$0")/functions/install_packages.sh"
source "$(dirname "$0")/functions/setup_easyrsa.sh"
source "$(dirname "$0")/functions/setup_certificates.sh"
source "$(dirname "$0")/functions/configure_server.sh"
source "$(dirname "$0")/functions/setup_network.sh"
source "$(dirname "$0")/functions/prepare_client.sh"
source "$(dirname "$0")/functions/create_additional_clients.sh"
source "$(dirname "$0")/functions/detect_setup_state.sh"
source "$(dirname "$0")/functions/certificate_management.sh"

# Function to display messages with color
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Check for existing OpenVPN installation
check_existing_installation

# Detect current setup state
detect_setup_state

# Determine mode based on setup state
if $SETUP_COMPLETE; then
    echo "OpenVPN Server is already set up and running."
    echo "Entering client management mode."
    echo
    
    # Get current server settings
    get_current_server_settings
    
    # List existing clients
    list_client_certificates
    
    # Client management mode
    while true; do
        echo "Client Management Options:"
        echo "1. Create a new client certificate"
        echo "2. Regenerate an existing client certificate"
        echo "3. List all client certificates"
        echo "4. Exit"
        read -p "Select an option (1-4): " OPTION
        
        case $OPTION in
            1)
                read -p "Enter name for the new client: " CLIENT_NAME
                if [ -z "$CLIENT_NAME" ]; then
                    echo "Client name cannot be empty."
                    continue
                fi
                manage_client_certificate "$CLIENT_NAME"
                ;;
            2)
                list_client_certificates
                read -p "Enter name of the client to regenerate: " CLIENT_NAME
                if [ -z "$CLIENT_NAME" ]; then
                    echo "Client name cannot be empty."
                    continue
                fi
                if ! client_certificate_exists "$CLIENT_NAME"; then
                    echo "Client '$CLIENT_NAME' does not exist."
                    continue
                fi
                manage_client_certificate "$CLIENT_NAME"
                ;;
            3)
                list_client_certificates
                ;;
            4)
                echo "Exiting client management."
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
else
    echo "OpenVPN Server is not fully set up."
    echo "Entering server setup mode."
    echo
    
    # User inputs for server setup
    read -p "Enter your cloud server's public IP address: " SERVER_IP
    read -p "Enter OpenVPN port [default: 1194]: " VPN_PORT
    VPN_PORT=${VPN_PORT:-1194}
    read -p "Enter VPN subnet [default: 10.8.0.0/24]: " VPN_SUBNET
    VPN_SUBNET=${VPN_SUBNET:-"10.8.0.0 255.255.255.0"}
    read -p "Enter initial client name for RouterOS [default: routeros]: " CLIENT_NAME
    CLIENT_NAME=${CLIENT_NAME:-routeros}

    # Confirm configuration
    echo
    echo "Configuration Summary:"
    echo "Server IP: $SERVER_IP"
    echo "VPN Port: $VPN_PORT"
    echo "VPN Subnet: $VPN_SUBNET"
    echo "Initial Client Name: $CLIENT_NAME"
    echo

    if ! confirm_action "Is this configuration correct?"; then
        echo "Please restart the script with the correct configuration."
        exit 1
    fi

    # Run setup steps (only if needed)
    if ! $PACKAGES_INSTALLED; then
        install_packages
    else
        echo "✓ Packages are already installed. Skipping installation."
    fi

    if ! $EASYRSA_SETUP; then
        setup_easyrsa
    else
        echo "✓ Easy-RSA is already set up. Skipping setup."
    fi

    if ! $SERVER_CERTS_EXIST; then
        setup_certificates "$CLIENT_NAME"
    else
        echo "✓ Server certificates already exist. Skipping generation."
        manage_client_certificate "$CLIENT_NAME"
    fi

    if ! $SERVER_CONFIGURED; then
        configure_server "$VPN_PORT" "$VPN_SUBNET"
    else
        echo "✓ Server is already configured. Skipping configuration."
        
        # Check if configs need to be updated
        if [ "$CURRENT_VPN_PORT" != "$VPN_PORT" ] || [ "$CURRENT_VPN_SUBNET" != "$VPN_SUBNET" ]; then
            echo "WARNING: You specified different port/subnet than currently configured."
            if confirm_action "Do you want to update the server configuration? (This will restart OpenVPN)"; then
                configure_server "$VPN_PORT" "$VPN_SUBNET"
            fi
        fi
    fi

    if ! $NETWORK_CONFIGURED; then
        setup_network
    else
        echo "✓ Network forwarding is already configured. Skipping setup."
    fi
    
    # Ask for additional clients
    create_additional_clients

    # Display completion message
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}OpenVPN server setup complete!${NC}"
    echo -e "${YELLOW}Certificate files for RouterOS are in: ${NC}${CYAN}~/client-configs/$CLIENT_NAME/${NC}"
    echo -e "${YELLOW}You need to transfer these files to your RouterOS device:${NC}"
    
    # Check if certificate files exist and display with verification
    CERT_DIR="$HOME/client-configs/$CLIENT_NAME"
    if [ -f "$CERT_DIR/ca.crt" ]; then
        echo -e "${GREEN}✅ - ca.crt${NC} (${CYAN}$CERT_DIR/ca.crt${NC})"
    else
        echo -e "${RED}❌ - ca.crt not found${NC}"
    fi
    
    if [ -f "$CERT_DIR/$CLIENT_NAME.crt" ]; then
        echo -e "${GREEN}✅ - $CLIENT_NAME.crt${NC} (${CYAN}$CERT_DIR/$CLIENT_NAME.crt${NC})"
    else
        echo -e "${RED}❌ - $CLIENT_NAME.crt not found${NC}"
    fi
    
    if [ -f "$CERT_DIR/$CLIENT_NAME.key" ]; then
        echo -e "${GREEN}✅ - $CLIENT_NAME.key${NC} (${CYAN}$CERT_DIR/$CLIENT_NAME.key${NC})"
    else
        echo -e "${RED}❌ - $CLIENT_NAME.key not found${NC}"
    fi
    
    # Add commands for transferring files
    echo -e "\n${YELLOW}To transfer files to RouterOS using SCP:${NC}"
    echo -e "${CYAN}scp $CERT_DIR/ca.crt $CERT_DIR/$CLIENT_NAME.crt $CERT_DIR/$CLIENT_NAME.key admin@router-ip-address:/${NC}"
    
    echo -e "${BLUE}================================================${NC}"
    echo
    echo -e "${YELLOW}To connect additional clients, use the certificates in the respective${NC}"
    echo -e "${YELLOW}client directories: ${NC}${CYAN}~/client-configs/[CLIENT_NAME]/${NC}"
    echo
    echo "For RouterOS devices, follow the instructions in the routerOs.sh file."
    echo "================================================"
fi
