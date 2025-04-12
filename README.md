# OpenVPN Server Setup

A comprehensive bash script collection for easy deployment and management of OpenVPN servers with robust security features.

## Features

- **Automated Server Setup**: Complete OpenVPN server deployment with a single script
- **Certificate Management**: Easy generation and management of client certificates
- **Smart Detection**: Automatically detects existing installations and setup state
- **Flexible Configuration**: Customizable subnet, port, and client settings
- **Protocol Switching**: Easily switch between UDP and TCP protocols
- **Guided Process**: Interactive prompts guide you through the setup process
- **OVPN File Generation**: Generate ready-to-use .ovpn configuration files for clients
- **Diagnostics**: Built-in tools for troubleshooting connection issues

## Prerequisites

- Ubuntu 18.04+ or Debian 10+ server
- Root or sudo privileges
- Basic knowledge of networking concepts

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/sparrow-code/OpenVpn-Server.git
   cd OpenVpn-Server
   ```

2. Make the scripts executable:

   ```bash
   chmod +x *.sh
   ```

3. Run the main setup script:

   ```bash
   sudo ./setupVpn.sh
   ```

   Follow the interactive prompts to complete the setup.

## Usage

### Initial Setup

Run the main setup script:

```bash
./setupVpn.sh
```

The script will:

1. Install necessary packages
2. Set up Easy-RSA for certificate management
3. Generate server and initial client certificates
4. Configure the OpenVPN server
5. Set up proper network routing
6. Prepare client certificates

### Client Management

After initial setup, running the script again will enter client management mode where you can:

1. Create new client certificates
2. Regenerate existing client certificates
3. List all client certificates
4. Exit the management interface

### Generating OVPN Configuration Files

For clients, you can generate ready-to-use .ovpn configuration files:

```bash
sudo ./get_vpn.sh
```

The script will:

1. List all available client certificates
2. Let you select which client to create a configuration for
3. Generate a complete .ovpn file with embedded certificates
4. Save the file to an accessible directory

### Server Management

The `vpn_manager.sh` script provides a comprehensive interface for managing your OpenVPN server:

```bash
sudo ./vpn_manager.sh
```

Features include:
- Server status monitoring
- Client certificate management
- Protocol switching (TCP/UDP)
- Diagnostics and troubleshooting
- Firewall configuration

## File Structure

```
OpenVpn-Server/
├── setupVpn.sh            # Main setup script
├── get_vpn.sh             # OVPN configuration generator
├── vpn_manager.sh         # Server management interface
├── vpn_diagnostics.sh     # Diagnostics script
├── vpn_troubleshoot.sh    # Troubleshooting utilities
├── README.md              # Documentation
├── functions/             # Module functions
│   ├── certificate_management.sh
│   ├── configure_server.sh
│   ├── create_additional_clients.sh
│   ├── detect_setup_state.sh
│   ├── install_packages.sh
│   ├── prepare_client.sh
│   ├── setup_certificates.sh
│   ├── setup_easyrsa.sh
│   ├── setup_network.sh
│   └── utils.sh
└── utils/                 # Utility scripts
    ├── switch_btw_protocol.sh
    ├── switch_protocol.sh
    ├── switch_to_tcp.sh
    ├── switch_to_udp.sh
    ├── uninstall_openvpn_complete.sh
    ├── vpn_diagnostics.sh
    ├── vpn_killswitch.sh
    └── vpn_troubleshoot.sh
```

## Configuration Options

During setup, you'll be prompted for:

- **Server IP Address**: Your server's public IP address
- **VPN Port**: Port for OpenVPN (default: 1194)
- **VPN Subnet**: Internal VPN subnet (default: 10.8.0.0/24)
- **Client Name**: Name for the initial client certificate

## Advanced Features

### Protocol Switching

You can easily switch between UDP and TCP protocols:

```bash
# Switch to TCP
sudo ./utils/switch_to_tcp.sh

# Switch to UDP
sudo ./utils/switch_to_udp.sh
```

### Diagnostics

The built-in diagnostics tool helps identify common issues:

```bash
sudo ./vpn_diagnostics.sh
```

This checks:
- Service status
- IP forwarding
- Firewall rules
- DNS resolution
- VPN tunnel setup
- Internet access through VPN

### Firewall Configuration

The setup automatically configures necessary firewall rules, including:
- Port forwarding
- NAT configuration
- IP masquerading

## Troubleshooting

### Common Issues

- **Connection Refused**: Check that the server port is open in your firewall
- **TLS Handshake Failed**: Verify certificate paths and permissions
- **Routing Problems**: Check IP forwarding settings
- **DNS Issues**: Verify DNS settings in the OpenVPN configuration

Run the diagnostics script to automatically identify and fix common issues:

```bash
sudo ./vpn_diagnostics.sh
```

## Security Considerations

- The default configuration provides strong security with AES-256-CBC encryption
- Keep your certificate files secure; anyone with your client certificates can connect to your VPN
- Consider implementing additional firewall rules for production environments
- Regularly update your server and OpenVPN installation
- Consider implementing certificate revocation for compromised clients

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- The OpenVPN team for their excellent VPN software
- The Easy-RSA project for certificate management tools
- All contributors who have helped improve this project
