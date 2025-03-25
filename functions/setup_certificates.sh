#!/bin/bash

# Function to set up certificates
setup_certificates() {
    local CLIENT_NAME=$1
    
    echo "Initializing PKI and creating certificates..."
    cd ~/easy-rsa
    ./easyrsa init-pki
    ./easyrsa build-ca nopass
    ./easyrsa gen-dh
    ./easyrsa gen-req server nopass
    ./easyrsa sign-req server server

    echo "Creating client certificate for $CLIENT_NAME..."
    ./easyrsa gen-req $CLIENT_NAME nopass
    ./easyrsa sign-req client $CLIENT_NAME

    echo "Copying certificates to OpenVPN directory..."
    sudo mkdir -p /etc/openvpn
    sudo cp ~/easy-rsa/pki/ca.crt /etc/openvpn/
    sudo cp ~/easy-rsa/pki/dh.pem /etc/openvpn/
    sudo cp ~/easy-rsa/pki/issued/server.crt /etc/openvpn/
    sudo cp ~/easy-rsa/pki/private/server.key /etc/openvpn/
}

# Function with check for existing certificates
setup_certificates_with_check() {
    local CLIENT_NAME=$1
    
    echo
    echo "Step 3: Certificate Generation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step generates server and client certificates."
    echo "✓ Server certificates only need to be generated once."
    echo "✓ Each client needs its own unique certificate."
    echo "✓ If you're adding a new client to an existing server, you only need to generate client certificates."

    if [ -f ~/easy-rsa/pki/issued/server.crt ]; then
        echo "✓ Server certificates appear to be already generated."
    else
        echo "❗ Server certificates not found and will be generated."
    fi

    if [ -f ~/easy-rsa/pki/issued/$CLIENT_NAME.crt ]; then
        echo "✓ Client certificate for '$CLIENT_NAME' appears to be already generated."
        if confirm_action "Do you want to regenerate the client certificate?"; then
            setup_certificates "$CLIENT_NAME"
        else
            echo "Skipping certificate generation for '$CLIENT_NAME'."
        fi
    else
        if confirm_action "Do you want to generate certificates for server and client '$CLIENT_NAME'?"; then
            setup_certificates "$CLIENT_NAME"
        else
            echo "Skipping certificate generation. Note that the VPN won't work without proper certificates."
        fi
    fi
}
