# OpenVPN Server Setup for RouterOS

A comprehensive bash script collection for easy deployment and management of OpenVPN servers specifically tailored for RouterOS clients.

## Features

- **Automated Server Setup**: Complete OpenVPN server deployment with a single script
- **Certificate Management**: Easy generation and management of client certificates
- **RouterOS Integration**: Optimized for MikroTik RouterOS clients
- **Smart Detection**: Automatically detects existing installations and setup state
- **Flexible Configuration**: Customizable subnet, port, and client settings
- **Guided Process**: Interactive prompts guide you through the setup process
- **OVPN File Generation**: Generate ready-to-use .ovpn configuration files for standard OpenVPN clients

## Prerequisites

- Ubuntu 18.04+ or Debian 10+ server
- Root or sudo privileges
- Basic knowledge of networking concepts
- RouterOS device (for client connection)

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/openvpn-routeros-setup.git
   cd openvpn-routeros-setup
   ```

2. Make the scripts executable:
   ```bash
   chmod +x setupVpn.sh get_vpn.sh
   ```

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
6. Prepare client certificates for RouterOS

Follow the interactive prompts to complete the setup.

### Client Management

After initial setup, running the script again will enter client management mode where you can:

1. Create new client certificates
2. Regenerate existing client certificates
3. List all client certificates
4. Exit the management interface

### Generating OVPN Configuration Files

For standard OpenVPN clients (not RouterOS), you can generate ready-to-use .ovpn configuration files:

```bash
sudo ./get_vpn.sh
```

The script will:

1. List all available client certificates
2. Let you select which client to create a configuration for
3. Generate a complete .ovpn file with embedded certificates
4. Save the file to `/home/itguy/vpn/ovpn_configs/` directory

## File Structure

```
openvpn-routeros-setup/
├── setupVpn.sh            # Main script
├── get_vpn.sh             # OVPN configuration generator
├── routerOs.sh            # RouterOS configuration guide
├── README.md              # This documentation
└── functions/             # Module functions
    ├── certificate_management.sh
    ├── configure_server.sh
    ├── create_additional_clients.sh
    ├── detect_setup_state.sh
    ├── install_packages.sh
    ├── prepare_client.sh
    ├── setup_certificates.sh
    ├── setup_easyrsa.sh
    ├── setup_network.sh
    └── utils.sh
```

## Configuration Options

During setup, you'll be prompted for:

- **Server IP Address**: Your cloud server's public IP
- **VPN Port**: Port for OpenVPN (default: 1194)
- **VPN Subnet**: Internal VPN subnet (default: 10.8.0.0/24)
- **Client Name**: Name for the initial RouterOS client certificate

## RouterOS Client Configuration

After generating certificates, you'll need to:

1. Transfer certificate files to your RouterOS device:

   - ca.crt
   - [client_name].crt
   - [client_name].key

2. Import certificates in RouterOS and configure the OpenVPN client

Detailed instructions are provided in `routerOs.sh`.

## Standard OpenVPN Client Configuration

For standard OpenVPN clients (Windows, Linux, Android, iOS, etc.):

1. Generate the .ovpn file using `get_vpn.sh`
2. Transfer the .ovpn file to your client device
3. Import the .ovpn file into your OpenVPN client application

## Troubleshooting

### Common Issues

- **Connection Refused**: Check that the server port is open in your firewall
- **TLS Handshake Failed**: Verify certificate paths and permissions
- **Routing Problems**: Check IP forwarding settings

Run the script again to verify the setup state and correct any issues.

## Security Considerations

- The default configuration provides strong security with AES-256-CBC encryption
- Keep your certificate files secure; anyone with your client certificates can connect to your VPN
- Consider implementing additional firewall rules for production environments

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
