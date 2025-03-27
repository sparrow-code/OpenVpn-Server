# Client Configuration Guide for API Routing Solution

This guide provides configuration instructions for various client platforms to work with our API routing solution.

## MikroTik RouterOS Configuration

MikroTik routers require minimal configuration as most of the routing logic is handled by the VPN server.

```
# MikroTik RouterOS Configuration
/interface ovpn-client
add connect-to=<YOUR_VPN_SERVER_IP> name=ovpn-out1 port=1194 \
    user=mikrotik_router1 password=<YOUR_PASSWORD> \
    certificate=<YOUR_CERT_NAME_IF_NEEDED> auth=sha1 cipher=aes256 \
    mode=ip add-default-route=no

# Enable IP forwarding
/ip forward
set enabled=yes

# For better reliability, add a scheduler to check connection
/system scheduler
add interval=15m name=check-vpn on-event="/system script run check-vpn" \
    policy=read,write,test start-time=startup

# Create connection check script
/system script
add name=check-vpn owner=admin policy=read,write,test source=\
"if ([/interface get [find name=\"ovpn-out1\"] running] = false) do={\
    /log info \"Reconnecting VPN...\"\
    /interface ovpn-client disable ovpn-out1\
    :delay 5s\
    /interface ovpn-client enable ovpn-out1\
}"
```

## Windows Client Configuration

For Windows clients that need to use this routing solution:

1. Install OpenVPN client for Windows
2. Create a custom client configuration file (`.ovpn`):

```
client
dev tun
proto udp
remote <YOUR_VPN_SERVER_IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
remote-cert-tla server
cipher AES-256-CBC
auth SHA256
verb 3

# Use the specific route for api.ipify.org only
route api.ipify.org 255.255.255.255
# Do not use VPN as default gateway
route-nopull
```

3. Save the above as `custom_api_routing.ovpn` and include the necessary certificates.

## Linux Client Configuration

For Linux clients:

1. Install OpenVPN: `sudo apt install openvpn` (Debian/Ubuntu) or `sudo yum install openvpn` (CentOS/RHEL)
2. Create a client configuration file:

```
client
dev tun
proto udp
remote <YOUR_VPN_SERVER_IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/client.crt
key /etc/openvpn/client.key
remote-cert-tla server
cipher AES-256-CBC
auth SHA256
verb 3

# Use specific route for api.ipify.org only
route api.ipify.org 255.255.255.255
# Do not use VPN as default gateway
route-nopull

# Set up script to handle API domain resolution
script-security 2
up /etc/openvpn/scripts/add-api-route.sh
```

3. Create the helper script for domain resolution:

```bash
#!/bin/bash
# /etc/openvpn/scripts/add-api-route.sh

API_DOMAIN="api.ipify.org"
API_IP=$(host -t A $API_DOMAIN | grep "has address" | head -n1 | awk '{print $NF}')

if [ -n "$API_IP" ]; then
    ip route add $API_IP via $route_vpn_gateway
    echo "Added route for $API_DOMAIN ($API_IP) via VPN"
fi

exit 0
```

4. Make the script executable: `sudo chmod +x /etc/openvpn/scripts/add-api-route.sh`

## Android Client Configuration

For Android devices:

1. Install the official OpenVPN Connect app from the Google Play Store
2. Create a custom `.ovpn` file with the following content:

```
client
dev tun
proto udp
remote <YOUR_VPN_SERVER_IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca [inline]
cert [inline]
key [inline]
cipher AES-256-CBC
auth SHA256
verb 3

# Use specific route for api.ipify.org only
route api.ipify.org 255.255.255.255
# Do not use VPN as default gateway
route-nopull

<ca>
-----BEGIN CERTIFICATE-----
... (paste your CA certificate here) ...
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
... (paste your client certificate here) ...
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
... (paste your client private key here) ...
-----END PRIVATE KEY-----
</key>
```

3. Import this `.ovpn` file into the OpenVPN Connect app.
4. In the app settings, enable "Connect through" and select "VPN for selected apps only"
5. Add your applications that need to use the API routing

## iOS Client Configuration

For iOS devices:

1. Install the OpenVPN Connect app from the App Store
2. Create a custom `.ovpn` file similar to the Android configuration:

```
client
dev tun
proto udp
remote <YOUR_VPN_SERVER_IP> 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca [inline]
cert [inline]
key [inline]
cipher AES-256-CBC
auth SHA256
verb 3

# Use specific route for api.ipify.org only
route api.ipify.org 255.255.255.255
# Do not use VPN as default gateway
route-nopull

<ca>
-----BEGIN CERTIFICATE-----
... (paste your CA certificate here) ...
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
... (paste your client certificate here) ...
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
... (paste your client private key here) ...
-----END PRIVATE KEY-----
</key>
```

3. Import this configuration using iTunes File Sharing, email, or another file transfer method
4. In the OpenVPN app, connect to the VPN
5. For iOS Split Tunneling, go to Settings in the OpenVPN app and enable "Allow Local Network Access"

## Custom Domain Configuration

If you need to route traffic for a domain other than api.ipify.org:

1. Edit the `api_routing_setup.sh` script:

   - Change the `API_TARGET` variable to your custom domain
   - Run the script to update the configuration

2. For clients, update the route directive to use your custom domain:

   ```
   route your-custom-domain.com 255.255.255.255
   ```

3. Make sure the NGINX configuration is updated to proxy your custom domain.

## Troubleshooting Guide

### Common Issues and Solutions

#### Connection Issues

1. **VPN Connection Fails**:

   - Verify server IP address and port are correct
   - Check that certificates are valid and properly formatted
   - Ensure no firewalls are blocking OpenVPN traffic

2. **Cannot Access API through VPN**:

   - Verify routing table is properly configured using `ip route show table apiroutes`
   - Ensure the learn-address script is being called with `journalctl | grep learn-address`
   - Check that the API domain resolves with `host api.ipify.org`

3. **Mikrotik Router Shows Connected but No Routing**:
   - Verify IP forwarding is enabled
   - Check route exists with `/ip route print where dst-address=api.ipify.org/32`
   - Try manually adding route `/ip route add dst-address=api.ipify.org/32 gateway=<VPN_SERVER_IP>`

#### Testing API Routing

To verify your configuration is working correctly:

1. **Basic Test**:

   ```bash
   curl http://api.ipify.org?format=json
   ```

2. **Checking Route**:

   ```bash
   traceroute api.ipify.org
   ```

   The first hop should go through the VPN interface

3. **DNS Resolution**:

   ```bash
   host api.ipify.org
   ```

   Ensure it resolves to the correct IP address

4. **Advanced Verification**:
   Run the included verification scripts:
   ```bash
   /usr/local/bin/check-api-routing.sh 10
   ```

### Monitoring and Maintenance

1. **Check Active Routers**:

   ```bash
   cat /etc/openvpn/active_routers
   ```

2. **View Routing Table**:

   ```bash
   ip route show table apiroutes
   ```

3. **Check Routing Rules**:

   ```bash
   ip rule show | grep api
   ```

4. **Restart Routing When Needed**:

   ```bash
   systemctl restart api-routing.service
   ```

5. **View Logs**:
   ```bash
   tail -f /var/log/api_routing/learn-address.log
   ```
