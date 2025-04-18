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

## Setting Up on a New VPS

### Step 1: Initial VPS Configuration

1. Log in to your VPS via SSH:
   ```bash
   ssh root@your_vps_ip_address
   ```

2. Update the system and install git:
   ```bash
   apt update && apt upgrade -y
   apt install git -y
   ```

3. Secure your server (recommended):
   ```bash
   # Create a new user with sudo privileges
   adduser yourusername
   usermod -aG sudo yourusername
   
   # Configure SSH (optional but recommended)
   nano /etc/ssh/sshd_config
   # Set: PermitRootLogin no
   # Set: PasswordAuthentication no (if using SSH keys)
   systemctl restart sshd
   ```

### Step 2: OpenVPN Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/sparrow-code/OpenVpn-Server.git
   cd OpenVpn-Server
   ```

2. Make the scripts executable:
   ```bash
   chmod +x *.sh
   chmod +x utils/*.sh
   chmod +x functions/*.sh
   ```

3. Run the main setup script:
   ```bash
   sudo ./setupVpn.sh
   ```

4. Follow the interactive prompts to complete the setup:
   - Select a port for OpenVPN (default: 1194)
   - Choose between UDP (faster, default) or TCP (more reliable)
   - Enter the first client name
   - Verify your external IP address
   - Confirm your selections

## Post-Installation Management

### All-in-One Management Interface

After installing OpenVPN, simply use the comprehensive management interface:

```bash
sudo ./vpn_manager.sh
```

This central interface provides access to all OpenVPN management functions:

- **Server Status**: Monitor service status and connected clients
- **Client Management**: Create, revoke, and manage client certificates
- **Server Configuration**: Change ports, protocols, and settings
- **Diagnostics & Troubleshooting**: Identify and fix connection issues
- **Protocol Switching**: Easily switch between TCP and UDP
- **Configuration Generation**: Create .ovpn files for clients

### Transferring Configuration Files

After generating client configurations, transfer the .ovpn file securely to your client device:
```bash
# From your local machine (not the VPS)
scp username@your_vps_ip:~/ovpns/clientname.ovpn .
```

### Quick Solutions for Common Tasks

| Task | Solution |
|------|----------|
| **View server status** | Run `vpn_manager.sh` → Select "View OpenVPN Status" |
| **Create a new client** | Run `vpn_manager.sh` → Select "Create New Client" |
| **Switch protocol** | Run `vpn_manager.sh` → Select "Diagnostics & Troubleshooting" → "Switch between TCP/UDP Protocol" |
| **Troubleshoot issues** | Run `vpn_manager.sh` → Select "Diagnostics & Troubleshooting" |

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

You can easily switch between UDP and TCP protocols using the consolidated protocol switching script:

```bash
# Switch to TCP
sudo ./utils/switch_btw_protocol.sh tcp

# Switch to UDP
sudo ./utils/switch_btw_protocol.sh udp
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
