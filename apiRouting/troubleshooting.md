# Enhanced API Routing Troubleshooting Guide

## Comprehensive Diagnosis Steps

### 1. Verify MikroTik Connectivity

First, ensure your MikroTik router is properly connected:

```bash
# Check if MikroTik is connected to VPN and responsive
ping -c 3 10.8.0.6
cat /etc/openvpn/active_routers
```

### 2. Check Routing Configuration

Verify the routing tables and rules are properly set up:

```bash
# Get current API IP
API_IP=$(dig +short api.ipify.org)
echo "API IP: $API_IP"

# Check routing table
ip route show table apiroutes

# Check routing rules
ip rule show | grep -E "(api|$API_IP)"

# See what route will actually be used
ip route get $API_IP
```

### 3. Verify NAT Rules

Ensure your NAT rules are correctly set up:

```bash
# Check PREROUTING chain
iptables -t nat -L PREROUTING -v -n
# Should show DNAT rule for API IP to MikroTik

# Check POSTROUTING chain
iptables -t nat -L POSTROUTING -v -n
# Should show SNAT rule for MikroTik
```

### 4. Common Issues and Solutions

#### Traffic Still Using VPN Server IP

If requests still show the VPN server's IP (176.222.55.126):

1. **Comprehensive NAT Rules Fix**:

```bash
API_IP=$(dig +short api.ipify.org)
MIKROTIK_VPN_IP="10.8.0.6"
VPN_SERVER_INTERNAL_IP="10.8.0.1"

# Clear existing rules
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Add proper NAT rules
iptables -t nat -A PREROUTING -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
iptables -t nat -A PREROUTING -p tcp --dport 80 -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:80
iptables -t nat -A PREROUTING -p tcp --dport 443 -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:443

# Clean conntrack table
conntrack -F 2>/dev/null || echo "conntrack not available"
```

2. **Check MikroTik Configuration**:

Connect to your MikroTik router and verify:

```
/ip route print where comment~"API"
/ip firewall nat print where comment~"API"
/ip dns static print where comment~"API"
```

3. **Restart Services**:

```bash
sudo systemctl restart openvpn
sudo systemctl restart networking
```

#### MikroTik Command Errors

When entering commands on the MikroTik router:

1. Use these exact commands one at a time:

```
# First enable IP forwarding
/ip settings set ip-forward=yes

# Then add the route (use correct IP!)
/ip route add dst-address=104.26.12.205/32 gateway=10.8.0.1 distance=1

# Then add NAT rule
/ip firewall nat add chain=srcnat src-address=10.8.0.1 dst-address=104.26.12.205 action=masquerade
```

2. If you see "bad command name" errors, check your RouterOS version. These commands work on RouterOS v6 and v7.

#### API IP Address Changes Frequently

If the API IP changes often:

1. Use the address list feature on MikroTik:

```
/ip firewall address-list add address=104.26.12.205 list=api_targets
/ip firewall address-list add address=104.26.13.205 list=api_targets
/ip firewall nat add chain=srcnat src-address=10.8.0.1 dst-address-list=api_targets action=masquerade
```

2. Use our automatic update script included in the MikroTik configuration.

#### Firewall Interference

If your existing firewall rules are interfering:

1. Ensure the new NAT rule is placed at the beginning of your NAT chain:

```
/ip firewall nat add chain=srcnat src-address=10.8.0.1 dst-address=104.26.12.205 action=masquerade place-before=0
```

2. Add a dedicated accept rule for API traffic if needed:

```
/ip firewall filter add chain=forward src-address=10.8.0.1 dst-address-list=api_targets action=accept place-before=0
```

### 5. Advanced Diagnostics

For deeper diagnosis:

```bash
# Check routing cache
ip route show cache

# Watch traffic in real-time
sudo tcpdump -i tun0 host api.ipify.org -n

# Test with multiple methods
curl -v http://api.ipify.org
wget -O- http://api.ipify.org
python3 -c "import urllib.request; print(urllib.request.urlopen('http://api.ipify.org').read().decode())"
```

### 6. Understanding the NAT-Based Transparent Proxy Technique

Our technique uses a combination of special NAT rules:

1. **DNAT** - Redirects traffic to API to go to the MikroTik router
2. **SNAT** - Makes redirected traffic appear to come from the VPN server
3. **Connection Tracking** - Ensures return traffic is properly routed

Unlike direct routing, this approach avoids "Nexthop has invalid gateway" errors and works even with complex firewall setups.
