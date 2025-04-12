#!/bin/bash

# Function to configure OpenVPN server
configure_server() {
    local VPN_PORT=$1
    local VPN_SUBNET=$2
    
    echo "Creating server configuration..."
    cat > /tmp/server.conf << EOF
port $VPN_PORT
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
server $VPN_SUBNET
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
client-to-client
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

    sudo cp /tmp/server.conf /etc/openvpn/server.conf
    
    # Start OpenVPN server
    echo "Starting OpenVPN server..."
    sudo systemctl enable openvpn@server
    sudo systemctl start openvpn@server
}

# Function with check for existing configuration
configure_server_with_check() {
    local VPN_PORT=$1
    local VPN_SUBNET=$2
    
    echo
    echo "Step 4: Server Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This step configures the OpenVPN server."
    echo "✓ Basic server configuration only needs to be done once."
    echo "✓ If you're changing server settings (port, subnet), you should reconfigure."

    if [ -f /etc/openvpn/server.conf ]; then
        echo "✓ OpenVPN server configuration file already exists."
        if confirm_action "Do you want to reconfigure the server? (This will overwrite your current configuration)"; then
            configure_server "$VPN_PORT" "$VPN_SUBNET"
        else
            echo "Keeping existing server configuration."
        fi
    else
        if confirm_action "Do you want to configure the OpenVPN server?"; then
            configure_server "$VPN_PORT" "$VPN_SUBNET"
        else
            echo "Skipping server configuration. Note that the VPN won't work without proper server configuration."
        fi
    fi
}
