#!/bin/bash
# Comprehensive script to completely uninstall OpenVPN and all associated components
# Run this script with root privileges (sudo)

set -e

# Function to display progress
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

log "Starting complete OpenVPN uninstallation process..."
log "This will remove OpenVPN, all configurations, certificates, and API routing components."

# Ask for confirmation before proceeding
echo -n "Are you sure you want to completely remove OpenVPN and all its components? (y/n): "
read -r confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    log "Uninstallation aborted."
    exit 0
fi

# 1. First remove API routing components if present
log "Removing API routing components if present..."

# 1.1. Stop and remove API routing systemd services
for service in api-routing.service api-tun-bridge.service; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        log "Stopping $service..."
        systemctl stop $service
    fi
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        log "Disabling $service..."
        systemctl disable $service
    fi
    if [ -f /etc/systemd/system/$service ]; then
        log "Removing $service file..."
        rm -f /etc/systemd/system/$service
    fi
done

# 1.2. Remove API routing cron jobs
log "Removing API routing cron jobs..."
rm -f /etc/cron.d/api-ip-monitor
rm -f /etc/cron.d/api-route-monitor
rm -f /etc/cron.d/domain-health-check

# 1.3. Remove API routing rules and tables
log "Cleaning up API routing configuration..."
if command -v ip &>/dev/null; then
    API_TARGETS=("api.ipify.org")
    ROUTING_TABLE="apiroutes"

    # Check for custom domains
    if [ -f /etc/openvpn/scripts/learn-address.sh ]; then
        CUSTOM_API=$(grep "API_TARGET=" /etc/openvpn/scripts/learn-address.sh | cut -d'"' -f2)
        if [ -n "$CUSTOM_API" ] && [ "$CUSTOM_API" != "api.ipify.org" ]; then
            API_TARGETS+=("$CUSTOM_API")
        fi
    fi

    # Remove routing rules for all API targets
    for target in "${API_TARGETS[@]}"; do
        log "Removing routing rules for $target..."
        if command -v ip &>/dev/null; then
            ip rule show 2>/dev/null | grep -E "to $target lookup $ROUTING_TABLE" | while read -r rule; do
                rule_num=$(echo "$rule" | awk '{print $1}' | sed 's/://')
                ip rule del prio "$rule_num" 2>/dev/null || true
            done
            
            # Try to resolve the target to get its IP
            if command -v host &>/dev/null; then
                target_ip=$(host -t A "$target" 2>/dev/null | grep "has address" | head -n1 | awk '{print $NF}' || echo "")
                if [ -n "$target_ip" ]; then
                    log "Removing routing rules for IP $target_ip..."
                    ip rule show 2>/dev/null | grep -E "to $target_ip lookup $ROUTING_TABLE" | while read -r rule; do
                        rule_num=$(echo "$rule" | awk '{print $1}' | sed 's/://')
                        ip rule del prio "$rule_num" 2>/dev/null || true
                    done
                fi
            fi
        fi
    done

    # Flush the apiroutes table
    if [ -f /etc/iproute2/rt_tables ] && grep -q "$ROUTING_TABLE" /etc/iproute2/rt_tables; then
        log "Flushing and removing $ROUTING_TABLE routing table..."
        ip route flush table "$ROUTING_TABLE" 2>/dev/null || true
        
        # Remove the table entry
        grep -v "$ROUTING_TABLE" /etc/iproute2/rt_tables > /tmp/rt_tables.new
        mv /tmp/rt_tables.new /etc/iproute2/rt_tables
    fi
fi

# 1.4. Clean up NAT rules if iptables is available
if command -v iptables &>/dev/null; then
    log "Cleaning up API NAT rules..."
    # Find and remove the apiRouting NAT rules
    for target in "${API_TARGETS[@]}"; do
        if command -v host &>/dev/null; then
            target_ip=$(host -t A "$target" 2>/dev/null | grep "has address" | head -n1 | awk '{print $NF}' || echo "")
            if [ -n "$target_ip" ]; then
                log "Removing NAT rules for $target_ip..."
                iptables -t nat -S PREROUTING 2>/dev/null | grep -E -- "-d $target_ip" | while read -r rule; do
                    modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
                    iptables -t nat $modified_rule 2>/dev/null || true
                done
                
                iptables -t nat -S POSTROUTING 2>/dev/null | grep -E -- "-d $target_ip" | while read -r rule; do
                    modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
                    iptables -t nat $modified_rule 2>/dev/null || true
                done
            fi
        fi
    done

    # Clean up rules mentioning common VPN IPs
    for vpn_ip in "10.8.0.1" "10.8.0.6"; do
        log "Removing NAT rules for VPN IP $vpn_ip..."
        iptables -t nat -S 2>/dev/null | grep -E -- "$vpn_ip" | while read -r rule; do
            chain=$(echo "$rule" | awk '{print $2}')
            if [[ "$chain" == "PREROUTING" || "$chain" == "POSTROUTING" ]]; then
                modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
                iptables -t nat $modified_rule 2>/dev/null || true
            fi
        done
    done
fi

# 1.5. Remove API network bridge if it exists
log "Checking for API network bridges..."
BRIDGE_NAME="br-apiroute"
if command -v brctl &>/dev/null && brctl show 2>/dev/null | grep -q "$BRIDGE_NAME"; then
    log "Removing $BRIDGE_NAME bridge..."
    ip link set "$BRIDGE_NAME" down 2>/dev/null || true
    brctl delbr "$BRIDGE_NAME" 2>/dev/null || true
    log "Network bridge removed."
fi

# 2. Stop and disable OpenVPN service
log "Stopping and disabling OpenVPN service..."
# Handle both systemd and init.d systems
if command -v systemctl &>/dev/null; then
    # For systemd systems
    for service in openvpn@server.service openvpn.service; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            log "Stopping $service..."
            systemctl stop $service
        fi
        if systemctl is-enabled --quiet $service 2>/dev/null; then
            log "Disabling $service..."
            systemctl disable $service
        fi
    done
elif [ -f /etc/init.d/openvpn ]; then
    # For older init.d systems
    log "Stopping OpenVPN via init.d..."
    /etc/init.d/openvpn stop
    update-rc.d -f openvpn remove
fi

# 3. Remove OpenVPN packages based on the package manager
log "Removing OpenVPN packages..."
if command -v apt-get &>/dev/null; then
    # Debian/Ubuntu
    log "Detected Debian/Ubuntu. Removing packages via apt..."
    apt-get -y remove --purge openvpn easy-rsa
    apt-get -y autoremove
    apt-get -y clean
elif command -v yum &>/dev/null; then
    # CentOS/RHEL
    log "Detected CentOS/RHEL. Removing packages via yum..."
    yum -y remove openvpn easy-rsa
    yum -y autoremove
    yum clean all
elif command -v dnf &>/dev/null; then
    # Fedora/newer RHEL
    log "Detected Fedora/newer RHEL. Removing packages via dnf..."
    dnf -y remove openvpn easy-rsa
    dnf -y autoremove
    dnf clean all
elif command -v pacman &>/dev/null; then
    # Arch Linux
    log "Detected Arch Linux. Removing packages via pacman..."
    pacman -Rs --noconfirm openvpn easy-rsa
    pacman -Scc --noconfirm
fi

# 4. Remove all OpenVPN configuration files, scripts, and directories
log "Removing OpenVPN configuration files and directories..."

# 4.1 Remove main OpenVPN directories
rm -rf /etc/openvpn
rm -rf /usr/share/doc/openvpn*
rm -rf /var/log/openvpn

# 4.2 Remove EasyRSA files if they exist
rm -rf /etc/easy-rsa
rm -rf /usr/share/easy-rsa
rm -rf /root/easy-rsa

# 4.3 Remove API routing scripts and log directories
rm -rf /etc/openvpn/scripts
rm -rf /var/log/api_routing
rm -f /etc/openvpn/active_routers

# 4.4 Remove verification and monitoring scripts
rm -f /usr/local/bin/test-api-routing.sh
rm -f /usr/local/bin/check-api-routing.sh
rm -f /usr/local/bin/verify-routing.js
rm -f /usr/local/bin/check-outgoing-ip.sh
rm -f /usr/local/bin/monitor-api-routes.sh
rm -f /usr/local/bin/check-domain-health.sh
rm -f /usr/local/bin/enhanced-test-api-routing.sh

# 5. Remove NGINX configurations related to API routing
log "Cleaning up NGINX configurations if present..."
if [ -d /etc/nginx/conf.d ]; then
    rm -f /etc/nginx/conf.d/api-ipify-proxy.conf
    rm -f /etc/nginx/conf.d/custom-api-proxy.conf
    
    # Reload NGINX if it's running
    if command -v systemctl &>/dev/null && systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl reload nginx
        log "NGINX configuration reloaded."
    elif [ -f /etc/init.d/nginx ]; then
        /etc/init.d/nginx reload
        log "NGINX configuration reloaded."
    fi
fi

# 6. Clean up networking configurations
log "Cleaning up networking configurations..."

# 6.1 Remove TUN/TAP devices if they exist
for tun in /dev/net/tun*; do
    if [ -c "$tun" ]; then
        log "Found TUN device: $tun"
        # We don't usually delete the devices, just note their presence
    fi
done

# 6.2 Clean up iptables rules related to OpenVPN
if command -v iptables &>/dev/null; then
    log "Cleaning up iptables rules..."
    
    # Clean up NAT masquerade rules for common OpenVPN subnet
    iptables -t nat -S POSTROUTING 2>/dev/null | grep -E "10.8.0.0/24" | while read -r rule; do
        modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
        iptables -t nat $modified_rule 2>/dev/null || true
    done
    
    # Clean up forward rules for OpenVPN
    iptables -S FORWARD 2>/dev/null | grep -E "tun|openvpn|10.8.0.0/24" | while read -r rule; do
        modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
        iptables $modified_rule 2>/dev/null || true
    done
fi

# 6.3 Remove IP forwarding configuration if it was set for OpenVPN
if [ -f /etc/sysctl.d/99-ip-forward.conf ]; then
    log "Removing IP forwarding configuration..."
    rm -f /etc/sysctl.d/99-ip-forward.conf
    
    # Optionally reset ip_forward to default (0)
    # Uncomment the line below if you want to disable IP forwarding
    # echo 0 > /proc/sys/net/ipv4/ip_forward
    log "Note: IP forwarding settings have not been reset to 0, as other services might need it."
fi

# 7. Check for and remove any client config files that might be in common locations
log "Removing any OpenVPN client configurations..."
rm -f /home/*/*.ovpn
rm -f /home/*/*/*.ovpn
rm -f /root/*.ovpn
rm -f /root/*/*.ovpn

# 8. Restart networking to ensure all changes take effect
log "Restarting networking services..."
if command -v systemctl &>/dev/null; then
    systemctl restart networking.service 2>/dev/null || true
    systemctl restart NetworkManager.service 2>/dev/null || true
elif [ -f /etc/init.d/networking ]; then
    /etc/init.d/networking restart
fi

log "OpenVPN has been completely removed from the system."
log "All configuration files, certificates, keys, and API routing components have been deleted."
echo ""
echo "===== UNINSTALLATION COMPLETE ====="
echo "OpenVPN has been fully uninstalled from your server."
echo "Any custom firewall rules or routing configurations you had may need manual review."
echo ""
