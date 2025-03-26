#!/bin/bash

echo "=== OpenVPN Client Configuration Generator ==="
echo "This script generates .ovpn configuration files for OpenVPN clients."

# Get the real user's home directory even when run with sudo
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

# Default values
CERT_DIR="$USER_HOME/easy-rsa"
OUTPUT_DIR="$USER_HOME/ovpn_configs"
DEFAULT_PORT="1194"
DEFAULT_PROTO="udp"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
chown -R "$SUDO_USER":"$SUDO_USER" "$OUTPUT_DIR" 2>/dev/null || true

# Function to list available client certificates
list_available_clients() {
    echo "Available client certificates:"
    echo "-----------------------------"
    
    if [ ! -d "$CERT_DIR/pki/issued" ]; then
        echo "No certificates found in $CERT_DIR/pki/issued"
        echo "Make sure you've set up OpenVPN and generated client certificates first."
        exit 1
    fi
    
    # List all non-server certificates
    local clients=$(ls "$CERT_DIR/pki/issued" | grep -v "server.crt" | sed 's/.crt$//')
    
    if [ -z "$clients" ]; then
        echo "No client certificates found."
        exit 1
    fi
    
    local i=1
    for client in $clients; do
        echo "$i) $client"
        i=$((i+1))
    done
    
    echo ""
    return 0
}

# Function to get server IP
get_server_ip() {
    local server_ip
    
    # Try to get server IP from existing configuration
    if [ -f "/etc/openvpn/server.conf" ]; then
        local public_ip=$(hostname -I | cut -d' ' -f1)
        echo "Detected server IP: $public_ip"
        read -p "Is this your server's public IP? (y/n): " confirm
        
        if [[ $confirm =~ ^[Yy] ]]; then
            server_ip="$public_ip"
        fi
    fi
    
    # If not confirmed or found, ask user
    if [ -z "$server_ip" ]; then
        read -p "Enter your OpenVPN server's public IP address: " server_ip
        while [ -z "$server_ip" ]; do
            echo "Server IP cannot be empty."
            read -p "Enter your OpenVPN server's public IP address: " server_ip
        done
    fi
    
    echo "$server_ip"
}

# Function to get server port
get_server_port() {
    local server_port
    
    # Try to get port from existing configuration
    if [ -f "/etc/openvpn/server.conf" ]; then
        local detected_port=$(grep "^port " /etc/openvpn/server.conf | awk '{print $2}')
        
        if [ -n "$detected_port" ]; then
            echo "Detected OpenVPN port: $detected_port"
            read -p "Use this port? (y/n): " confirm
            
            if [[ $confirm =~ ^[Yy] ]]; then
                server_port="$detected_port"
            fi
        fi
    fi
    
    # If not confirmed or found, ask user
    if [ -z "$server_port" ]; then
        read -p "Enter OpenVPN server port [default: $DEFAULT_PORT]: " server_port
        server_port=${server_port:-$DEFAULT_PORT}
    fi
    
    echo "$server_port"
}

# Function to get server protocol
get_server_proto() {
    local server_proto
    
    # Try to get protocol from existing configuration
    if [ -f "/etc/openvpn/server.conf" ]; then
        local detected_proto=$(grep "^proto " /etc/openvpn/server.conf | awk '{print $2}')
        
        if [ -n "$detected_proto" ]; then
            echo "Detected OpenVPN protocol: $detected_proto"
            read -p "Use this protocol? (y/n): " confirm
            
            if [[ $confirm =~ ^[Yy] ]]; then
                server_proto="$detected_proto"
            fi
        fi
    fi
    
    # If not confirmed or found, ask user
    if [ -z "$server_proto" ]; then
        read -p "Enter OpenVPN protocol (udp/tcp) [default: $DEFAULT_PROTO]: " server_proto
        server_proto=${server_proto:-$DEFAULT_PROTO}
    fi
    
    echo "$server_proto"
}

# Function to generate ovpn file
generate_ovpn() {
    local client_name=$1
    local server_ip=$2
    local server_port=$3
    local server_proto=$4
    
    echo "Generating OVPN file for client: $client_name..."
    
    # Check if required files exist
    if [ ! -f "$CERT_DIR/pki/ca.crt" ]; then
        echo "ERROR: CA certificate not found at $CERT_DIR/pki/ca.crt"
        return 1
    fi
    
    if [ ! -f "$CERT_DIR/pki/issued/$client_name.crt" ]; then
        echo "ERROR: Client certificate not found at $CERT_DIR/pki/issued/$client_name.crt"
        return 1
    fi
    
    if [ ! -f "$CERT_DIR/pki/private/$client_name.key" ]; then
        echo "ERROR: Client key not found at $CERT_DIR/pki/private/$client_name.key"
        return 1
    fi
    
    # Create the ovpn file
    cat > "$OUTPUT_DIR/$client_name.ovpn" << EOF
client
dev tun
proto $server_proto
remote $server_ip $server_port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3

<ca>
$(cat "$CERT_DIR/pki/ca.crt")
</ca>
<cert>
$(cat "$CERT_DIR/pki/issued/$client_name.crt")
</cert>
<key>
$(cat "$CERT_DIR/pki/private/$client_name.key")
</key>
EOF
    
    # Ensure proper ownership of the generated file
    chown "$SUDO_USER":"$SUDO_USER" "$OUTPUT_DIR/$client_name.ovpn" 2>/dev/null || true
    
    echo "Configuration file created: $OUTPUT_DIR/$client_name.ovpn"
    return 0
}

# Main execution
list_available_clients

# Get client selection
read -p "Enter the number of the client to generate config for: " selection
clients=$(ls "$CERT_DIR/pki/issued" | grep -v "server.crt" | sed 's/.crt$//')
selected_client=$(echo "$clients" | sed -n "${selection}p")

if [ -z "$selected_client" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

echo "Selected client: $selected_client"

# Get server information
SERVER_IP=$(get_server_ip)
SERVER_PORT=$(get_server_port)
SERVER_PROTO=$(get_server_proto)

# Generate OVPN file
generate_ovpn "$selected_client" "$SERVER_IP" "$SERVER_PORT" "$SERVER_PROTO"

if [ $? -eq 0 ]; then
    echo "✅ OpenVPN client configuration generated successfully!"
    echo "File location: $OUTPUT_DIR/$selected_client.ovpn"
    echo "You can now use this file with your OpenVPN client."
else
    echo "❌ Failed to generate OpenVPN client configuration."
fi
