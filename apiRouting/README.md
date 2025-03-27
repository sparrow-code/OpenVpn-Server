# OpenVPN API Routing Solution

A specialized OpenVPN configuration that enables selective routing of API traffic through multiple MikroTik routers, providing IP address rotation and failover capabilities.

## Overview

This project provides scripts and configurations to route traffic for specific API domains (like api.ipify.org) through multiple MikroTik routers connected via OpenVPN. This setup is useful for scenarios where you need to distribute API requests across different IP addresses or ensure high availability for critical API traffic.

Key features:

- Traffic to specific domains is routed through OpenVPN-connected MikroTik routers
- Automatic IP address rotation for API requests
- Self-healing routing table maintenance
- Monitoring and verification tools
- Support for custom domains

## Directory Structure

```
apiRouting/
├── api_routing_setup.sh      # Main setup script
├── custom_domain_setup.sh    # Script to add custom domains
├── verify-routing.js         # Node.js verification script
├── check-api-routing.sh      # Bash verification script (created by setup script)
├── dashboard.html            # Web-based monitoring dashboard
├── api-monitor.js            # Backend API for dashboard
├── client_configs_guide.md   # Client configuration guide
└── README.md                 # This file
```

## Installation

### Prerequisites

- Linux server with OpenVPN server installed
- NGINX web server (for domain proxying)
- Node.js (for verification scripts)
- MikroTik routers with OpenVPN client capability

### Setup Instructions

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/openvpn-api-routing.git
   cd openvpn-api-routing/apiRouting
   ```

2. Run the main setup script:

   ```bash
   sudo bash api_routing_setup.sh
   ```

3. Configure your MikroTik routers according to the generated `microtik_config.txt` file

4. Test the setup using the verification scripts:
   ```bash
   sudo /usr/local/bin/check-api-routing.sh 10
   ```

### Adding Custom Domains

To route traffic for domains other than api.ipify.org:

```bash
sudo bash custom_domain_setup.sh your-custom-domain.com [port]
```

## Client Configuration

MikroTik routers require minimal setup. For details, see the `client_configs_guide.md` file.
Example for MikroTik:

```
/interface ovpn-client
add connect-to=<YOUR_VPN_SERVER_IP> name=ovpn-out1 port=1194 \
    user=mikrotik_router1 password=<YOUR_PASSWORD> \
    mode=ip add-default-route=no

/ip route
add dst-address=api.ipify.org/32 gateway=<VPN_SERVER_INTERNAL_IP> distance=1
```

## Monitoring

### Command-Line Tools

1. Check API routing:

   ```bash
   sudo /usr/local/bin/check-api-routing.sh 10
   ```

2. Node.js verification:

   ```bash
   node /usr/local/bin/verify-routing.js 20
   ```

3. Check active routers:

   ```bash
   cat /etc/openvpn/active_routers
   ```

4. View logs:
   ```bash
   tail -f /var/log/api_routing/learn-address.log
   ```

### Web Dashboard

We provide a web-based dashboard for real-time monitoring:

1. Start the dashboard backend:

   ```bash
   node api-monitor.js
   ```

2. Access the dashboard at http://your-server-ip:3000

## Self-Healing Capabilities

The setup includes several self-healing mechanisms:

1. Automatic routing table recovery
2. Connection monitoring for MikroTik routers
3. Regular health checks for API endpoints
4. Automatic failover between multiple routers

## Advanced Configuration

### Modifying IP Rotation Strategy

By default, we use a time-based metric for IP rotation. You can modify this behavior by editing the `learn-address.sh` script.

### Custom Domains

The solution supports routing different API domains through different routers. See `custom_domain_setup.sh` for details.

### Scaling

To add more routers, simply:

1. Create additional OpenVPN clients with names starting with "mikrotik\_"
2. Connect them to your OpenVPN server
3. The system will automatically use them for API routing

## Troubleshooting

See the troubleshooting section in `client_configs_guide.md` for common issues and solutions.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- OpenVPN community
- MikroTik for their flexible routing capabilities
- api.ipify.org for providing a simple IP testing API
