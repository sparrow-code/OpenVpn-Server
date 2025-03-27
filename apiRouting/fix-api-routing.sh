#!/bin/bash
# API Routing Fix - Clean and efficient solution
# This script fixes routing to make API requests use MikroTik's public IP

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
API_TARGET="api.ipify.org"
ROUTING_TABLE="apiroutes"
ROUTING_TABLE_ID="200"
LOG_DIR="/var/log/api_routing"
SCRIPT_DIR="/etc/openvpn/scripts"
MIKROTIK_VPN_IP="10.8.0.6"

echo "===== API Routing Fix ====="
echo "Making API traffic go through MikroTik public IP"
echo "Date: $(date)"
echo ""

# Create necessary directories
mkdir -p $LOG_DIR $SCRIPT_DIR /etc/openvpn

# Step 1: Resolve API target 
echo "Step 1: Resolving API target..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_TARGET_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "$API_TARGET resolves to $API_TARGET_IP"

# Step 2: Ensure active_routers file exists with MikroTik IP
echo "Step 2: Setting up active_routers file..."
echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
echo "MikroTik VPN IP set to: $MIKROTIK_VPN_IP"

# Step 3: Enable IP forwarding (critical for routing)
echo "Step 3: Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1
echo "IP forwarding enabled"

# Step 4: Set up proper routing table
echo "Step 4: Setting up routing table..."
grep -q "$ROUTING_TABLE_ID $ROUTING_TABLE" /etc/iproute2/rt_tables || \
    echo "$ROUTING_TABLE_ID $ROUTING_TABLE" >> /etc/iproute2/rt_tables

# Step 5: Clean up all previous routing rules and routes
echo "Step 5: Cleaning up previous routing configuration..."
# Remove all rules for the routing table
ip rule show | grep -E "lookup $ROUTING_TABLE" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done
# Flush the routing table
ip route flush table $ROUTING_TABLE 2>/dev/null || true

# Step 6: Set up IP-based routing 
echo "Step 6: Setting up IP-based routing..."
# Add rule that will route API traffic using our table
ip rule add to $API_TARGET_IP lookup $ROUTING_TABLE
# Add a catch-all default route in the table that points to MikroTik
ip route add default via $MIKROTIK_VPN_IP table $ROUTING_TABLE
echo "Routing configured"

# Step 7: Set up NAT properly - this is the key fix
echo "Step 7: Setting up proper NAT rules..."
# Clear all existing NAT rules to avoid conflicts
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# The critical NAT rules
echo "Adding essential NAT rules..."
# Allow traffic to API to appear from MikroTik instead of server
iptables -t nat -A POSTROUTING -d $API_TARGET_IP -j ACCEPT
# Ensure MikroTik can establish connections from its IP
iptables -t nat -A POSTROUTING -s $MIKROTIK_VPN_IP -j MASQUERADE
echo "NAT rules applied"

# Step 8: Enable proxy ARP on TUN interface
echo "Step 8: Enabling proxy ARP..."
for iface in $(ip link | grep -E ': tun[0-9]+' | cut -d: -f2 | tr -d ' '); do
    echo 1 > /proc/sys/net/ipv4/conf/$iface/forwarding
    echo 1 > /proc/sys/net/ipv4/conf/$iface/proxy_arp
    echo "Enabled proxy_arp on $iface"
done

# Step 9: Flush routing cache to apply changes
echo "Step 9: Applying changes..."
ip route flush cache
echo "Routing cache flushed"

# Create MikroTik router configuration
echo "Creating MikroTik configuration..."
cat > ./mikrotik-fix.rsc << EOF
# MikroTik Configuration for API Routing
# Apply these commands on your MikroTik router

# 1. Enable IP forwarding
/ip forward set enabled=yes

# 2. Route requests to API target through VPN
/ip route add dst-address=$API_TARGET_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# 3. Set up NAT to ensure traffic appears from MikroTik's public IP
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_TARGET_IP action=masquerade comment="NAT for API traffic"

# 4. Add DNS entry for API target
/ip dns static add name=$API_TARGET address=$API_TARGET_IP
EOF

echo ""
echo "===== Fix Complete ====="
echo ""
echo "To test if the fix worked:"
echo "  curl http://api.ipify.org?format=json"
echo ""
echo "If you're still seeing the VPN server's IP (${VPN_SERVER_IP}):"
echo "1. Apply the MikroTik configuration from mikrotik-fix.rsc to your router"
echo "2. Restart OpenVPN: systemctl restart openvpn"
echo "3. Try again: curl http://api.ipify.org?format=json"
echo ""
echo "Your traffic should now go through your MikroTik's public IP."
