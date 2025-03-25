#!/bin/bash

# Function to prepare client certificates
prepare_client() {
    local CLIENT_NAME=$1
    
    echo "Creating certificate archive for RouterOS..."
    mkdir -p ~/client-configs/$CLIENT_NAME
    cp ~/easy-rsa/pki/ca.crt ~/client-configs/$CLIENT_NAME/
    cp ~/easy-rsa/pki/issued/$CLIENT_NAME.crt ~/client-configs/$CLIENT_NAME/
    cp ~/easy-rsa/pki/private/$CLIENT_NAME.key ~/client-configs/$CLIENT_NAME/
}

# Function with check for existing client configuration
prepare_client_with_check() {
    local CLIENT_NAME=$1
    
    echo
    echo "Step 6: Client Certificate Preparation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step prepares the client certificates for RouterOS."
    echo "✓ You need to do this for each client you want to connect."

    if [ -d ~/client-configs/$CLIENT_NAME ]; then
        echo "✓ Client certificate directory for '$CLIENT_NAME' already exists."
        if confirm_action "Do you want to prepare the client certificates again?"; then
            prepare_client "$CLIENT_NAME"
        else
            echo "Skipping client certificate preparation."
        fi
    else
        if confirm_action "Do you want to prepare client certificates for '$CLIENT_NAME'?"; then
            prepare_client "$CLIENT_NAME"
        else
            echo "Skipping client certificate preparation."
        fi
    fi
}
