#!/bin/bash

# Function to list all existing client certificates
list_client_certificates() {
    echo "Existing Client Certificates:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -d ~/easy-rsa/pki/issued/ ]; then
        echo "No certificates found. Server setup may not be complete."
        return
    fi
    
    # List all non-server certificates
    ls ~/easy-rsa/pki/issued/ | grep -v "server.crt" | sed 's/.crt$//' | while read -r client; do
        if [ -d ~/client-configs/$client ]; then
            echo "  ✓ $client (Files prepared for RouterOS)"
        else
            echo "  ✓ $client (Certificate exists but files not prepared)"
        fi
    done
    echo
}

# Function to check if a client certificate exists
client_certificate_exists() {
    local CLIENT_NAME=$1
    [ -f ~/easy-rsa/pki/issued/$CLIENT_NAME.crt ]
}

# Function to manage a specific client certificate
manage_client_certificate() {
    local CLIENT_NAME=$1
    local REGENERATE=false
    
    if client_certificate_exists "$CLIENT_NAME"; then
        echo "Certificate for client '$CLIENT_NAME' already exists."
        if confirm_action "Do you want to regenerate it? (WARNING: This will invalidate existing connections)"; then
            REGENERATE=true
        fi
    else
        echo "Creating new certificate for client '$CLIENT_NAME'..."
        REGENERATE=true
    fi
    
    if $REGENERATE; then
        cd ~/easy-rsa
        ./easyrsa gen-req $CLIENT_NAME nopass
        ./easyrsa sign-req client $CLIENT_NAME
        prepare_client "$CLIENT_NAME"
        echo "Certificate for '$CLIENT_NAME' has been created/regenerated."
    fi
    
    echo "Certificate files for '$CLIENT_NAME' are located at: ~/client-configs/$CLIENT_NAME/"
}
