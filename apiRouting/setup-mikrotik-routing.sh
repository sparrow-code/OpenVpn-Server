#!/bin/bash
# MikroTik Router API Routing Setup Script
# This script configures both VPN server and MikroTik router for proper API routing

# Exit on any error
set -e

# Fixed Configuration Variables - Only these will not change
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"

# Dynamic Configuration Variables
API_TARGET="api.ipify.org"
ROUTERS_FILE="/etc/openvpn/active_routers"

echo "===== MikroTik API Routing Setup ====="

# Step 1: Check if any MikroTik router is connected to VPN
echo "Step 1: Checking for connected MikroTik routers..."
if [ ! -f "$ROUTERS_FILE" ] || [ ! -s "$ROUTERS_FILE" ]; then
    echo "Error: No active routers found in $ROUTERS_FILE"
    echo "Please ensure at least one MikroTik router is connected to the VPN"
    exit 1
fi

# Get the first available MikroTik router IP from active_routers file
MIKROTIK_VPN_IP=$(head -1 "$ROUTERS_FILE")
if [ -z "$MIKROTIK_VPN_IP" ]; then
    echo "Error: Could not determine MikroTik VPN IP"
    exit 1
fi

echo "Using MikroTik router with VPN IP: $MIKROTIK_VPN_IP"

# Verify router is reachable
ping -c 3 $MIKROTIK_VPN_IP > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Warning: Cannot reach MikroTik router at $MIKROTIK_VPN_IP"
    echo "Router may be listed in active_routers but not currently reachable"
    echo -n "Do you want to continue anyway? [y/N] "
    read continue_setup
    if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
        echo "Setup aborted."
        exit 1
    fi
fi

# Step 2: Dynamically resolve the API target
echo "Step 2: Resolving API target..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_TARGET_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "$API_TARGET resolves to $API_TARGET_IP"

# Step 3: Configure VPN server routing table
echo "Step 3: Setting up VPN server routing..."
echo "Ensuring routing table exists..."
grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables

echo "Adding route for $API_TARGET via MikroTik router..."
ip route replace $API_TARGET_IP/32 via $MIKROTIK_VPN_IP table apiroutes

echo "Setting up routing rule..."
ip rule show | grep -q "to $API_TARGET lookup apiroutes" && ip rule del to $API_TARGET lookup apiroutes
ip rule add to $API_TARGET lookup apiroutes

echo "Ensuring domain-based routing (in case IP changes)..."
ip rule show | grep -q "to $API_TARGET_IP lookup apiroutes" && ip rule del to $API_TARGET_IP lookup apiroutes
ip rule add to $API_TARGET_IP lookup apiroutes

echo "Flushing routing cache..."
ip route flush cache

# Step 4: Configure source NAT to ensure requests come from MikroTik
echo "Step 4: Setting up NAT for MikroTik router..."

# Remove any existing rules for clarity
iptables -t nat -S POSTROUTING | grep -E "ACCEPT.*-d $API_TARGET_IP" | while read rule; do
    modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
    iptables -t nat $modified_rule
done

# Add new rule
iptables -t nat -I POSTROUTING -d $API_TARGET_IP -j ACCEPT
echo "Added iptables rule to prevent SNAT for API traffic"

# Step 5: Update learn-address script for better resilience
echo "Step 5: Updating learn-address script..."
SCRIPT_DIR="/etc/openvpn/scripts"
if [ -f "$SCRIPT_DIR/learn-address.sh" ]; then
    # Backup the original script
    cp "$SCRIPT_DIR/learn-address.sh" "$SCRIPT_DIR/learn-address.sh.bak"
    
    # Update the script to handle dynamic IPs better
    sed -i "s/metric \"$(date +%s)\"/metric 100/g" $SCRIPT_DIR/learn-address.sh
    
    # Make sure the script has the correct API_TARGET
    sed -i "s/API_TARGET=.*$/API_TARGET=\"$API_TARGET\"/" $SCRIPT_DIR/learn-address.sh
    
    # Update script to add IP-based rules in addition to domain-based rules
    cat > "$SCRIPT_DIR/ip_update_hook.sh" << EOF
#!/bin/bash
# Hook to update routing when API IP changes
API_TARGET="$API_TARGET"
ROUTING_TABLE="apiroutes"

# Get current IP
NEW_IP=\$(host -t A \$API_TARGET | grep "has address" | head -n1 | awk '{print \$NF}')

if [ -n "\$NEW_IP" ]; then
    # Update IP-based rule
    ip rule show | grep -q "to \$NEW_IP lookup \$ROUTING_TABLE" || {
        # Remove old IP rules that aren't the current one
        ip rule show | grep "lookup \$ROUTING_TABLE" | grep -v "to \$API_TARGET" | while read rule; do
            ip_in_rule=\$(echo \$rule | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
            if [ "\$ip_in_rule" != "\$NEW_IP" ]; then
                ip rule del to \$ip_in_rule lookup \$ROUTING_TABLE 2>/dev/null || true
            fi
        done
        
        # Add new rule
        ip rule add to \$NEW_IP lookup \$ROUTING_TABLE
        
        # Update routes in the table using all available routers
        if [ -f "/etc/openvpn/active_routers" ]; then
            while read router_ip; do
                if ping -c 1 -W 1 \$router_ip >/dev/null 2>&1; then
                    ip route replace \$NEW_IP/32 via \$router_ip table \$ROUTING_TABLE
                    break
                fi
            done < "/etc/openvpn/active_routers"
        fi
        
        ip route flush cache
    }
fi
EOF
    chmod +x "$SCRIPT_DIR/ip_update_hook.sh"
    
    # Add cron job to check for IP changes every 15 minutes
    echo "*/15 * * * * root $SCRIPT_DIR/ip_update_hook.sh >/dev/null 2>&1" > /etc/cron.d/api-ip-monitor
    
    echo "Modified learn-address script and created IP monitoring hook"
else
    echo "Warning: learn-address.sh not found in $SCRIPT_DIR"
fi

# Step 6: Generate MikroTik router configuration commands
echo "Step 6: Generating MikroTik router configuration..."
cat > mikrotik_commands.txt << EOF
# MikroTik Router Commands for API Routing

# 1. Ensure IP forwarding is enabled
/ip forward set enabled=yes

# 2. Add specific route for api.ipify.org
/ip route add dst-address=$API_TARGET_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# 3. Set up NAT so traffic appears from MikroTik's public IP
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_TARGET_IP action=masquerade comment="NAT for API traffic"

# 4. Create a script to automatically update routes when API IP changes
/system script
add name="update-api-route" source={
  :local apiTarget "$API_TARGET";
  :local apiIP [:resolve \$apiTarget];
  :local vpnServerIP "$VPN_SERVER_INTERNAL_IP";
  
  # Remove old routes for this target
  :foreach r in=[/ip route find where comment="API route"] do={
    /ip route remove \$r;
  };
  
  # Add new route
  /ip route add dst-address=\$apiIP/32 gateway=\$vpnServerIP distance=1 comment="API route";
  
  :log info "Updated route for \$apiTarget to \$apiIP via \$vpnServerIP";
}

# 5. Add scheduler to run the update script every 4 hours
/system scheduler
add interval=4h name=update-api-route on-event="{/system script run update-api-route;}" \
    start-time=startup

# 6. Run the script immediately
/system script run update-api-route
EOF

echo "MikroTik router configuration has been saved to mikrotik_commands.txt"
echo "Please apply these commands on your MikroTik router"

# Step 7: Create diagnostic script
echo "Step 7: Creating diagnostic script..."
cat > api-routing-diagnostics.sh << 'EOF'
#!/bin/bash
# API Routing Diagnostic Tool

# Set default API target
API_TARGET=${1:-"api.ipify.org"}

echo "===== API Routing Diagnostics ====="
echo "Testing API target: $API_TARGET"
echo "Date: $(date)"
echo ""

# 1. DNS Resolution
echo "==== DNS Resolution ===="
echo -n "Resolving $API_TARGET: "
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -n "$API_IP" ]; then
    echo "$API_IP"
else
    echo "FAILED"
fi

# 2. Current Routes
echo -e "\n==== Routing Tables ===="
echo "Main routing table for $API_TARGET:"
if [ -n "$API_IP" ]; then
    ip route get $API_IP
else
    echo "Cannot resolve API target"
fi

echo -e "\nAPI routes table:"
ip route show table apiroutes

echo -e "\nRouting rules:"
ip rule show | grep -E "(api|$API_IP)"

# 3. OpenVPN Status
echo -e "\n==== OpenVPN Status ===="
systemctl status openvpn --no-pager | head -20

# 4. Active Routers
echo -e "\n==== Active Routers ===="
if [ -f "/etc/openvpn/active_routers" ]; then
    echo "Available routers:"
    cat /etc/openvpn/active_routers
    
    echo -e "\nReachability check:"
    while read router_ip; do
        if ping -c 1 -W 1 $router_ip >/dev/null 2>&1; then
            echo "$router_ip is reachable"
        else
            echo "$router_ip is NOT reachable"
        fi
    done < "/etc/openvpn/active_routers"
else
    echo "No active routers file found"
fi

# 5. Try curl with verbose output
echo -e "\n==== Testing API Connection ===="
echo "Connecting to $API_TARGET with curl:"
curl -v http://$API_TARGET 2>&1 | grep -E "(Connected to|HTTP|GET|< [[:digit:]])"

# 6. Test with traceroute
echo -e "\n==== API Route Traceroute ===="
which traceroute > /dev/null 2>&1 && traceroute $API_TARGET || echo "traceroute not installed"

# 7. Check NAT settings
echo -e "\n==== NAT Configuration ===="
iptables -t nat -L POSTROUTING -v

# 8. Suggest fixes
echo -e "\n==== Potential Fixes ====="
if [ -n "$API_IP" ]; then
    echo "If routing isn't working, try these commands:"
    echo ""
    echo "# Reset API routing:"
    echo "ip rule del to $API_TARGET lookup apiroutes 2>/dev/null || true"
    echo "ip rule del to $API_IP lookup apiroutes 2>/dev/null || true"
    echo "ip rule add to $API_TARGET lookup apiroutes"
    echo "ip rule add to $API_IP lookup apiroutes"
    
    if [ -f "/etc/openvpn/active_routers" ]; then
        FIRST_ROUTER=$(head -1 "/etc/openvpn/active_routers")
        if [ -n "$FIRST_ROUTER" ]; then
            echo "ip route replace $API_IP/32 via $FIRST_ROUTER table apiroutes"
        fi
    fi
    
    echo "ip route flush cache"
    echo ""
    echo "# Ensure NAT is correct:"
    echo "iptables -t nat -I POSTROUTING -d $API_IP -j ACCEPT"
fi
EOF

chmod +x api-routing-diagnostics.sh
echo "Diagnostic script created: api-routing-diagnostics.sh"

# Create a test script specifically for checking the outgoing IP
cat > check-outgoing-ip.sh << 'EOF'
#!/bin/bash
# Check outgoing IP for API requests

REQUESTS=${1:-5}
API_URL="http://api.ipify.org?format=json"
DELAY=${2:-1}

echo "===== Testing API Outgoing IP ====="
echo "Making $REQUESTS requests to $API_URL with ${DELAY}s delay..."
echo "Date: $(date)"
echo ""

for i in $(seq 1 $REQUESTS); do
    echo -n "Request $i: "
    curl -s $API_URL
    echo ""
    sleep $DELAY
done

echo -e "\nIf you're not seeing your MikroTik's public IP:"
echo "1. Make sure the MikroTik router is connected to the VPN server"
echo "2. Run ./api-routing-diagnostics.sh to check the system configuration"
echo "3. Verify the MikroTik configuration using mikrotik_commands.txt"
EOF

chmod +x check-outgoing-ip.sh
echo "IP check script created: check-outgoing-ip.sh"

echo ""
echo "===== Setup Complete ====="
echo "To verify the routing is working correctly, run:"
echo "./check-outgoing-ip.sh 5"
echo ""
echo "If you still have issues, run the diagnostic script:"
echo "./api-routing-diagnostics.sh"
echo ""
echo "Make sure to apply the MikroTik configuration from mikrotik_commands.txt"
echo "The system is now set up to handle IP changes automatically"
echo ""
