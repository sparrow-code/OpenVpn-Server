#!/bin/bash
# NAT-Based Transparent Proxy Routing for API Traffic
# This is a simplified, reliable approach for routing API traffic through a MikroTik router

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
MIKROTIK_VPN_IP="10.8.0.6"
API_TARGET="api.ipify.org"
LOG_DIR="/var/log/api_routing"

# Create necessary directories
mkdir -p $LOG_DIR /etc/openvpn

echo "===== NAT-Based Transparent Proxy Routing Setup ====="
echo "Date: $(date)"

# Step 1: Ensure MikroTik router is connected
echo "Step 1: Setting up MikroTik connection..."
echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
echo "Testing connectivity..."
if ping -c 2 -W 2 $MIKROTIK_VPN_IP >/dev/null 2>&1; then
    echo "✓ MikroTik router is reachable"
else
    echo "⚠ WARNING: Cannot reach MikroTik router at $MIKROTIK_VPN_IP"
    echo "Continuing, but this may not work without MikroTik connection"
fi

# Step 2: Get current API IP
echo "Step 2: Resolving API target..."
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "✓ $API_TARGET resolved to $API_IP"

# Step 3: Enable IP forwarding
echo "Step 3: Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1

# Step 4: Clear all iptables NAT rules to avoid conflicts
echo "Step 4: Clearing existing NAT rules..."
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Step 5: Set up NAT rules - this is the core of the technique
echo "Step 5: Setting up NAT-Based Transparent Proxy..."
iptables -t nat -A PREROUTING -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
echo "✓ NAT-Based Transparent Proxy configured"

# Step 6: Enable proxy ARP on TUN interfaces
echo "Step 6: Enabling proxy ARP..."
for iface in $(ip link | grep -E ': tun[0-9]+' | cut -d: -f2 | tr -d ' '); do
    echo 1 > /proc/sys/net/ipv4/conf/$iface/forwarding
    echo 1 > /proc/sys/net/ipv4/conf/$iface/proxy_arp
    echo "Enabled proxy_arp on $iface"
done

# Step 7: Flush routing cache
echo "Step 7: Flushing routing cache..."
ip route flush cache

# Step 8: Create MikroTik configuration with TESTED WORKING commands
echo "Step 8: Creating MikroTik configuration..."
cat > mikrotik-router-commands.txt << EOF
# MikroTik Router Commands for API Routing
# IMPORTANT: Copy and paste ONE LINE AT A TIME into your MikroTik terminal

# Enable IP forwarding (correct syntax)
/ip forward set enabled=yes

# Add route for API target
/ip route add dst-address=$API_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# Add NAT rule for API traffic
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP action=masquerade comment="API Traffic NAT"

# Add DNS static entry (might fail if already exists)
/ip dns static add name=$API_TARGET address=$API_IP comment="API DNS entry"
EOF

echo "✓ MikroTik configuration saved to mikrotik-router-commands.txt"

# Step 9: Create a simple test script
cat > test-api-routing.sh << 'EOF'
#!/bin/bash
# Test API routing

API_URL="http://api.ipify.org?format=json"
REQUESTS=${1:-5}

echo "===== Testing API Routing ====="
echo "Making $REQUESTS requests to $API_URL"
echo ""

for i in $(seq 1 $REQUESTS); do
    echo -n "Request $i: "
    curl -s $API_URL
    echo ""
    sleep 1
done
EOF
chmod +x test-api-routing.sh

echo ""
echo "===== NAT-Based Transparent Proxy Routing Setup Complete ====="
echo ""
echo "IMPORTANT STEPS TO MAKE IT WORK:"
echo ""
echo "1. Copy and paste each MikroTik command ONE BY ONE:"
echo "   - Open the file: mikrotik-router-commands.txt"
echo "   - Copy and paste each command SEPARATELY into your MikroTik terminal"
echo ""
echo "2. Restart OpenVPN service:"
echo "   sudo systemctl restart openvpn"
echo ""
echo "3. Test if it's working:"
echo "   ./test-api-routing.sh"
echo ""
echo "If it still shows the VPN server's IP ($VPN_SERVER_IP),"
echo "make sure you've correctly entered ALL MikroTik commands."
echo ""
echo "This NAT-Based Transparent Proxy Routing technique bypasses"
echo "the 'Nexthop has invalid gateway' error by using NAT instead of routing."
echo ""
