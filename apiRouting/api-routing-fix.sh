#!/bin/bash
# API Routing Quick Fix Script
# This script fixes common issues with the API routing setup

# Exit on any error
set -e

# Fixed Configuration Variables
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
MIKROTIK_VPN_IP="10.8.0.6"
API_TARGET="api.ipify.org"
ROUTING_TABLE="apiroutes"
ROUTING_TABLE_ID="200"
LOG_DIR="/var/log/api_routing"
SCRIPT_DIR="/etc/openvpn/scripts"

echo "===== API Routing Quick Fix Script ====="
echo "This script will fix common issues with API routing"
echo "Date: $(date)"
echo ""

# Create necessary directories
mkdir -p $LOG_DIR $SCRIPT_DIR /etc/openvpn

# Step 1: Get current API IP
echo "Step 1: Resolving API target..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_TARGET_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "$API_TARGET resolves to $API_TARGET_IP"

# Step 2: Create active_routers file if missing
echo "Step 2: Setting up active_routers file..."
if [ ! -f "/etc/openvpn/active_routers" ]; then
    echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
    echo "Created active_routers file with MikroTik IP: $MIKROTIK_VPN_IP"
else 
    # Ensure our MikroTik IP is in the file
    grep -q "$MIKROTIK_VPN_IP" /etc/openvpn/active_routers || echo "$MIKROTIK_VPN_IP" >> /etc/openvpn/active_routers
    echo "Updated active_routers file"
fi

# Step 3: Create or update the learn-address script
echo "Step 3: Creating/updating learn-address script..."
cat > $SCRIPT_DIR/learn-address.sh << EOF
#!/bin/bash

# Learn-address hook for OpenVPN
# Arguments: operation(add/update/delete) client_ip common_name

ACTION=\$1
CLIENT_IP=\$2
COMMON_NAME=\$3

LOG_FILE="$LOG_DIR/learn-address.log"
ROUTERS_FILE="/etc/openvpn/active_routers"
API_TARGET="$API_TARGET"
ROUTING_TABLE="$ROUTING_TABLE"

# Log function
log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

# Initialize log file if it doesn't exist
mkdir -p "\$(dirname "\$LOG_FILE")"
touch "\$LOG_FILE"

log "Called with: \$ACTION \$CLIENT_IP \$COMMON_NAME"

# Only process MikroTik clients
if [[ "\$COMMON_NAME" == "mikrotik_"* ]]; then
    log "Processing MikroTik router: \$COMMON_NAME (\$CLIENT_IP)"
    
    case "\$ACTION" in
        add|update)
            # Add to active routers list
            echo "\$CLIENT_IP" >> "\$ROUTERS_FILE"
            sort -u "\$ROUTERS_FILE" -o "\$ROUTERS_FILE"
            log "Added \$CLIENT_IP to active routers list"
            
            # Add route in the API routing table
            ip route add default via "\$CLIENT_IP" table "\$ROUTING_TABLE" metric 100 2>/dev/null || \\
                ip route change default via "\$CLIENT_IP" table "\$ROUTING_TABLE" metric 100
            log "Updated route via \$CLIENT_IP in \$ROUTING_TABLE table"
            
            # Get API IP address
            API_IP=\$(host -t A \$API_TARGET | grep "has address" | head -n1 | awk '{print \$NF}')
            if [ -n "\$API_IP" ]; then
                # Add specific route for API IP
                ip route replace \$API_IP/32 via "\$CLIENT_IP" table "\$ROUTING_TABLE"
                
                # Ensure rules exist for both domain and IP
                ip rule show | grep -q "to \$API_TARGET lookup \$ROUTING_TABLE" || \\
                    ip rule add to "\$API_TARGET" lookup "\$ROUTING_TABLE"
                ip rule show | grep -q "to \$API_IP lookup \$ROUTING_TABLE" || \\
                    ip rule add to "\$API_IP" lookup "\$ROUTING_TABLE"
                
                log "Added rules and routes for \$API_TARGET (\$API_IP)"
            fi
            
            # Flush routing cache to apply changes
            ip route flush cache
            log "Flushed routing cache"
            ;;
            
        delete)
            # Remove from active routers list
            if [ -f "\$ROUTERS_FILE" ]; then
                grep -v "^\$CLIENT_IP$" "\$ROUTERS_FILE" > "\${ROUTERS_FILE}.tmp"
                mv "\${ROUTERS_FILE}.tmp" "\$ROUTERS_FILE"
                log "Removed \$CLIENT_IP from active routers list"
                
                # Remove the route from the API routing table
                ip route del default via "\$CLIENT_IP" table "\$ROUTING_TABLE" 2>/dev/null || true
                log "Removed route via \$CLIENT_IP from \$ROUTING_TABLE table"
                
                # Flush routing cache to apply changes
                ip route flush cache
                log "Flushed routing cache"
            fi
            ;;
    esac
    
    # Output current active routers for debugging
    ACTIVE_ROUTERS=\$(cat "\$ROUTERS_FILE" 2>/dev/null || echo "None")
    log "Current active routers: \$ACTIVE_ROUTERS"
fi

exit 0
EOF

chmod +x $SCRIPT_DIR/learn-address.sh
echo "Learn-address script updated"

# Step 4: Ensure routing table exists
echo "Step 4: Setting up routing table..."
grep -q "$ROUTING_TABLE_ID $ROUTING_TABLE" /etc/iproute2/rt_tables || echo "$ROUTING_TABLE_ID $ROUTING_TABLE" >> /etc/iproute2/rt_tables

# Step 5: Set up API routing
echo "Step 5: Setting up API routing rules..."
# Remove any existing rules
ip rule show | grep -E "lookup $ROUTING_TABLE" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done

# Add new rules
ip rule add to $API_TARGET lookup $ROUTING_TABLE
ip rule add to $API_TARGET_IP lookup $ROUTING_TABLE

# Add route in the table
ip route replace $API_TARGET_IP/32 via $MIKROTIK_VPN_IP table $ROUTING_TABLE

# Step 6: Configure NAT
echo "Step 6: Configuring NAT settings..."
iptables -t nat -I POSTROUTING -d $API_TARGET_IP -j ACCEPT
iptables -t nat -I POSTROUTING -s $MIKROTIK_VPN_IP -j ACCEPT

# Step 7: Flush routing cache
echo "Step 7: Flushing routing cache..."
ip route flush cache

# Step 8: Update OpenVPN server.conf if needed
echo "Step 8: Checking OpenVPN configuration..."
if ! grep -q "learn-address $SCRIPT_DIR/learn-address.sh" /etc/openvpn/server.conf; then
    echo "Updating OpenVPN server configuration..."
    cat >> /etc/openvpn/server.conf << EOF

# API Routing Configuration
script-security 2
learn-address $SCRIPT_DIR/learn-address.sh
client-config-dir /etc/openvpn/ccd

EOF
    echo "OpenVPN configuration updated. You need to restart OpenVPN."
    echo "Run: systemctl restart openvpn"
else
    echo "OpenVPN configuration already has learn-address script."
fi

# Step 9: Generate MikroTik router configuration commands
echo "Step 9: Generating MikroTik router configuration..."
cat > mikrotik_commands.txt << EOF
# MikroTik Router Commands for API Routing
# Apply these commands on your MikroTik router

# 1. Ensure IP forwarding is enabled
/ip forward set enabled=yes

# 2. Add specific route for api.ipify.org
/ip route add dst-address=$API_TARGET_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# 3. Set up NAT so traffic appears from MikroTik's public IP
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_TARGET_IP action=masquerade comment="NAT for API traffic"

# 4. Set up DNS
/ip dns static add name=$API_TARGET address=$API_TARGET_IP
EOF

echo "MikroTik router configuration has been saved to mikrotik_commands.txt"

# Step 10: Verify the setup
echo "Step 10: Verifying setup..."
echo "Active routers:"
cat /etc/openvpn/active_routers
echo ""

echo "Routing table:"
ip route show table $ROUTING_TABLE || echo "Routing table is empty!"
echo ""

echo "Routing rules:"
ip rule show | grep -E "(api|$API_TARGET_IP)"
echo ""

echo -e "\n===== Quick Fix Complete ====="
echo "Run a test with:"
echo "curl http://api.ipify.org?format=json"
echo ""
echo "If you still have issues, try the alternative approach in the troubleshooting guide."
