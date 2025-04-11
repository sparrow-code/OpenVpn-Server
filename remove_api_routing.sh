#!/bin/bash
# Comprehensive script to remove all apiRouting functionality
# from an OpenVPN server installation
#
# Run this script with root privileges (sudo)
# Author: GitHub Copilot

set -e

# Function to display progress
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure user has root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

log "Starting apiRouting removal process..."

# 1. Stop and remove systemd services
log "Stopping and removing systemd services..."
for service in api-routing.service api-tun-bridge.service; do
    if systemctl is-active --quiet $service; then
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
systemctl daemon-reload
log "Services removed."

# 2. Remove cron jobs
log "Removing cron jobs..."
rm -f /etc/cron.d/api-ip-monitor
rm -f /etc/cron.d/api-route-monitor
rm -f /etc/cron.d/domain-health-check
log "Cron jobs removed."

# 3. Remove routing rules and tables
log "Cleaning up routing configuration..."
API_TARGETS=("api.ipify.org")
ROUTING_TABLE="apiroutes"

# Add any custom domains that might be in use
if [ -f /etc/openvpn/scripts/learn-address.sh ]; then
    CUSTOM_API=$(grep "API_TARGET=" /etc/openvpn/scripts/learn-address.sh | cut -d'"' -f2)
    if [ -n "$CUSTOM_API" ] && [ "$CUSTOM_API" != "api.ipify.org" ]; then
        API_TARGETS+=("$CUSTOM_API")
    fi
fi

# Remove routing rules for all API targets
for target in "${API_TARGETS[@]}"; do
    log "Removing routing rules for $target..."
    ip rule show | grep -E "to $target lookup $ROUTING_TABLE" | while read rule; do
        rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
        ip rule del prio $rule_num 2>/dev/null || true
    done
    
    # Try to resolve the target to get its IP
    target_ip=$(host -t A $target | grep "has address" | head -n1 | awk '{print $NF}' 2>/dev/null || echo "")
    if [ -n "$target_ip" ]; then
        log "Removing routing rules for IP $target_ip..."
        ip rule show | grep -E "to $target_ip lookup $ROUTING_TABLE" | while read rule; do
            rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
            ip rule del prio $rule_num 2>/dev/null || true
        done
    fi
done

# Flush the apiroutes table
if grep -q "$ROUTING_TABLE" /etc/iproute2/rt_tables; then
    log "Flushing and removing $ROUTING_TABLE routing table..."
    ip route flush table $ROUTING_TABLE 2>/dev/null || true
    
    # Remove the table entry
    grep -v "$ROUTING_TABLE" /etc/iproute2/rt_tables > /tmp/rt_tables.new
    mv /tmp/rt_tables.new /etc/iproute2/rt_tables
fi

# 4. Clean up NAT rules
log "Cleaning up NAT rules..."
# Find and remove the apiRouting NAT rules
for target in "${API_TARGETS[@]}"; do
    target_ip=$(host -t A $target | grep "has address" | head -n1 | awk '{print $NF}' 2>/dev/null || echo "")
    if [ -n "$target_ip" ]; then
        log "Removing NAT rules for $target_ip..."
        iptables -t nat -S PREROUTING | grep -E -- "-d $target_ip" | while read rule; do
            modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -t nat $modified_rule || true
        done
        
        iptables -t nat -S POSTROUTING | grep -E -- "-d $target_ip" | while read rule; do
            modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -t nat $modified_rule || true
        done
    fi
done

# Also try to clean up rules mentioning common VPN IPs
for vpn_ip in "10.8.0.1" "10.8.0.6"; do
    log "Removing NAT rules for VPN IP $vpn_ip..."
    iptables -t nat -S | grep -E -- "$vpn_ip" | while read rule; do
        chain=$(echo "$rule" | awk '{print $2}')
        if [[ "$chain" == "PREROUTING" || "$chain" == "POSTROUTING" ]]; then
            modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -t nat $modified_rule || true
        fi
    done
done

# 5. Remove OpenVPN configuration
log "Cleaning up OpenVPN configuration..."
# First, create backup
if [ -f /etc/openvpn/server.conf ]; then
    cp /etc/openvpn/server.conf /etc/openvpn/server.conf.backup.$(date +%Y%m%d)
    
    # Remove apiRouting related lines
    log "Removing API routing configuration from OpenVPN server.conf..."
    grep -v -E "(learn-address|client-connect|client-config-dir|API Routing)" /etc/openvpn/server.conf > /tmp/server.conf.tmp
    mv /tmp/server.conf.tmp /etc/openvpn/server.conf
fi

# 6. Remove scripts and directories
log "Removing API routing scripts and directories..."
# Remove scripts
if [ -d /etc/openvpn/scripts ]; then
    rm -f /etc/openvpn/scripts/learn-address.sh
    rm -f /etc/openvpn/scripts/client-connect.sh
    rm -f /etc/openvpn/scripts/ip_update_hook.sh
fi

# Remove active routers file
rm -f /etc/openvpn/active_routers

# Remove monitoring and verification scripts
rm -f /usr/local/bin/test-api-routing.sh
rm -f /usr/local/bin/check-api-routing.sh
rm -f /usr/local/bin/verify-routing.js
rm -f /usr/local/bin/check-outgoing-ip.sh
rm -f /usr/local/bin/monitor-api-routes.sh
rm -f /usr/local/bin/check-domain-health.sh
rm -f /usr/local/bin/enhanced-test-api-routing.sh

# 7. Remove NGINX configurations
log "Cleaning up NGINX configurations..."
# Remove any API-related NGINX configs
if [ -d /etc/nginx/conf.d ]; then
    rm -f /etc/nginx/conf.d/api-ipify-proxy.conf
    rm -f /etc/nginx/conf.d/custom-api-proxy.conf
    
    # Reload NGINX if it's running
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log "NGINX configuration reloaded."
    fi
fi

# 8. Remove network bridge if it exists
log "Checking for API network bridges..."
BRIDGE_NAME="br-apiroute"
if command -v brctl &> /dev/null && brctl show | grep -q "$BRIDGE_NAME"; then
    log "Removing $BRIDGE_NAME bridge..."
    ip link set $BRIDGE_NAME down
    brctl delbr $BRIDGE_NAME
    log "Network bridge removed."
fi

# 9. Remove log directory
log "Cleaning up log files..."
if [ -d /var/log/api_routing ]; then
    log "Removing API routing logs directory..."
    rm -rf /var/log/api_routing
fi

# 10. Restart OpenVPN to apply changes
log "Restarting OpenVPN service..."
systemctl restart openvpn.service
log "OpenVPN restarted."

log "API routing removal complete. All components have been removed."
log "If you wish to reuse the API routing functionality in the future,"
log "please reinstall using the desired routing method script."
echo ""
echo "===== REMOVAL COMPLETE ====="
echo "All apiRouting components have been removed from the system."
echo "A backup of your original OpenVPN server configuration has been created at:"
echo "/etc/openvpn/server.conf.backup.$(date +%Y%m%d)"
echo ""
