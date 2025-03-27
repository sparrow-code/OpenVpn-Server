# OpenVPN API Routing Solution

A specialized OpenVPN configuration that enables selective routing of API traffic through MikroTik routers using multiple proven techniques.

## Overview

This project provides scripts and configurations to route traffic for specific API domains (like api.ipify.org) through MikroTik routers connected via OpenVPN. This setup is useful for scenarios where you need to distribute API requests across different IP addresses.

Key features:

- Traffic to specific API domains is routed through OpenVPN-connected MikroTik routers
- Multiple routing techniques to handle different network environments
- Simple configuration and maintenance
- Support for custom domains

## Available Routing Techniques

This solution offers three different routing methods to ensure compatibility with any environment:

### 1. NAT-Based Transparent Proxy (Default)

```
[Client] → [OpenVPN Server] → DNAT → [MikroTik Router] → [API Service]
```

Uses NAT rules to redirect traffic, avoiding common routing issues. This is our default approach as it's the most reliable across different environments.

**Advantages:**

- No "Nexthop has invalid gateway" errors
- Works with complex firewall configurations
- Simple to implement and maintain

### 2. Direct TUN Bridging (Advanced)

```
[Client] → [OpenVPN Server] → [TUN Bridge] → [MikroTik Router] → [API Service]
```

For environments where NAT is problematic, this technique creates a direct Layer 2 bridge between the TUN interface and the MikroTik router.

**Advantages:**

- Lower latency than NAT
- No connection tracking overhead
- More transparent network path

### 3. SOCKS Proxy Method (Fallback)

```
[Client] → [OpenVPN Server] → [Local SOCKS Proxy] → [MikroTik Router] → [API Service]
```

This method establishes a SOCKS proxy on the OpenVPN server that forwards connections through the MikroTik router.

**Advantages:**

- Works even with strict firewalls
- No special routing required
- Compatible with any client that supports SOCKS

## Directory Structure

```
apiRouting/
├── nat-proxy-routing.sh         # Main script implementing NAT-based proxy routing
├── custom_domain_setup.sh       # Script to add custom domains
├── verify-routing.js            # Node.js verification script
├── test-api-routing.sh          # Simple testing script
├── troubleshooting.md           # Troubleshooting guide
├── client_configs_guide.md      # Client configuration guide
└── README.md                    # This file
```

## Installation

### Prerequisites

- Linux server with OpenVPN server installed
- MikroTik router with OpenVPN client capability

### Basic Setup (NAT Method)

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/openvpn-api-routing.git
   cd openvpn-api-routing/apiRouting
   ```

2. Run the setup script with default NAT method:

   ```bash
   sudo bash nat-proxy-routing.sh
   ```

3. Configure your MikroTik router using the generated commands:

   - Copy and paste each command ONE BY ONE from the generated mikrotik-router-commands.txt file
   - Apply them to your MikroTik router via its terminal interface

4. Restart OpenVPN:

   ```bash
   sudo systemctl restart openvpn
   ```

5. Test the setup:
   ```bash
   ./test-api-routing.sh
   ```

### Advanced TUN Bridging Setup

If the NAT method doesn't work in your environment, try the TUN bridging approach:

```bash
sudo bash tun-bridge-routing.sh
```

Then follow the router configuration instructions displayed.

### SOCKS Proxy Setup (Last Resort)

If both previous methods fail:

```bash
sudo bash socks-proxy-routing.sh
```

## Troubleshooting

See the troubleshooting.md file for common issues and solutions. If you're still having issues:

1. Try the alternative routing methods described above
2. Ensure your MikroTik router is properly connected to the VPN
3. Check firewall rules on both server and router
4. Verify the API IP hasn't changed (some APIs rotate IPs frequently)

## Special Router Configurations

For complex firewall setups on MikroTik routers, use our specialized configurations:

```bash
sudo bash generate-mikrotik-config.sh --firewall-compatible
```

This generates router commands that work alongside existing firewall rules.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- OpenVPN community
- MikroTik for their flexible routing capabilities
- api.ipify.org for providing a simple IP testing API
