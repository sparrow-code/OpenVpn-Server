# OpenVPN API Routing Solution

A specialized OpenVPN configuration that enables selective routing of API traffic through MikroTik routers using NAT-Based Transparent Proxy Routing.

## Overview

This project provides scripts and configurations to route traffic for specific API domains (like api.ipify.org) through MikroTik routers connected via OpenVPN. This setup is useful for scenarios where you need to distribute API requests across different IP addresses.

Key features:

- Traffic to specific API domains is routed through OpenVPN-connected MikroTik routers
- Uses NAT-Based Transparent Proxy technique (more reliable than direct routing)
- Simple configuration and maintenance
- Support for custom domains

## NAT-Based Transparent Proxy Routing Technique

This solution uses a specialized technique that avoids common routing issues:

1. **No Gateway Issues**: Avoids the "Nexthop has invalid gateway" error by using NAT instead of direct routing
2. **IP-Based Rules**: Uses IP addresses instead of domain names in routing rules
3. **Transparent to Applications**: Applications don't need any special configuration
4. **Resilient to IP Changes**: Can be easily updated when API IPs change

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

### Setup Instructions

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/openvpn-api-routing.git
   cd openvpn-api-routing/apiRouting
   ```

2. Run the NAT-based proxy routing script:

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

### Adding Custom Domains

To route traffic for domains other than api.ipify.org:

```bash
sudo bash custom_domain_setup.sh your-custom-domain.com [port]
```

## Troubleshooting

See the troubleshooting.md file for common issues and solutions.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- OpenVPN community
- MikroTik for their flexible routing capabilities
- api.ipify.org for providing a simple IP testing API
