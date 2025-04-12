#!/bin/bash

# This script removes all OpenVPN configurations, logs, and setups, restoring the server to a fresh state.

# Stop OpenVPN service if running
if systemctl is-active --quiet openvpn@server || systemctl is-active --quiet openvpn; then
    echo "Stopping OpenVPN service..."
    systemctl stop openvpn@server || systemctl stop openvpn
fi

# Remove OpenVPN configuration files
CONFIG_DIR="/etc/openvpn"
if [ -d "$CONFIG_DIR" ]; then
    echo "Removing OpenVPN configuration directory: $CONFIG_DIR"
    rm -rf "$CONFIG_DIR"
else
    echo "No OpenVPN configuration directory found."
fi

# Remove OpenVPN log files
LOG_DIR="/var/log/openvpn"
if [ -d "$LOG_DIR" ]; then
    echo "Removing OpenVPN log directory: $LOG_DIR"
    rm -rf "$LOG_DIR"
else
    echo "No OpenVPN log directory found."
fi

# Remove OpenVPN binaries
if command -v openvpn &> /dev/null; then
    echo "Removing OpenVPN binaries..."
    apt-get remove --purge -y openvpn
else
    echo "OpenVPN is not installed."
fi

# Remove any additional OpenVPN-related files
ADDITIONAL_FILES=(
    "/usr/share/doc/openvpn"
    "/var/lib/openvpn"
)
for FILE in "${ADDITIONAL_FILES[@]}"; do
    if [ -e "$FILE" ]; then
        echo "Removing $FILE"
        rm -rf "$FILE"
    fi
done

# Clean up any residual dependencies
echo "Cleaning up residual dependencies..."
apt-get autoremove -y

# Final message
echo "OpenVPN has been completely removed, and the server is restored to a fresh state."
