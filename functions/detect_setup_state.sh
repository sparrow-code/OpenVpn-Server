#!/bin/bash

# Function to detect the current state of OpenVPN setup
detect_setup_state() {
    # Initialize state variables
    PACKAGES_INSTALLED=false
    EASYRSA_SETUP=false
    SERVER_CERTS_EXIST=false
    SERVER_CONFIGURED=false
    NETWORK_CONFIGURED=false
    SERVER_RUNNING=false

    # Check if packages are installed
    if [ -f /usr/sbin/openvpn ] && [ -d /usr/share/easy-rsa ]; then
        PACKAGES_INSTALLED=true
    fi

    # Check if Easy-RSA is set up
    if [ -d ~/easy-rsa/pki ]; then
        EASYRSA_SETUP=true
    fi

    # Check if server certificates exist
    if [ -f ~/easy-rsa/pki/issued/server.crt ] && [ -f ~/easy-rsa/pki/private/server.key ]; then
        SERVER_CERTS_EXIST=true
    fi

    # Check if server is configured
    if [ -f /etc/openvpn/server.conf ]; then
        SERVER_CONFIGURED=true
    fi

    # Check if network forwarding is enabled
    if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        NETWORK_CONFIGURED=true
    fi

    # Check if OpenVPN server is running
    if systemctl is-active --quiet openvpn@server; then
        SERVER_RUNNING=true
    fi

    # Determine overall setup state
    if $SERVER_RUNNING && $SERVER_CONFIGURED && $SERVER_CERTS_EXIST && $NETWORK_CONFIGURED; then
        SETUP_COMPLETE=true
    else
        SETUP_COMPLETE=false
    fi

    # Output detected state
    echo "Detected OpenVPN Setup State:"
    echo "✓ Packages Installed: $PACKAGES_INSTALLED"
    echo "✓ Easy-RSA Setup: $EASYRSA_SETUP"
    echo "✓ Server Certificates: $SERVER_CERTS_EXIST"
    echo "✓ Server Configured: $SERVER_CONFIGURED"
    echo "✓ Network Configured: $NETWORK_CONFIGURED"
    echo "✓ Server Running: $SERVER_RUNNING"
    echo "✓ Setup Complete: $SETUP_COMPLETE"
    echo
}

# Function to get current server settings if they exist
get_current_server_settings() {
    if [ -f /etc/openvpn/server.conf ]; then
        CURRENT_VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
        CURRENT_VPN_SUBNET=$(grep "^server " /etc/openvpn/server.conf | awk '{print $2 " " $3}')
        
        echo "Current server settings:"
        echo "  - Port: $CURRENT_VPN_PORT"
        echo "  - Subnet: $CURRENT_VPN_SUBNET"
        echo
        
        # Update the global variables if they weren't explicitly set
        VPN_PORT=${VPN_PORT:-$CURRENT_VPN_PORT}
        VPN_SUBNET=${VPN_SUBNET:-$CURRENT_VPN_SUBNET}
    fi
}
