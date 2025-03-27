#!/bin/bash
# TUN Bridge Routing for API Traffic
# This approach creates a direct bridge between TUN and MikroTik router

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
MIKROTIK_VPN_IP="10.8.0.6"
API_TARGET="api.ipify.org"
LOG_DIR="/var/log/api_routing"
BRIDGE_NAME="br-apiroute"

# Create necessary directories
mkdir -p $LOG_DIR /etc/openvpn

echo "===== TUN Bridge API Routing Setup ====="
echo "Date: $(date)"

# Step 1: Ensure MikroTik router is connected
echo "Step 1: Setting up MikroTik connection..."
echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
echo "Testing connectivity..."
if ping -c 2 -W 2 $MIKROTIK_VPN_IP >/dev/null 2>&1; then
    echo "✓ MikroTik router is reachable"
else
    echo "⚠ WARNING: Cannot reach MikroTik router at $MIKROTIK_VPN_IP"
    echo "This method requires a connected MikroTik router"
    exit 1
fi

# Step 2: Resolve API domain to IP
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

# Step 4: Create network bridge
echo "Step 4: Creating network bridge..."
TUN_INTERFACE=$(ip link | grep -E ': tun[0-9]+' | cut -d: -f2 | tr -d ' ' | head -n1)

if [ -z "$TUN_INTERFACE" ]; then
    echo "Error: No TUN interface found. Make sure OpenVPN is running."
    exit 1
fi

# Install bridge-utils if not available
if ! command -v brctl &> /dev/null; then
    echo "Installing bridge-utils..."
    apt update && apt install -y bridge-utils
fi

# Remove bridge if it already exists
if brctl show | grep -q $BRIDGE_NAME; then
    echo "Removing existing bridge..."
    ip link set $BRIDGE_NAME down
    brctl delbr $BRIDGE_NAME
fi

# Create bridge and add TUN interface
echo "Creating bridge $BRIDGE_NAME with $TUN_INTERFACE..."
brctl addbr $BRIDGE_NAME
ip link set $BRIDGE_NAME up
ip link set $TUN_INTERFACE promisc on
brctl addif $BRIDGE_NAME $TUN_INTERFACE

# Step 5: Configure explicit routing for API target
echo "Step 5: Setting up routing for API target..."
# Ensure routing table exists
grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables

# Clean up existing rules
ip rule show | grep -E "lookup apiroutes" | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    ip rule del prio $rule_num 2>/dev/null || true
done
ip route flush table apiroutes 2>/dev/null || true

# Add IP-based rule
ip rule add to $API_IP lookup apiroutes
ip route add $API_IP via $MIKROTIK_VPN_IP table apiroutes

# Step 6: Configure proxy ARP
echo "Step 6: Enabling proxy ARP..."
echo 1 > /proc/sys/net/ipv4/conf/all/proxy_arp
echo 1 > /proc/sys/net/ipv4/conf/$TUN_INTERFACE/proxy_arp
echo 1 > /proc/sys/net/ipv4/conf/$BRIDGE_NAME/proxy_arp

# Step 7: Create MikroTik configuration
echo "Step 7: Creating MikroTik configuration..."
cat > mikrotik-tun-bridge-commands.txt << EOF
# MikroTik Router Commands for TUN Bridge API Routing
# IMPORTANT: Copy and paste ONE LINE AT A TIME into your MikroTik terminal

# Enable IP forwarding
/ip forward set enabled=yes

# Add route for API target
/ip route add dst-address=$API_IP/32 gateway=$VPN_SERVER_INTERNAL_IP distance=1

# Add NAT rule for API traffic with fallback
/ip firewall nat add chain=srcnat action=masquerade src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP comment="API Traffic NAT"

# Add DNS entry for consistent resolution
/ip dns static add name=$API_TARGET address=$API_IP comment="API DNS entry"

# Add firewall exception for OpenVPN traffic
/ip firewall filter add chain=forward action=accept connection-state=established,related comment="Allow established API connections"
/ip firewall filter add chain=forward action=accept protocol=tcp src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP dst-port=80,443 comment="Allow API HTTP/HTTPS traffic"
EOF

echo "✓ MikroTik configuration saved to mikrotik-tun-bridge-commands.txt"

# Step 8: Create systemd service for persistence
echo "Step 8: Creating persistent configuration..."
cat > /etc/systemd/system/api-tun-bridge.service << EOF
[Unit]
Description=API TUN Bridge Service
After=network.target openvpn.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip link set $TUN_INTERFACE promisc on && brctl addif $BRIDGE_NAME $TUN_INTERFACE && ip rule add to $API_IP lookup apiroutes && ip route add $API_IP via $MIKROTIK_VPN_IP table apiroutes'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable api-tun-bridge.service

# Step 9: Create test script
echo "Step 9: Creating test script..."
cat > test-tun-bridge.sh << 'EOF'
#!/bin/bash
# Test TUN bridge API routing

API_URL="http://api.ipify.org?format=json"
REQUESTS=${1:-5}

echo "===== Testing TUN Bridge API Routing ====="
echo "Making $REQUESTS requests to $API_URL"
echo ""

for i in $(seq 1 $REQUESTS); do
    echo -n "Request $i: "
    curl -s $API_URL
    echo ""
    sleep 1
done

echo -e "\nChecking actual route used:"
API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')
ip route get $API_IP
EOF
chmod +x test-tun-bridge.sh

echo ""
echo "===== TUN Bridge API Routing Setup Complete ====="
echo ""
echo "IMPORTANT STEPS TO MAKE IT WORK:"
echo ""
echo "1. Configure your MikroTik router:"
echo "   - Copy and paste each command SEPARATELY from mikrotik-tun-bridge-commands.txt"
echo ""
echo "2. Restart OpenVPN service:"
echo "   sudo systemctl restart openvpn"
echo ""
echo "3. Test if it's working:"
echo "   ./test-tun-bridge.sh"
echo ""
echo "If it still shows the VPN server's IP, try:"
echo "1. Run: sudo systemctl restart api-tun-bridge.service"
echo "2. Check if bridge is properly created: brctl show $BRIDGE_NAME"
echo "3. As a last resort, reboot your server and router"
echo ""
