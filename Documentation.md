# OpenVPN Server Documentation

This document provides detailed technical information about the OpenVPN server setup, configuration, and management.

## 1. Installation Process

The installation script (`setupVpn.sh`) performs the following operations:

1. Updates the package repository
2. Installs OpenVPN and Easy-RSA packages
3. Sets up the PKI (Public Key Infrastructure)
4. Creates server and client certificates
5. Configures the OpenVPN server
6. Sets up network forwarding and firewall rules
7. Generates client configuration files

## 2. Certificate Management

### Certificate Authority (CA)

The setup creates a Certificate Authority (CA) using Easy-RSA with the following steps:

```bash
# Initialize PKI
./easyrsa init-pki

# Build CA
./easyrsa build-ca nopass

# Generate Diffie-Hellman parameters
./easyrsa gen-dh

# Generate server certificate and key
./easyrsa build-server-full server nopass

# Generate client certificate and key
./easyrsa build-client-full client_name nopass
```

### Certificate Locations

- CA Certificate: `~/easy-rsa/pki/ca.crt`
- Server Certificate: `~/easy-rsa/pki/issued/server.crt`
- Server Key: `~/easy-rsa/pki/private/server.key`
- Client Certificate: `~/easy-rsa/pki/issued/[client_name].crt`
- Client Key: `~/easy-rsa/pki/private/[client_name].key`
- Diffie-Hellman Parameters: `~/easy-rsa/pki/dh.pem`

## 3. Server Configuration

The OpenVPN server is configured with secure defaults that can be customized during setup.

### Default Configuration Parameters

```
# Network settings
port 1194
proto udp
dev tun

# Cryptographic settings
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
cipher AES-256-CBC
auth SHA256

# Network configuration
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Performance and security
keepalive 10 120
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/status.log
verb 3
```

## 4. Protocol Switching

The scripts support switching between UDP and TCP protocols:

### UDP to TCP Conversion

The script `switch_to_tcp.sh` performs the following operations:

1. Creates a backup of the current configuration
2. Updates the protocol line to TCP
3. Adds TCP-specific optimizations
4. Updates firewall rules
5. Restarts the OpenVPN service

```bash
# Key configuration changes
sed -i 's/^proto udp/proto tcp/' /etc/openvpn/server.conf
echo "tcp-nodelay" >> /etc/openvpn/server.conf
```

### TCP to UDP Conversion

The script `switch_to_udp.sh` performs similar operations but for UDP:

```bash
# Key configuration changes
sed -i 's/^proto tcp/proto udp/' /etc/openvpn/server.conf
```

## 5. Client Configuration Files

The `get_vpn.sh` script generates complete .ovpn files for clients with embedded certificates:

```
client
dev tun
proto udp
remote server_ip 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
auth SHA256
key-direction 1
verb 3

<ca>
[CA CERTIFICATE CONTENTS]
</ca>

<cert>
[CLIENT CERTIFICATE CONTENTS]
</cert>

<key>
[CLIENT KEY CONTENTS]
</key>

<tls-auth>
[TLS AUTH KEY CONTENTS]
</tls-auth>
```

## 6. Network Configuration

The setup configures proper network forwarding and firewall rules for the VPN:

```bash
# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn.conf
sysctl -p

# Configure iptables for NAT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
```

## 7. Diagnostics and Troubleshooting

The `vpn_diagnostics.sh` script performs comprehensive checks:

1. Verifies the OpenVPN service status
2. Checks IP forwarding configuration
3. Validates firewall rules
4. Tests DNS resolution
5. Verifies VPN tunnel establishment
6. Tests internet access through the VPN
7. Inspects server configuration
8. Checks logs for errors

Common issues detected include:
- Missing NAT rules
- Disabled IP forwarding
- Incorrect firewall configuration
- DNS resolution problems
- Missing routes

## 8. VPN Manager

The `vpn_manager.sh` provides a comprehensive management interface with the following capabilities:

1. Display server status
2. Create new client certificates
3. Manage existing clients
4. Configure server settings
5. Run diagnostics and troubleshooting
6. View detailed status information

## 9. Security Considerations

The default configuration implements several security best practices:

- Strong encryption (AES-256-CBC)
- Strong authentication (SHA256)
- Certificate-based authentication
- User/group downgrade after initialization
- No password storage in configuration files
- Minimal required privileges

Additional security measures that can be implemented:
- TLS authentication (`tls-auth`)
- Certificate revocation
- Firewall restrictions
- Regular certificate rotation

## 10. Performance Optimization

The OpenVPN configuration includes several performance optimizations:

- Proper keepalive settings
- Compression disabled by default (better security)
- TCP-specific optimizations when using TCP protocol
- Persistent connections
- Connection status monitoring

For high-traffic scenarios, consider these additional optimizations:
- Increasing `tun-mtu` value
- Adjusting `fragment` value
- Using UDP protocol when possible
- Implementing multiple server instances
- Load balancing with multiple VPN servers
