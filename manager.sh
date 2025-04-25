#!/bin/bash
# OpenVPN Management Script
# This script provides a standardized interface for the ISP management system
# to interact with the OpenVPN server installation.

# Set strict error handling
set -e

# Source utility functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/utils/common.sh" ]]; then
  source "${SCRIPT_DIR}/utils/common.sh"
fi

# Configuration paths
BASE_DIR="${SCRIPT_DIR}"
EASY_RSA_DIR="/root/easy-rsa"
PKI_DIR="${EASY_RSA_DIR}/pki"
CLIENT_CONFIG_DIR="/home/sdworlld/client-configs"
CLIENTS_DIR="${CLIENT_CONFIG_DIR}"
BASE_CONFIG="${CLIENT_CONFIG_DIR}/base.conf"

# Function to display usage information
usage() {
  echo "Usage: $0 command [options]"
  echo
  echo "Commands:"
  echo "  create-client         Create a new OpenVPN client"
  echo "  revoke-client         Revoke a client certificate"
  echo "  list-clients          List all clients"
  echo "  get-client            Get details for a specific client"
  echo "  server-status         Check OpenVPN server status"
  echo "  server-restart        Restart the OpenVPN server"
  echo
  echo "Options:"
  echo "  --name=NAME           Client name (required for client operations)"
  echo "  --generate_ovpn=yes   Generate .ovpn file (for create-client)"
  echo "  --ip=IP               Server IP to use (optional)"
  echo "  --port=PORT           Server port to use (optional)"
  echo "  --protocol=PROTOCOL   Protocol to use [tcp|udp] (optional)"
  echo
  exit 1
}

# Function to parse command line arguments
parse_args() {
  for i in "$@"; do
    case $i in
      --name=*)
        CLIENT_NAME="${i#*=}"
        shift
        ;;
      --generate_ovpn=*)
        GENERATE_OVPN="${i#*=}"
        shift
        ;;
      --ip=*)
        SERVER_IP="${i#*=}"
        shift
        ;;
      --port=*)
        SERVER_PORT="${i#*=}"
        shift
        ;;
      --protocol=*)
        PROTOCOL="${i#*=}"
        shift
        ;;
      *)
        # Unknown option
        ;;
    esac
  done
}

# Function to create a new client
create_client() {
  if [[ -z "${CLIENT_NAME}" ]]; then
    echo "Error: Client name is required"
    usage
    exit 1
  fi

  echo "==================================================="
  echo "           OpenVPN Management System"
  echo "==================================================="
  echo
  echo "Create New OpenVPN Client"
  echo
  echo "Enter name for the new client: ${CLIENT_NAME}"
  echo "Generating new certificate for ${CLIENT_NAME}..."

  # Change to Easy-RSA directory
  cd "${EASY_RSA_DIR}"

  # Generate certificate
  ./easyrsa build-client-full "${CLIENT_NAME}" nopass

  echo
  echo "Certificate for ${CLIENT_NAME} generated successfully."
  echo

  # Create client directory
  mkdir -p "${CLIENTS_DIR}/${CLIENT_NAME}"

  # Copy certificates to client directory
  cp "${PKI_DIR}/ca.crt" "${CLIENTS_DIR}/${CLIENT_NAME}/"
  cp "${PKI_DIR}/issued/${CLIENT_NAME}.crt" "${CLIENTS_DIR}/${CLIENT_NAME}/"
  cp "${PKI_DIR}/private/${CLIENT_NAME}.key" "${CLIENTS_DIR}/${CLIENT_NAME}/"

  echo "Client certificates created successfully!"
  echo "Certificate files are in: ${CLIENTS_DIR}/${CLIENT_NAME}/"
  echo "File listing:"
  ls -la "${CLIENTS_DIR}/${CLIENT_NAME}/"

  # Generate OVPN file if requested
  if [[ "${GENERATE_OVPN}" == "yes" ]]; then
    echo "Do you want to generate an .ovpn file for this client? (y/n): y"
    echo "Gathering server information for OVPN file..."
    
    # Get server IP
    if [[ -z "${SERVER_IP}" ]]; then
      echo "Attempting to detect your public IPv4 address..."
      SERVER_IP=$(curl -s https://api.ipify.org)
      echo "Detected server IP: ${SERVER_IP}"
      echo "Is this your server's public IP? (y/n): y"
    fi
    
    # Get port and protocol
    if [[ -z "${SERVER_PORT}" ]]; then
      SERVER_PORT="1194"
      echo "Detected OpenVPN port: ${SERVER_PORT}"
    fi
    
    if [[ -z "${PROTOCOL}" ]]; then
      PROTOCOL="tcp"
      echo "Detected OpenVPN protocol: ${PROTOCOL}"
    fi
    
    # Generate the OVPN file
    echo "Generating OVPN file for client: ${CLIENT_NAME}..."
    echo "Using: IP=${SERVER_IP}, PORT=${SERVER_PORT}, PROTOCOL=${PROTOCOL}"
    
    # Define the base configuration directly
    cat > "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn" << EOF
client
dev tun
# The proto and remote lines will be updated by sed below
proto ${PROTOCOL}
remote ${SERVER_IP} ${SERVER_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
EOF
    echo "<ca>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    cat "${CLIENTS_DIR}/${CLIENT_NAME}/ca.crt" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "</ca>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "<cert>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    # Use cat instead of sed for the client cert to ensure the whole content is included
    cat "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.crt" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "</cert>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "<key>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    cat "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.key" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "</key>" >> "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    
    # Server details are already set with variables in the OVPN file
    
    echo "OVPN file created successfully: ${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    echo "File permissions:"
    ls -l "${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
  fi
}

# Function to revoke a client
revoke_client() {
  if [[ -z "${CLIENT_NAME}" ]]; then
    echo "Error: Client name is required"
    usage
    exit 1
  fi

  echo "Revoking certificate for client: ${CLIENT_NAME}"
  
  # Change to Easy-RSA directory
  cd "${EASY_RSA_DIR}"
  
  # Revoke certificate
  ./easyrsa revoke "${CLIENT_NAME}"
  
  # Generate CRL
  ./easyrsa gen-crl
  
  # Copy CRL to OpenVPN directory
  cp "${PKI_DIR}/crl.pem" /etc/openvpn/
  
  echo "Certificate for client ${CLIENT_NAME} has been revoked"
  echo "CRL has been updated"
  
  # Restart OpenVPN server to apply CRL
  systemctl restart openvpn@server
  
  echo "OpenVPN server restarted to apply changes"
}

# Function to list clients
list_clients() {
  echo "==================================================="
  echo "           OpenVPN Management System"
  echo "==================================================="
  echo
  echo "List of VPN Clients"
  echo
  
  # Change to Easy-RSA directory
  cd "${EASY_RSA_DIR}"
  
  # Get list of certificates
  if [[ -d "${PKI_DIR}/issued" ]]; then
    echo "Active clients:"
    for cert in "${PKI_DIR}/issued/"*.crt; do
      if [[ -f "$cert" ]]; then
        client_name=$(basename "$cert" .crt)
        if [[ "$client_name" != "server" ]]; then
          expiry=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)
          echo "- ${client_name} (Expires: ${expiry})"
        fi
      fi
    done
  else
    echo "No clients found or PKI directory not initialized"
  fi
  
  # List revoked clients if CRL exists
  if [[ -f "${PKI_DIR}/crl.pem" ]]; then
    echo
    echo "Revoked clients:"
    openssl crl -text -noout -in "${PKI_DIR}/crl.pem" | grep "Serial Number" | awk '{print $3}'
  fi
}

# Function to get client details
get_client() {
  if [[ -z "${CLIENT_NAME}" ]]; then
    echo "Error: Client name is required"
    usage
    exit 1
  fi
  
  echo "==================================================="
  echo "           OpenVPN Management System"
  echo "==================================================="
  echo
  echo "Client Details: ${CLIENT_NAME}"
  echo
  
  # Check if certificate exists
  cert_file="${PKI_DIR}/issued/${CLIENT_NAME}.crt"
  if [[ -f "${cert_file}" ]]; then
    echo "Certificate information:"
    openssl x509 -text -noout -in "${cert_file}"
    
    # Check for OVPN file
    ovpn_file="${CLIENTS_DIR}/${CLIENT_NAME}/${CLIENT_NAME}.ovpn"
    if [[ -f "${ovpn_file}" ]]; then
      echo
      echo "OVPN file exists: ${ovpn_file}"
      echo "File size: $(du -h "${ovpn_file}" | cut -f1)"
      echo "Created: $(stat -c %y "${ovpn_file}")"
    else
      echo
      echo "OVPN file not found"
    fi
  else
    echo "Error: Client certificate not found for ${CLIENT_NAME}"
    exit 1
  fi
}

# Function to check server status
server_status() {
  echo "==================================================="
  echo "           OpenVPN Management System"
  echo "==================================================="
  echo
  echo "OpenVPN Server Status"
  echo
  
  # Check if OpenVPN service is running
  systemctl status openvpn@server --no-pager
  
  echo
  echo "Connected clients:"
  if [[ -f /var/log/openvpn/status.log ]]; then
    grep "CLIENT_LIST" /var/log/openvpn/status.log | awk -F, '{print $2 " - " $3 " (connected since " $5 ")"}'
  else
    echo "Status log not found"
  fi
  
  echo
  echo "Server configuration:"
  echo "Protocol: $(grep -E "^proto " /etc/openvpn/server.conf | awk '{print $2}')"
  echo "Port: $(grep -E "^port " /etc/openvpn/server.conf | awk '{print $2}')"
  echo "Cipher: $(grep -E "^cipher " /etc/openvpn/server.conf | awk '{print $2}')"
  
  # Check for TUN/TAP interface
  echo
  echo "Network interfaces:"
  ip addr show tun0 2>/dev/null || echo "TUN interface not active"
}

# Function to restart server
server_restart() {
  echo "==================================================="
  echo "           OpenVPN Management System"
  echo "==================================================="
  echo
  echo "Restarting OpenVPN Server"
  echo
  
  # Restart OpenVPN service
  systemctl restart openvpn@server
  
  # Wait a moment for the service to start
  sleep 2
  
  # Check status
  if systemctl is-active --quiet openvpn@server; then
    echo "OpenVPN server restarted successfully"
  else
    echo "Failed to restart OpenVPN server"
    echo "Server status:"
    systemctl status openvpn@server --no-pager
    exit 1
  fi
}

# Main script execution
if [[ $# -lt 1 ]]; then
  usage
fi

# Parse command line arguments
parse_args "$@"

# Execute command
case "$1" in
  create-client)
    create_client
    ;;
  revoke-client)
    revoke_client
    ;;
  list-clients)
    list_clients
    ;;
  get-client)
    get_client
    ;;
  server-status)
    server_status
    ;;
  server-restart)
    server_restart
    ;;
  *)
    echo "Error: Unknown command '$1'"
    usage
    ;;
esac

exit 0
