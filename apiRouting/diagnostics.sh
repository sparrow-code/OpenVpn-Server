#!/bin/bash
# Advanced Diagnostics for MikroTik Gateway Issues
# This script will help diagnose why the "Nexthop has invalid gateway" error occurs

# Configuration
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
API_TARGET="api.ipify.org"
ROUTERS_FILE="/etc/openvpn/active_routers"
ROUTING_TABLE="apiroutes"

# Get MikroTik IP from active_routers file if it exists
if [ -f "$ROUTERS_FILE" ] && [ -s "$ROUTERS_FILE" ]; then
    MIKROTIK_VPN_IP=$(head -1 "$ROUTERS_FILE")
    echo "Found MikroTik VPN IP: $MIKROTIK_VPN_IP"
else
    # Default to common VPN IP if file doesn't exist
    MIKROTIK_VPN_IP="10.8.0.6"
    echo "Using default MikroTik VPN IP: $MIKROTIK_VPN_IP"
fi

# Resolve API target
echo "Resolving $API_TARGET..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -n "$API_TARGET_IP" ]; then
    echo "$API_TARGET resolved to $API_TARGET_IP"
else
    echo "Could not resolve $API_TARGET"
    echo "Skipping API-specific diagnostics"
fi

echo -e "\n===== Network Interface Information ====="
ip addr show | grep -E '(tun|ens|eth|wlan)'

echo -e "\n===== Current Routing Tables ====="
echo "Main routing table:"
ip route show

echo -e "\nAPI routes table (if exists):"
ip route show table apiroutes 2>/dev/null || echo "apiroutes table not found or empty"

echo -e "\n===== Routing Rules ====="
ip rule show

echo -e "\n===== OpenVPN Status ====="
systemctl status openvpn --no-pager | head -20

echo -e "\n===== OpenVPN Client List ====="
if [ -f "/etc/openvpn/openvpn-status.log" ]; then
    grep "CLIENT_LIST" /etc/openvpn/openvpn-status.log
else
    echo "OpenVPN status log not found"
fi

echo -e "\n===== TUN/TAP Interface Status ====="
ip link show | grep -A 1 tun

echo -e "\n===== IP Forwarding Status ====="
cat /proc/sys/net/ipv4/ip_forward
echo -e "\nDetailed IP forwarding configuration:"
sysctl -a 2>/dev/null | grep -E 'net.ipv4.(ip_forward|conf.*\.forwarding)'

echo -e "\n===== Connection Test to MikroTik Router ====="
ping -c 3 $MIKROTIK_VPN_IP

echo -e "\n===== Route to MikroTik Router ====="
ip route get $MIKROTIK_VPN_IP

echo -e "\n===== NAT Configuration ====="
echo "PREROUTING Chain:"
iptables -t nat -L PREROUTING -v
echo -e "\nPOSTROUTING Chain:"
iptables -t nat -L POSTROUTING -v

echo -e "\n===== Testing API Connection ====="
curl -v http://$API_TARGET 2>&1 | grep -E "(Connected to|HTTP|GET|< [[:digit:]]|\"ip\")"

echo -e "\n===== Kernel Modules for Network ====="
lsmod | grep -E '(tun|tap|ppp|ipv4)'

echo -e "\n===== Network Service Status ====="
systemctl status network.service NetworkManager.service 2>/dev/null || echo "Network service status not available"

echo -e "\n===== Recommended Fixes ====="
echo "1. Run the gateway-fix.sh script to try multiple approaches"
echo "2. Make sure IP forwarding is enabled: echo 1 > /proc/sys/net/ipv4/ip_forward"
echo "3. Check if the MikroTik router is correctly connected and configured"
echo "4. Try alternative NAT approach with explicit DNAT/SNAT rules"
echo "5. Verify MikroTik router has IP forwarding enabled"
echo ""
echo "For more help, see: https://wiki.mikrotik.com/wiki/OpenVPN"
