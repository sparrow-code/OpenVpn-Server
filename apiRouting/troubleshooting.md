# API Routing Troubleshooting Guide

This guide provides solutions for the most common issues with the API routing solution.

## NAT-Based Transparent Proxy Routing Technique

This solution uses NAT rules instead of direct routing to avoid the "Nexthop has invalid gateway" error.

### How It Works

1. Traffic to API IP is DNATed to MikroTik router
2. Return traffic is SNATed to VPN server internal IP
3. MikroTik processes traffic through its public interface
4. No direct routing is used, avoiding gateway issues

## Common Issues

### 1. "Nexthop has invalid gateway" Error

This happens when you try to use direct routing. Fix by using NAT-based transparent proxying instead:

```bash
# Get API IP
API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')
MIKROTIK_VPN_IP="10.8.0.6"
VPN_SERVER_INTERNAL_IP="10.8.0.1"

# Clear existing rules
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Set up NAT-based transparent proxying
iptables -t nat -A PREROUTING -d $API_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
```

### 2. MikroTik Command Syntax Errors

The MikroTik router requires specific command syntax. Use these exact commands:

```
# This works - Enable IP forwarding
/ip forward set enabled=yes

# This works - Add route
/ip route add dst-address=104.26.12.205/32 gateway=10.8.0.1 distance=1

# This works - Add NAT rule
/ip firewall nat add chain=srcnat src-address=10.8.0.1 dst-address=104.26.12.205 action=masquerade
```

### 3. Domain-Based Routing Not Working

Linux IP rules don't support domain names directly. Always use IP addresses:

```bash
# This fails
ip rule add to api.ipify.org lookup apiroutes  # Error!

# This works
API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')
ip rule add to $API_IP lookup apiroutes
```

### 4. API IP Address Changes

API services like api.ipify.org use multiple IPs. Use this script to update your configuration when the IP changes:

```bash
#!/bin/bash
API_TARGET="api.ipify.org"
OLD_IP=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' /path/to/your/config)
NEW_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')

if [ "$OLD_IP" != "$NEW_IP" ]; then
    echo "IP changed from $OLD_IP to $NEW_IP, updating..."
    # Update NAT rules
    iptables -t nat -F PREROUTING
    iptables -t nat -F POSTROUTING
    iptables -t nat -A PREROUTING -d $NEW_IP -j DNAT --to-destination 10.8.0.6
    iptables -t nat -A POSTROUTING -d 10.8.0.6 -j SNAT --to-source 10.8.0.1
fi
```

### 5. Testing Your Setup

Run this simple test to verify if your setup is working:

```bash
# Simple test
curl http://api.ipify.org?format=json

# Multiple requests test
for i in {1..5}; do curl -s http://api.ipify.org?format=json; echo; sleep 1; done
```

If the IP shown is your MikroTik's public IP, the setup is working correctly. If it shows 176.222.55.126, it's still using your VPN server's IP.
