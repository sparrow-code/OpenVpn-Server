#!/bin/bash
# MikroTik API Routing Fix
# Comprehensive solution with proper syntax for MikroTik

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
MIKROTIK_VPN_IP="10.8.0.6"
API_TARGET="api.ipify.org"

# Step 1: Resolve current API IP
echo "Resolving current API IP address..."
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi
echo "$API_TARGET currently resolves to $API_IP"

# Step 2: Configure VPN server
echo "Configuring VPN server..."

# Ensure IP forwarding is enabled
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1

# Ensure routing table exists
grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables

# Clear existing rules and routes for apiroutes
ip rule show | grep -E "lookup apiroutes" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done
ip route flush table apiroutes 2>/dev/null || true

# Set up rules and routes
ip rule add to $API_IP lookup apiroutes
ip route add default via $MIKROTIK_VPN_IP table apiroutes

# Clear and set up NAT rules
echo "Configuring NAT rules..."
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Add essential NAT rules - this is the key fix
iptables -t nat -A PREROUTING -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
iptables -t nat -A POSTROUTING -s $MIKROTIK_VPN_IP -j ACCEPT

# Flush routing cache
ip route flush cache

# Step 3: Generate fixed MikroTik configuration
echo "Generating MikroTik configuration..."

cat > mikrotik-commands.rsc << EOF
# MikroTik Configuration for API Routing ($API_TARGET)
# Generated on $(date)
# Apply these commands one by one on your MikroTik router

# Enable IP forwarding
/ip forward enable

# Add route for API target
/ip route add dst-address=$API_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# Add NAT rule
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP action=masquerade comment="API Traffic NAT"

# Add DNS static entry
/ip dns static add name=$API_TARGET address=$API_IP comment="API DNS entry"
EOF

echo "Configuration saved to mikrotik-commands.rsc"

echo -e "\n===== Setup Complete ====="
echo "1. Apply the MikroTik commands from the file ONE BY ONE:"
echo "   - Connect to your MikroTik router"
echo "   - Copy and paste each command separately"
echo ""
echo "2. Restart OpenVPN with: sudo systemctl restart openvpn"
echo ""
echo "3. Test the connection with: curl http://api.ipify.org?format=json"
echo ""
echo "Your API traffic should now go through the MikroTik router's IP."
