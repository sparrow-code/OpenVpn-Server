#!/bin/bash
# Enhanced NAT-Based API Routing Solution
# This script implements a comprehensive solution that works with existing MikroTik firewall rules

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
MIKROTIK_VPN_IP="10.8.0.6"
API_TARGET="api.ipify.org"
LOG_DIR="/var/log/api_routing"
INTERFACES_DIR="/proc/sys/net/ipv4/conf"

# Create necessary directories
mkdir -p $LOG_DIR /etc/openvpn

echo "===== Enhanced API Routing Setup ====="
echo "Date: $(date)"
echo "Implementing dual-chain NAT with MikroTik integration"

# Step 1: Ensure MikroTik router is connected
echo "Step 1: Setting up MikroTik connection..."
echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
echo "Testing connectivity..."
if ping -c 2 -W 2 $MIKROTIK_VPN_IP >/dev/null 2>&1; then
    echo "✓ MikroTik router is reachable"
else
    echo "⚠ WARNING: Cannot reach MikroTik router at $MIKROTIK_VPN_IP"
    echo "Please check if the MikroTik router is properly connected to the OpenVPN server"
    echo -n "Continue anyway? [y/N]: "
    read continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        echo "Setup aborted."
        exit 1
    fi
fi

# Step 2: Get current API IP with multiple DNS resolvers for reliability
echo "Step 2: Resolving API target with multiple DNS servers..."
for dns in 8.8.8.8 1.1.1.1 9.9.9.9; do
    echo "Trying DNS server $dns..."
    API_IP=$(dig @$dns +short $API_TARGET A | head -n1)
    if [ -n "$API_IP" ]; then
        break
    fi
done

# Fallback to host command if dig fails
if [ -z "$API_IP" ]; then
    API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
fi

if [ -z "$API_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET with any DNS server"
    exit 1
fi
echo "✓ $API_TARGET resolved to $API_IP"

# Step 3: Configure advanced kernel settings
echo "Step 3: Configuring network kernel parameters..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf

# Enable proxy ARP and IP forwarding on all relevant interfaces
for iface in all default lo tun0; do
    if [ -d "$INTERFACES_DIR/$iface" ]; then
        echo 1 > $INTERFACES_DIR/$iface/forwarding 2>/dev/null || true
        echo 1 > $INTERFACES_DIR/$iface/proxy_arp 2>/dev/null || true
        echo "Enabled forwarding and proxy_arp on $iface"
    fi
done

# Step 4: Ensure routing table exists with only one entry
echo "Step 4: Setting up dedicated routing table..."
grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables
# Fix duplicate entries if they exist
if [ $(grep -c "apiroutes" /etc/iproute2/rt_tables) -gt 1 ]; then
    grep -v "apiroutes" /etc/iproute2/rt_tables > /tmp/rt_tables.new
    echo "200 apiroutes" >> /tmp/rt_tables.new
    mv /tmp/rt_tables.new /etc/iproute2/rt_tables
    echo "✓ Fixed duplicate routing table entries"
fi

# Step 5: Set up comprehensive routing with fallback
echo "Step 5: Setting up enhanced routing..."
# Clean up any existing rules for our table
ip rule show | grep -E "lookup apiroutes" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done

# Add IP-based rule (more reliable than domain-based)
ip rule add to $API_IP lookup apiroutes prio 100

# Add a default route in the apiroutes table
ip route flush table apiroutes
ip route add default via $MIKROTIK_VPN_IP table apiroutes

# Step 6: Set up comprehensive NAT rules
echo "Step 6: Setting up enhanced NAT rules..."
# Clear existing NAT rules to avoid conflicts
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# CRITICAL: The order of these rules matters!
# 1. DNAT packets destined for API_IP to go to MikroTik router
iptables -t nat -A PREROUTING -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP

# 2. SNAT packets going to MikroTik to appear from VPN server
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP

# 3. Accept established connections from MikroTik
iptables -t nat -A POSTROUTING -s $MIKROTIK_VPN_IP -j ACCEPT

# 4. Special HTTP/HTTPS rules (important for API traffic)
iptables -t nat -A PREROUTING -p tcp --dport 80 -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:80
iptables -t nat -A PREROUTING -p tcp --dport 443 -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:443

# 5. Add connection tracking rule to help with return traffic
iptables -A FORWARD -i tun+ -o tun+ -j ACCEPT
echo "✓ Enhanced NAT rules configured"

# Step 7: Flush routing cache and conntrack table for clean state
echo "Step 7: Flushing caches..."
ip route flush cache
if command -v conntrack >/dev/null 2>&1; then
    conntrack -F 2>/dev/null || true
fi

# Step 8: Generate MikroTik configuration that works with existing firewall
echo "Step 8: Creating MikroTik configuration..."
cat > mikrotik-enhanced-commands.rsc << EOF
# Enhanced MikroTik Configuration for API Routing
# Generated on $(date)
# This configuration is designed to work with existing firewall rules

# 1. Enable IP forwarding (if not already enabled)
/ip settings set ip-forward=yes

# 2. Add route for API destination
/ip route add dst-address=$API_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1 comment="API Route for $API_TARGET"

# 3. Add NAT rule that plays well with existing firewall rules
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP action=masquerade comment="API Traffic NAT" place-before=[:pick [/ip firewall nat find chain=srcnat] 0]

# 4. Add DNS static entry to avoid DNS leaks
/ip dns static add name=$API_TARGET address=$API_IP ttl=10m comment="API DNS Entry"

# 5. Create automatic update script for when API IP changes
/system script add name="update-api-route" source={
    :local apiDomain "$API_TARGET"
    :local currentApiIP "$API_IP"
    :local vpnServerIP "$VPN_SERVER_INTERNAL_IP"
    
    :log info "Checking for \$apiDomain IP changes..."
    :local newApiIP [:resolve \$apiDomain]
    
    :if (\$newApiIP != \$currentApiIP) do={
        :log info "API IP changed from \$currentApiIP to \$newApiIP"
        
        # Update route
        /ip route remove [/ip route find where comment="API Route for \$apiDomain"]
        /ip route add dst-address=\$newApiIP/32 gateway=\$vpnServerIP distance=1 comment="API Route for \$apiDomain"
        
        # Update NAT rule
        :local natRule [/ip firewall nat find where comment="API Traffic NAT"]
        :if ([:len \$natRule] > 0) do={
            /ip firewall nat set \$natRule dst-address=\$newApiIP
        }
        
        # Update DNS entry
        :local dnsEntry [/ip dns static find where comment="API DNS Entry"]
        :if ([:len \$dnsEntry] > 0) do={
            /ip dns static set \$dnsEntry address=\$newApiIP
        }
        
        :log info "Updated configuration for new API IP: \$newApiIP"
    } else={
        :log info "API IP unchanged: \$currentApiIP"
    }
}

# 6. Schedule the update script to run every hour
/system scheduler add interval=1h name=check-api-ip start-time=startup on-event="/system script run update-api-route" comment="Check API IP Hourly"
EOF

echo "✓ Enhanced MikroTik configuration saved to mikrotik-enhanced-commands.rsc"

# Step 9: Create a comprehensive test script
cat > enhanced-test-api-routing.sh << 'EOF'
#!/bin/bash
# Enhanced API Routing Test

API_URL="http://api.ipify.org?format=json"
REQUESTS=${1:-10}
DELAY=${2:-1}
LOG_FILE="api_test_results.log"

echo "===== Enhanced API Routing Test ====="
echo "Date: $(date)" | tee -a $LOG_FILE
echo "Testing $REQUESTS requests to $API_URL" | tee -a $LOG_FILE
echo "------------------------------------------" | tee -a $LOG_FILE

# Get expected server IP (VPN server) for comparison
VPN_SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n1)
echo "VPN Server IP: $VPN_SERVER_IP" | tee -a $LOG_FILE

# First, check DNS resolution
echo -n "DNS Resolution: " | tee -a $LOG_FILE
API_IP=$(dig +short api.ipify.org A | head -n1)
if [ -z "$API_IP" ]; then
    API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')
fi
echo "$API_IP" | tee -a $LOG_FILE

# Check NAT rules
echo -n "NAT Rules for API IP: " | tee -a $LOG_FILE
iptables -t nat -S | grep -c $API_IP | tee -a $LOG_FILE

# Test connections with both curl and wget for comparison
declare -A ip_results
success=0

echo -e "\n[CURL] Making $REQUESTS API requests:" | tee -a $LOG_FILE
for i in $(seq 1 $REQUESTS); do
    echo -n "Request $i: " | tee -a $LOG_FILE
    response=$(curl -s $API_URL)
    if [ $? -eq 0 ]; then
        # Extract IP address
        ip=$(echo "$response" | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
        echo "$ip" | tee -a $LOG_FILE
        
        # Count occurrences
        if [ -n "$ip" ]; then
            ip_results[$ip]=$((${ip_results[$ip]:-0} + 1))
            ((success++))
        fi
    else
        echo "Failed" | tee -a $LOG_FILE
    fi
    sleep $DELAY
done

# Try wget as an alternative if available
if command -v wget >/dev/null 2>&1; then
    echo -e "\n[WGET] Making verification request:" | tee -a $LOG_FILE
    wget_response=$(wget -qO- $API_URL)
    wget_ip=$(echo "$wget_response" | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
    echo "WGET IP: $wget_ip" | tee -a $LOG_FILE
fi

echo -e "\n===== Results Summary ====="  | tee -a $LOG_FILE
echo "Total requests: $REQUESTS" | tee -a $LOG_FILE
echo "Successful requests: $success" | tee -a $LOG_FILE
echo "Unique IPs detected: ${#ip_results[@]}" | tee -a $LOG_FILE

echo -e "\nIP distribution:" | tee -a $LOG_FILE
for ip in "${!ip_results[@]}"; do
    count=${ip_results[$ip]}
    percentage=$((count * 100 / REQUESTS))
    bar=$(printf "%0.s#" $(seq 1 $((percentage / 5))))
    echo "$ip: $count requests ($percentage%) $bar" | tee -a $LOG_FILE
    
    # Important check - is this our VPN server IP?
    if [ "$ip" == "$VPN_SERVER_IP" ]; then
        echo "⚠️ WARNING: Requests are using VPN server's IP, not MikroTik router IP!" | tee -a $LOG_FILE
    fi
done

# Show routing information
echo -e "\nRouting information:" | tee -a $LOG_FILE
echo "API routes table:" | tee -a $LOG_FILE
ip route show table apiroutes | tee -a $LOG_FILE

echo -e "\nRouting rules for API:" | tee -a $LOG_FILE
ip rule show | grep -E '(apiroutes|'$API_IP')' | tee -a $LOG_FILE

echo -e "\nActual route used:" | tee -a $LOG_FILE
ip route get $API_IP | tee -a $LOG_FILE

echo -e "\nLog saved to $LOG_FILE"

# Simple analysis of results
if [ ${#ip_results[@]} -eq 0 ]; then
    echo -e "\n❌ TEST FAILED: No successful responses"
elif [ ${ip_results[$VPN_SERVER_IP]:-0} -eq $success ] && [ $success -gt 0 ]; then
    echo -e "\n❌ TEST FAILED: All traffic is still going through VPN server"
    echo -e "\nTroubleshooting steps:"
    echo "1. Check if MikroTik commands were applied correctly"
    echo "2. Restart OpenVPN: sudo systemctl restart openvpn"
    echo "3. Check firewall settings on MikroTik"
    echo "4. Verify the NAT rules on the VPN server"
elif [ ${ip_results[$VPN_SERVER_IP]:-0} -gt 0 ]; then
    echo -e "\n⚠️ PARTIAL SUCCESS: Some traffic is still using VPN server IP"
else
    echo -e "\n✅ TEST PASSED: Traffic is successfully routed through MikroTik"
fi
EOF

chmod +x enhanced-test-api-routing.sh

echo -e "\n===== Enhanced Setup Complete ====="
echo ""
echo "IMPORTANT: Follow these steps exactly to make it work:"
echo ""
echo "1. Apply the MikroTik commands one by one from mikrotik-enhanced-commands.rsc"
echo "   IMPORTANT: Each command must be applied separately to avoid syntax errors"
echo ""
echo "2. Restart OpenVPN and networking on the server:"
echo "   sudo systemctl restart openvpn"
echo "   sudo systemctl restart networking"
echo ""
echo "3. Run the enhanced test script to verify the setup:"
echo "   ./enhanced-test-api-routing.sh"
echo ""
echo "If it's still showing the VPN server IP, check:"
echo "1. MikroTik connection status (ping $MIKROTIK_VPN_IP)"
echo "2. MikroTik firewall rules that might be blocking traffic"
echo "3. Run 'ip route get $API_IP' to see the actual route being used"
echo ""
echo "Logs are stored in $LOG_DIR for later investigation"
