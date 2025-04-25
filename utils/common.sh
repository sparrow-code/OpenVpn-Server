#!/bin/bash

# Common utilities for OpenVPN scripts
# This file should be sourced by other scripts

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print messages with color
log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

failure() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

# Network interface detection functions
detect_external_interface() {
    # Try to detect the interface with the default route
    DEFAULT_ROUTE_IF=$(ip -4 route show default 2>/dev/null | grep -Po '(?<=dev )(\S+)' | head -n1)
    
    # If that fails, try to find an interface with a public IP
    if [ -z "$DEFAULT_ROUTE_IF" ]; then
        for iface in $(ip -o link show 2>/dev/null | grep -v "lo" | awk -F': ' '{print $2}'); do
            # Skip virtual interfaces
            if [[ "$iface" == "tun"* ]] || [[ "$iface" == "tap"* ]] || [[ "$iface" == "docker"* ]] || [[ "$iface" == "br-"* ]] || [[ "$iface" == "veth"* ]]; then
                continue
            fi
            
            # Check if interface has an IP
            IP=$(ip -4 addr show dev "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
            if [ -n "$IP" ]; then
                DEFAULT_ROUTE_IF="$iface"
                break
            fi
        done
    fi
    
    echo "$DEFAULT_ROUTE_IF"
}

# Detect OpenVPN interface
detect_vpn_interface() {
    VPN_IF=$(ip -o link show 2>/dev/null | grep -oP '(?<=\d: )(tun\d+)|(tap\d+)' | head -n 1)
    echo "$VPN_IF"
}

# Detect local subnet
detect_local_subnet() {
    ip -o -f inet addr show 2>/dev/null | grep -v "127.0.0.1" | awk '{print $4}' | head -n1
}

# Function to check if OpenVPN is running
check_openvpn_running() {
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
            return 0  # Running
        fi
    elif pgrep -x "openvpn" &>/dev/null; then
        return 0  # Running
    fi
    return 1  # Not running
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        warn "Please run with sudo or as root user"
        exit 1
    fi
}

# Function to display a header
show_header() {
    local title="$1"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BOLD}${PURPLE}           $title${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# Function to confirm an action
confirm_action() {
    local prompt="$1"
    local response
    
    read -p "$prompt (y/n): " response
    case "$response" in
        [Yy]* ) return 0 ;;
        * ) return 1 ;;
    esac
}

# Create a temporary fix script with proper header
create_fix_script() {
    local script_path="$1"
    local description="$2"
    
    echo "#!/bin/bash" > "$script_path"
    echo "# Auto-generated script to $description" >> "$script_path"
    echo "echo 'Applying fixes to $description...'" >> "$script_path"
    
    # Make it executable
    chmod +x "$script_path"
    
    return 0
}

# Gets the OpenVPN server config parameters
get_server_config_param() {
    local param_name="$1"
    local config_file="/etc/openvpn/server.conf"
    
    if [ -f "$config_file" ]; then
        grep "^$param_name " "$config_file" | awk '{print $2}'
    fi
}

# Function to backup OpenVPN server config
backup_server_config() {
    local backup_suffix="$1"
    if [ -z "$backup_suffix" ]; then
        backup_suffix=$(date +%Y%m%d-%H%M%S)
    fi
    
    if [ -f /etc/openvpn/server.conf ]; then
        local backup_file="/etc/openvpn/server.conf.$backup_suffix"
        cp /etc/openvpn/server.conf "$backup_file"
        success "Backup created: $backup_file"
        return 0
    else
        error "Server configuration file not found at /etc/openvpn/server.conf"
        return 1
    fi
}

# Function to switch OpenVPN protocol
switch_protocol() {
    local target_protocol="$1"
    local current_port="$2"
    local new_port="$3"
    
    if [ "$target_protocol" == "tcp" ]; then
        current_protocol="udp"
    else
        current_protocol="tcp"
    fi
    
    # Backup original configuration
    backup_server_config "${current_protocol}-$(date +%Y%m%d-%H%M%S)"

    # Update the configuration file
    log "Updating server configuration to use $target_protocol protocol..."
    sed -i "s/^proto $current_protocol/proto $target_protocol/" /etc/openvpn/server.conf
    if ! grep -q "^proto $target_protocol" /etc/openvpn/server.conf; then
        # If the protocol line wasn't updated properly, add it
        sed -i '/^port/i proto '"$target_protocol" /etc/openvpn/server.conf
    fi

    # Update port if different
    if [ -n "$new_port" ] && [ "$new_port" != "$current_port" ]; then
        sed -i "s/^port .*/port $new_port/" /etc/openvpn/server.conf
        success "Port updated from $current_port to $new_port"
    fi

    # Handle protocol-specific settings
    if [ "$target_protocol" == "tcp" ]; then
        # Add TCP-specific options if they don't exist
        if ! grep -q "tcp-nodelay" /etc/openvpn/server.conf; then
            echo "# TCP specific settings" >> /etc/openvpn/server.conf
            echo "tcp-nodelay" >> /etc/openvpn/server.conf
            success "Added TCP-specific optimization settings"
        fi
    else # UDP
        # Remove TCP-specific options if they exist
        if grep -q "tcp-nodelay" /etc/openvpn/server.conf; then
            sed -i '/tcp-nodelay/d' /etc/openvpn/server.conf
            success "Removed TCP-specific settings"
        fi
    fi
    
    return 0
}

# Function to update firewall for protocol change
update_firewall_for_protocol() {
    local protocol="$1"
    local port="$2"
    
    log "Updating firewall rules for $protocol protocol on port $port..."
    
    # Check and update firewall if needed
    if command -v ufw > /dev/null; then
        if ufw status | grep -q "active"; then
            log "UFW firewall detected. Adding $protocol rules..."
            ufw allow $port/$protocol
            success "UFW rule added for port $port/$protocol"
        fi
    elif command -v firewall-cmd > /dev/null; then
        if firewall-cmd --state | grep -q "running"; then
            log "FirewallD detected. Adding $protocol rules..."
            firewall-cmd --zone=public --add-port=$port/$protocol --permanent
            firewall-cmd --reload
            success "FirewallD rule added for port $port/$protocol"
        fi
    else
        warn "No active firewall manager detected (UFW or FirewallD)."
        info "Consider installing and enabling UFW for easier firewall management."
        echo -e "  Install with: ${CYAN}sudo apt update && sudo apt install -y ufw${NC}"
        echo -e "  Enable with: ${CYAN}sudo ufw --force enable${NC}"
        echo -e "  Add rule with: ${CYAN}sudo ufw allow $port/$protocol${NC}"
    fi
}

# Function to verify OpenVPN is running with specific protocol
verify_openvpn_protocol() {
    local protocol="$1"
    local port="$2"
    
    log "Verifying OpenVPN is running with new settings..."
    sleep 2
    if pgrep -x "openvpn" > /dev/null; then
        RUNNING_PROTO=$(ss -tulpn | grep -i "openvpn" | grep -i "$port" | grep -i "$protocol")
        if [ -n "$RUNNING_PROTO" ]; then
            success "OpenVPN is running with $protocol protocol on port $port"
            return 0
        else
            warn "OpenVPN is running but couldn't verify the protocol and port."
            log "Current listening ports:"
            ss -tulpn | grep -i "openvpn"
            return 1
        fi
    else
        error "OpenVPN service is not running. Check logs with: journalctl -u openvpn@server"
        return 2
    fi
}

# Function to restart OpenVPN service
restart_openvpn() {
    log "Restarting OpenVPN service..."
    systemctl restart openvpn@server || systemctl restart openvpn
    if [ $? -eq 0 ]; then
        success "OpenVPN service restarted successfully."
        return 0
    else
        error "Failed to restart OpenVPN service. Check with: systemctl status openvpn@server"
        return 1
    fi
}

# Function to list client certificates
list_client_certificates() {
    local easyrsa_dir="$HOME/easy-rsa"
    
    if [ ! -d "$easyrsa_dir/pki/issued" ]; then
        warn "No certificates directory found at $easyrsa_dir/pki/issued"
        return 1
    fi
    
    log "Available client certificates:"
    echo "------------------------------"
    
    # List all non-server certificates
    local clients=$(ls "$easyrsa_dir/pki/issued" | grep -v "server.crt" | sed 's/.crt$//')
    
    if [ -z "$clients" ]; then
        info "No client certificates found."
        return 0
    fi
    
    local i=1
    for client in $clients; do
        echo "$i) $client"
        i=$((i+1))
    done
    
    echo ""
    return 0
}

# Function to check for client connection
is_client_connected() {
    local client_ip="$1"
    
    if [ -f /etc/openvpn/openvpn-status.log ]; then
        if grep -q "$client_ip" /etc/openvpn/openvpn-status.log; then
            return 0  # Connected
        fi
    fi
    return 1  # Not connected
}

# Function to get public IP
get_public_ip() {
    # Try multiple services in case one fails
    if command -v curl &> /dev/null; then
        curl -s -4 https://api.ipify.org 2>/dev/null || 
        curl -s -4 https://ipv4.icanhazip.com 2>/dev/null || 
        curl -s -4 https://ipinfo.io/ip 2>/dev/null
    elif command -v wget &> /dev/null; then
        wget -qO- -4 https://api.ipify.org 2>/dev/null || 
        wget -qO- -4 https://ipv4.icanhazip.com 2>/dev/null || 
        wget -qO- -4 https://ipinfo.io/ip 2>/dev/null
    else
        # Fallback method if curl and wget are not available
        hostname -I | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
    fi
}
