# API Routing Troubleshooting Guide

This guide will help you diagnose and fix issues with the API routing solution, focusing on resilience to IP changes.

## Common Issues

### 1. Traffic Is Not Using MikroTik Public IP

If your API requests show the VPN server's IP (176.222.55.126) instead of the MikroTik's public IP:

#### Verify MikroTik Connection

```bash
# Check if MikroTik is connected to VPN
cat /etc/openvpn/active_routers
# Ensure at least one router IP is listed
```

#### Check Routing Tables

```bash
# Resolve current API IP
API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')
echo "API IP: $API_IP"

# Check if API route exists in special routing table
ip route show table apiroutes
# Should show a route to the API IP via MikroTik's VPN IP

# Check if routing rules exist
ip rule show | grep -E "(api|$API_IP)"
# Should show rules for both domain and IP

# Test API IP route lookup
ip route get $API_IP
# Should show route via MikroTik VPN IP
```

### 2. Missing Active Routers File

If `/etc/openvpn/active_routers` is missing:

```bash
# Create the active_routers file with your MikroTik VPN IP
mkdir -p /etc/openvpn
echo "10.8.0.6" > /etc/openvpn/active_routers
```

### 3. Missing Routing Table

If the `apiroutes` table doesn't exist:

```bash
# Add the routing table
echo "200 apiroutes" >> /etc/iproute2/rt_tables

# Verify it was created
grep apiroutes /etc/iproute2/rt_tables
```

### 4. No API Routing Rules

If API routing rules are missing:

```bash
# Get current API IP
API_IP=$(host -t A api.ipify.org | grep "has address" | head -n1 | awk '{print $NF}')

# Add routing rules
ip rule add to api.ipify.org lookup apiroutes
ip rule add to $API_IP lookup apiroutes

# Add route to the table
ip route add $API_IP/32 via 10.8.0.6 table apiroutes

# Flush routing cache
ip route flush cache
```

### 5. MikroTik Router Configuration Issues

Make sure your MikroTik is properly configured:
