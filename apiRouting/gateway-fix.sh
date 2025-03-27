#!/bin/bash
# Gateway Fix Script - Specifically addresses the "Nexthop has invalid gateway" error
# This script fixes the routing issue when MikroTik cannot be used as a gateway

# Fixed Configuration Variables - Only these will not change
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
LOG_DIR="/var/log/api_routing"
SCRIPT_DIR="/etc/openvpn/scripts"

# Ensure required directories exist
mkdir -p $LOG_DIR $SCRIPT_DIR

# Get API target and VPN IP
API_TARGET="api.ipify.org"
ROUTERS_FILE="/etc/openvpn/active_routers"

echo "===== Gateway Fix Script ====="
echo "This script specifically fixes the 'Nexthop has invalid gateway' error"
echo "Date: $(date)"
echo ""

# Read MikroTik VPN IP from active_routers
if [ -f "$ROUTERS_FILE" ] && [ -s "$ROUTERS_FILE" ]; then
    MIKROTIK_VPN_IP=$(head -1 "$ROUTERS_FILE")
    echo "Found MikroTik VPN IP: $MIKROTIK_VPN_IP"
else
    echo -n "Router file not found. Enter MikroTik VPN IP (default 10.8.0.6): "
    read input_ip
    MIKROTIK_VPN_IP=${input_ip:-"10.8.0.6"}
    echo "$MIKROTIK_VPN_IP" > $ROUTERS_FILE
    echo "Created router file with IP: $MIKROTIK_VPN_IP"
fi

# Get API target IP
echo "Resolving $API_TARGET..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_TARGET_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "$API_TARGET resolved to $API_TARGET_IP"

# Step 1: Enable IP forwarding (critical for routing to work)
echo "Enabling IP forwarding system-wide..."
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl --system
echo "✓ IP forwarding enabled"

# Step 2: Fix the routing problem - Multiple approaches since the regular way fails

# Approach 1: Try to fix direct routing using a different syntax
echo "Approach 1: Testing alternative route syntax..."
ip route del $API_TARGET_IP/32 via $MIKROTIK_VPN_IP table apiroutes 2>/dev/null || true
ip route del $API_TARGET_IP/32 dev lo table apiroutes 2>/dev/null || true

# Try multiple route commands with different syntax
ip route add $API_TARGET_IP/32 via $MIKROTIK_VPN_IP table apiroutes 2>/dev/null || \
ip route add $API_TARGET_IP/32 dev tun0 via $MIKROTIK_VPN_IP table apiroutes 2>/dev/null || \
echo "Standard routing failed, trying alternative approaches."

# Approach 2: Enhanced NAT approach (This is the most reliable alternative)
echo "Approach 2: Setting up enhanced NAT routing..."
echo "Clearing existing NAT rules..."
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Add specific NAT rules for the API target
echo "Adding DNAT/SNAT rules for API traffic..."
iptables -t nat -A PREROUTING -d $API_TARGET_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
echo "✓ NAT rules configured"

# Approach 3: Kernel module check and proxy ARP
echo "Approach 3: Setting up proxy_arp to help with routing..."
for iface in $(ip link | grep -E ': tun[0-9]+' | cut -d: -f2 | tr -d ' '); do
    echo 1 > /proc/sys/net/ipv4/conf/$iface/forwarding
    echo 1 > /proc/sys/net/ipv4/conf/$iface/proxy_arp
    echo "Enabled proxy_arp on $iface"
done
echo "✓ Proxy ARP configured"

# Approach 4: Special rule for OpenVPN TUN interface
echo "Approach 4: Setting up direct device route..."
TUN_IFACE=$(ip route | grep -m1 "$MIKROTIK_VPN_IP" | awk '{print $3}')
if [ -n "$TUN_IFACE" ]; then
    echo "Found TUN interface: $TUN_IFACE for MikroTik router"
    ip route replace $API_TARGET_IP/32 dev $TUN_IFACE table apiroutes
    echo "✓ Added direct device route"
else
    echo "Warning: Could not determine TUN interface"
fi

# Approach 5: Use policy routing for simplicity
echo "Approach 5: Setting up policy based routing..."
# Ensure routing table exists
grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables

# Clean up any existing rules
ip rule show | grep -E "lookup apiroutes" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done

# Add rule for IP
ip rule add to $API_TARGET_IP lookup apiroutes
ip route flush cache

echo "✓ Added policy rule for $API_TARGET_IP"

# Create a simple verification script
cat > verify_routing.sh << 'EOF'
#!/bin/bash
# Verify routing fix worked

API_TARGET="api.ipify.org"
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')

echo "===== Verifying API Routing ====="
echo "API Target: $API_TARGET ($API_IP)"
echo ""

# Test 1: Check if the NAT rule is working
echo "Test 1: Checking NAT configuration..."
iptables -t nat -L PREROUTING -v | grep $API_IP
if [ $? -eq 0 ]; then
    echo "✓ NAT rules found for $API_IP"
else
    echo "✗ NAT rules not found for $API_IP"
fi

# Test 2: Direct connectivity test
echo -e "\nTest 2: Testing direct connectivity..."
curl -s http://$API_TARGET?format=json
echo ""

# Test 3: More verbose test
echo -e "\nTest 3: Running verbose test..."
curl -v http://$API_TARGET 2>&1 | grep -E "(Connected to|HTTP|GET|< [[:digit:]]|\"ip\")"

echo -e "\n===== Verification Complete ====="
echo "If you see your MikroTik's public IP in the response, the fix worked!"
echo "If not, apply the MikroTik configuration and try again."
EOF

chmod +x verify_routing.sh
echo "✓ Created verification script: verify_routing.sh"

# Generate the MikroTik configuration
cat > mikrotik_gateway_fix.rsc << EOF
# MikroTik Gateway Fix Commands
# Apply these commands on your MikroTik router to ensure proper routing

# 1. Enable IP forwarding
/ip forward set enabled=yes

# 2. Add a specific route for $API_TARGET
/ip route add dst-address=$API_TARGET_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1 comment="API route fix"

# 3. Set up source NAT
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_TARGET_IP action=masquerade comment="API traffic NAT"

# 4. Add DNS static entry
/ip dns static add name=$API_TARGET address=$API_TARGET_IP comment="API DNS fix"

# 5. Add explicit rule for HTTP/HTTPS
/ip firewall nat add chain=srcnat protocol=tcp src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_TARGET_IP dst-port=80,443 action=masquerade comment="HTTP/HTTPS NAT"

# 6. Ensure interfaces are configured correctly
/interface list
add name=VPN
/interface list member
add interface=ovpn-out1 list=VPN
/interface ovpn-client
set [find] add-default-route=no connect-to=$VPN_SERVER_IP use-encryption=yes
EOF

echo "✓ Created MikroTik configuration: mikrotik_gateway_fix.rsc"

echo ""
echo "===== Gateway Fix Complete ====="
echo ""
echo "The gateway error should be fixed using multiple approaches."
echo ""
echo "Verification steps:"
echo "1. Run the verification script: ./verify_routing.sh"
echo "2. Apply the MikroTik configuration: mikrotik_gateway_fix.rsc"
echo "3. Final test: curl http://api.ipify.org?format=json"
echo ""
echo "If still not working, try rebooting both the VPN server and the MikroTik router."
echo ""
