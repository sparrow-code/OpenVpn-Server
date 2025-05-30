#!/bin/bash

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# VPN Killswitch Script
# ---------------------
# This script implements a firewall-based VPN killswitch that prevents IP leakage
# by blocking all internet traffic if the VPN connection drops unexpectedly.
#
# Usage:
#   sudo bash vpn_killswitch.sh enable - Enable the killswitch
#   sudo bash vpn_killswitch.sh disable - Disable the killswitch
#   sudo bash vpn_killswitch.sh status - Check killswitch status

# Configuration
# Adjust these variables to match your system
VPN_INTERFACE="tun0"                # Default VPN interface
STATUS_FILE="/tmp/vpn_killswitch"   # File to track killswitch status

# Function to detect the primary external interface
detect_external_interface() {
    ip -4 route show default | grep -Po '(?<=dev )(\S+)' | head -n1
}

# Function to detect the local subnet
detect_local_subnet() {
    ip -o -f inet addr show | grep -v "127.0.0.1" | awk '{print $4}' | head -n1
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}This script must be run as root (sudo)${NC}"
  exit 1
fi

# Auto-detect interfaces and networks
EXTERNAL_IF=$(detect_external_interface)
LOCAL_SUBNET=$(detect_local_subnet)

if [ -z "$EXTERNAL_IF" ]; then
    echo -e "${RED}ERROR: Could not detect external network interface.${NC}"
    echo -e "${YELLOW}Please specify your external interface manually by editing this script.${NC}"
    exit 1
fi

echo -e "${BLUE}Detected network configuration:${NC}"
echo -e "- External interface: ${GREEN}$EXTERNAL_IF${NC}"
echo -e "- Local subnet: ${GREEN}$LOCAL_SUBNET${NC}"
echo -e "- VPN interface: ${GREEN}$VPN_INTERFACE${NC}"

# Function to enable the killswitch
enable_killswitch() {
    echo -e "${BLUE}Enabling VPN killswitch...${NC}"
    
    # Check if UFW is installed and active
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}UFW is not installed. Installing UFW...${NC}"
        apt update
        apt install -y ufw
    fi
    
    if ! ufw status | grep -q "Status: active"; then
        echo -e "${RED}UFW is not active. Enabling UFW...${NC}"
        ufw --force enable
    fi
    
    # Backup current UFW rules if possible
    echo -e "${YELLOW}Backing up current UFW rules...${NC}"
    ufw status verbose > /tmp/ufw-before-killswitch-$(date +"%Y%m%d-%H%M%S").backup
    
    # Reset UFW to default state for killswitch setup
    ufw reset --force
    
    # Set default policies - block all by default
    ufw default deny incoming
    ufw default deny outgoing
    
    # Allow loopback
    ufw allow in on lo
    ufw allow out on lo
    
    # Allow established and related connections
    ufw allow in proto tcp from any to any established
    ufw allow out proto tcp from any to any established
    
    # Allow local network
    ufw allow in from $LOCAL_SUBNET
    ufw allow out to $LOCAL_SUBNET
    
    # Allow connections to/from VPN server
    # First get the VPN server IP (from /etc/openvpn/server.conf)
    if [ -f /etc/openvpn/server.conf ]; then
        VPN_SERVER=$(grep "^remote " /etc/openvpn/server.conf | head -n1 | awk '{print $2}')
        VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | head -n1 | awk '{print $2}')
        
        if [ -n "$VPN_SERVER" ] && [ -n "$VPN_PORT" ]; then
            # Allow connection to VPN server
            ufw allow out to $VPN_SERVER port $VPN_PORT proto udp
            ufw allow in from $VPN_SERVER port $VPN_PORT proto udp
            echo "Added rules for VPN server $VPN_SERVER on port $VPN_PORT"
        else
            echo "WARNING: Could not detect VPN server from config, adding general UDP/1194 rule"
            # Allow OpenVPN traffic (default port)
            ufw allow out to any port 1194 proto udp
            ufw allow in from any port 1194 proto udp
        fi
    else
        echo "WARNING: No OpenVPN config found, adding general UDP/1194 rule"
        # Allow OpenVPN traffic (default port)
        ufw allow out to any port 1194 proto udp
        ufw allow in from any port 1194 proto udp
    fi
    
    # Allow DNS queries (needed to resolve VPN server address)
    ufw allow out to any port 53 proto udp
    ufw allow in from any port 53 proto udp
    ufw allow out to any port 53 proto tcp
    ufw allow in from any port 53 proto tcp
    
    # Allow traffic through VPN tunnel
    ufw allow in on $VPN_INTERFACE
    ufw allow out on $VPN_INTERFACE
    
    # Reload UFW to apply changes
    ufw reload
    
    # Create a mark for the killswitch status
    touch $STATUS_FILE
    echo "enabled" > $STATUS_FILE
    
    echo -e "${GREEN}✅ VPN killswitch enabled. All traffic will be blocked if VPN disconnects.${NC}"
    echo -e "${YELLOW}   Your internet access works ONLY through the VPN now.${NC}"
    echo -e "${CYAN}   To disable the killswitch, run: sudo bash $0 disable${NC}"
}

# Function to disable the killswitch
disable_killswitch() {
    echo -e "${BLUE}Disabling VPN killswitch...${NC}"
    
    # Check if UFW is installed and active
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}UFW is not installed. Cannot disable killswitch.${NC}"
        exit 1
    fi
    
    # Reset UFW rules to default
    ufw reset --force
    
    # Set default policies to allow
    ufw default allow incoming
    ufw default allow outgoing
    
    # Reload UFW to apply changes
    ufw reload
    
    # Update status file
    if [ -f "$STATUS_FILE" ]; then
        echo "disabled" > $STATUS_FILE
    fi
    
    echo -e "${GREEN}✅ VPN killswitch disabled. Traffic is now flowing normally.${NC}"
    echo "   ⚠️ WARNING: Your real IP address may be exposed if the VPN disconnects."
}

# Function to check killswitch status
check_status() {
    if [ -f "$STATUS_FILE" ] && [ "$(cat $STATUS_FILE)" == "enabled" ]; then
        echo "VPN killswitch is ENABLED."
        echo "All traffic is being routed through the VPN only."
        
        # Check if the VPN interface is actually up
        if ip link show $VPN_INTERFACE &>/dev/null; then
            echo "✅ VPN interface $VPN_INTERFACE is up"
            
            # Check if traffic is flowing through VPN
            if ping -c 1 -I $VPN_INTERFACE 8.8.8.8 &>/dev/null; then
                echo "✅ Traffic is flowing through the VPN"
            else
                echo "❌ No traffic flowing through VPN. Internet may be blocked."
            fi
        else
            echo "❌ VPN interface $VPN_INTERFACE is down"
            echo "❌ Internet access is likely BLOCKED due to killswitch"
        fi
    elif [ -f "$STATUS_FILE" ] && [ "$(cat $STATUS_FILE)" == "disabled" ]; then
        echo "VPN killswitch is DISABLED."
        echo "⚠️ Traffic may leak outside the VPN if connection drops."
    else
        echo "VPN killswitch status is UNKNOWN."
        echo "Run 'sudo bash $0 enable' to enable it."
    fi
}

# Function to display usage information
show_usage() {
    echo "Usage: $0 {enable|disable|status}"
    echo ""
    echo "Commands:"
    echo "  enable  - Enable the VPN killswitch (blocks traffic when VPN is down)"
    echo "  disable - Disable the VPN killswitch"
    echo "  status  - Show current killswitch status"
    echo ""
    echo "This script prevents IP leakage by blocking all internet traffic"
    echo "when the VPN connection drops unexpectedly."
}

# Function to set up VPN Killswitch on system startup
setup_autostart() {
    echo "Setting up VPN killswitch to start automatically..."
    
    # Create systemd service file
    cat > /etc/systemd/system/vpn-killswitch.service << EOF
[Unit]
Description=VPN Killswitch Service
After=network.target

[Service]
Type=oneshot
ExecStart=$(readlink -f $0) enable
RemainAfterExit=true
ExecStop=$(readlink -f $0) disable

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable vpn-killswitch.service
    systemctl start vpn-killswitch.service
    
    echo "✅ VPN killswitch will automatically start on system boot."
    echo "   To control it manually: sudo systemctl {start|stop} vpn-killswitch"
}

# Main script execution
case "$1" in
    enable)
        enable_killswitch
        ;;
    disable)
        disable_killswitch
        ;;
    status)
        check_status
        ;;
    autostart)
        setup_autostart
        ;;
    *)
        show_usage
        ;;
esac

exit 0
