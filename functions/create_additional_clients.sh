#!/bin/bash

# Function to create certificates for additional clients
create_additional_clients() {
    echo
    echo "Additional Clients"
    echo "━━━━━━━━━━━━━━━━━"
    echo "You can create certificates for additional clients if needed."

    while confirm_action "Do you want to create certificates for another client?"; do
        read -p "Enter name for the additional client: " ADDITIONAL_CLIENT
        if [ -z "$ADDITIONAL_CLIENT" ]; then
            echo "Client name cannot be empty."
            continue
        fi
        
        if [ -f ~/easy-rsa/pki/issued/$ADDITIONAL_CLIENT.crt ]; then
            echo "⚠️ A certificate for '$ADDITIONAL_CLIENT' already exists."
            if ! confirm_action "Do you want to regenerate it?"; then
                echo "Skipping certificate generation for '$ADDITIONAL_CLIENT'."
                continue
            fi
        fi
        
        echo "Creating certificates for client: $ADDITIONAL_CLIENT"
        cd ~/easy-rsa
        ./easyrsa gen-req $ADDITIONAL_CLIENT nopass
        ./easyrsa sign-req client $ADDITIONAL_CLIENT
        prepare_client "$ADDITIONAL_CLIENT"
        
        echo "Certificates for $ADDITIONAL_CLIENT created successfully."
        echo "Files location: ~/client-configs/$ADDITIONAL_CLIENT/"
    done
}
