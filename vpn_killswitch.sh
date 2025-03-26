#!/bin/bash

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
   echo "This script must be run as root (sudo)"
   exit 1
fi

# Auto-detect interfaces and networks
EXTERNAL_IF=$(detect_external_interface)
LOCAL_SUBNET=$(detect_local_subnet)

if [ -z "$EXTERNAL_IF" ]; then
    echo "ERROR: Could not detect external network interface."
    echo "Please specify your external interface manually by editing this script."
    exit 1
fi

echo "Detected network configuration:"
echo "- External interface: $EXTERNAL_IF"
echo "- Local subnet: $LOCAL_SUBNET"
echo "- VPN interface: $VPN_INTERFACE"

# Function to enable the killswitch
enable_killswitch() {
    echo "Enabling VPN killswitch..."
    
    # Save iptables state for recovery
    iptables-save > /tmp/iptables-before-killswitch
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    
    # Set default policies - block all by default
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established and related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow local network
    iptables -A INPUT -s $LOCAL_SUBNET -j ACCEPT
    iptables -A OUTPUT -d $LOCAL_SUBNET -j ACCEPT
    
    # Allow connections to/from VPN server
    # First get the VPN server IP (from /etc/openvpn/server.conf)
    if [ -f /etc/openvpn/server.conf ]; then
        VPN_SERVER=$(grep "^remote " /etc/openvpn/server.conf | head -n1 | awk '{print $2}')
        VPN_PORT=$(grep "^port " /etc/openvpn/server.conf | head -n1 | awk '{print $2}')
        
        if [ -n "$VPN_SERVER" ] && [ -n "$VPN_PORT" ]; then
            # Allow connection to VPN server
            iptables -A OUTPUT -o $EXTERNAL_IF -d $VPN_SERVER -p udp --dport $VPN_PORT -j ACCEPT
            iptables -A INPUT -i $EXTERNAL_IF -s $VPN_SERVER -p udp --sport $VPN_PORT -j ACCEPT
            echo "Added rules for VPN server $VPN_SERVER on port $VPN_PORT"
        else
            echo "WARNING: Could not detect VPN server from config, adding general UDP/1194 rule"
            # Allow OpenVPN traffic (default port)
            iptables -A OUTPUT -o $EXTERNAL_IF -p udp --dport 1194 -j ACCEPT
            iptables -A INPUT -i $EXTERNAL_IF -p udp --sport 1194 -j ACCEPT
        fi
    else
        echo "WARNING: No OpenVPN config found, adding general UDP/1194 rule"
        # Allow OpenVPN traffic (default port)
        iptables -A OUTPUT -o $EXTERNAL_IF -p udp --dport 1194 -j ACCEPT
        iptables -A INPUT -i $EXTERNAL_IF -p udp --sport 1194 -j ACCEPT
    fi
    
    # Allow DNS queries (needed to resolve VPN server address)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --sport 53 -j ACCEPT
    
    # Allow traffic through VPN tunnel
    iptables -A INPUT -i $VPN_INTERFACE -j ACCEPT
    iptables -A OUTPUT -o $VPN_INTERFACE -j ACCEPT
    
    # Create a mark for the killswitch status
    touch $STATUS_FILE
    echo "enabled" > $STATUS_FILE
    
    echo "✅ VPN killswitch enabled. All traffic will be blocked if VPN disconnects."
    echo "   Your internet access works ONLY through the VPN now."
    echo "   To disable the killswitch, run: sudo bash $0 disable"
}

# Function to disable the killswitch
disable_killswitch() {
    echo "Disabling VPN killswitch..."
    
    # Flush all rules
    iptables -F
    iptables -X
    iptables -t nat -F
    
    # Set default policies to ACCEPT
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # If we have a saved iptables state, restore it
    if [ -f /tmp/iptables-before-killswitch ]; then
        iptables-restore < /tmp/iptables-before-killswitch
        rm /tmp/iptables-before-killswitch
        echo "Restored previous firewall rules."
    else
        echo "No previous firewall rules to restore."
    fi
    
    # Update status file
    if [ -f "$STATUS_FILE" ]; then
        echo "disabled" > $STATUS_FILE
    fi
    
    echo "✅ VPN killswitch disabled. Traffic is now flowing normally."
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
