#!/bin/bash

echo "=== OpenVPN Server Setup Script ==="
echo "This script will help you set up an OpenVPN server on your cloud machine."

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
    echo "================================================"
    echo "OpenVPN server setup complete!"
    echo "Certificate files for RouterOS are in: ~/client-configs/$CLIENT_NAME/"
    echo "You need to transfer these files to your RouterOS device:"
    echo "- ca.crt"
    echo "- $CLIENT_NAME.crt"
    echo "- $CLIENT_NAME.key"
    echo "================================================"
    echo
    echo "To connect additional clients, use the certificates in the respective"
    echo "client directories: ~/client-configs/[CLIENT_NAME]/"
    echo
    echo "For RouterOS devices, follow the instructions in the routerOs.sh file."
    echo "================================================"
fi
