#!/bin/bash

# Custom Domain API Routing Setup Script
# This script configures routing for a custom API domain through MikroTik OpenVPN clients

# Exit on any error
set -e

# Check if domain provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <custom_domain> [port]"
    echo "Example: $0 api.example.com 443"
    exit 1
fi

# Parameters
CUSTOM_DOMAIN=$1
PORT=${2:-443}
API_TARGET=$CUSTOM_DOMAIN
ROUTING_TABLE="apiroutes"
SCRIPT_DIR="/etc/openvpn/scripts"
CONFIG_DIR="/etc/nginx/conf.d"
LOG_DIR="/var/log/api_routing"

# Ensure log directory exists
mkdir -p $LOG_DIR

# Step 0: Verify domain is reachable
echo "Verifying domain is reachable..."
if ! host $CUSTOM_DOMAIN > /dev/null 2>&1; then
    echo "Warning: Domain $CUSTOM_DOMAIN could not be resolved"
    echo -n "Do you want to continue anyway? [y/N] "
    read continue_setup
    if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
        echo "Setup aborted."
        exit 1
    fi
else
    echo "Domain $CUSTOM_DOMAIN resolves successfully."
fi

# Test if domain is accessible
echo "Testing connection to $CUSTOM_DOMAIN:$PORT..."
if ! timeout 5 bash -c "</dev/tcp/$CUSTOM_DOMAIN/$PORT" 2>/dev/null; then
    echo "Warning: Cannot connect to $CUSTOM_DOMAIN:$PORT"
    echo -n "Do you want to continue anyway? [y/N] "
    read continue_setup
    if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
        echo "Setup aborted."
        exit 1
    fi
else
    echo "Connection to $CUSTOM_DOMAIN:$PORT successful."
fi

echo "===== Setting up API routing for $API_TARGET ====="

# Step 1: Update learn-address script with new domain
if [ -f "$SCRIPT_DIR/learn-address.sh" ]; then
    echo "Updating learn-address script with new domain..."
    sed -i "s/API_TARGET=.*$/API_TARGET=\"$API_TARGET\"/" $SCRIPT_DIR/learn-address.sh
else
    echo "Error: learn-address script not found. Please run api_routing_setup.sh first."
    exit 1
fi

# Step 2: Update client-connect script with new domain
if [ -f "$SCRIPT_DIR/client-connect.sh" ]; then
    echo "Updating client-connect script with new domain..."
    sed -i "s/API_TARGET=.*$/API_TARGET=\"$API_TARGET\"/" $SCRIPT_DIR/client-connect.sh
else
    echo "Error: client-connect script not found. Please run api_routing_setup.sh first."
    exit 1
fi

# Step 3: Create NGINX configuration for custom domain
echo "Creating NGINX configuration for custom domain..."
cat > $CONFIG_DIR/custom-api-proxy.conf << EOF
# Custom API Routing proxy for $API_TARGET
server {
    listen 80;
    server_name $API_TARGET;

    location / {
        resolver 8.8.8.8;
        proxy_pass https://$API_TARGET:$PORT;
        proxy_set_header Host $API_TARGET;
        proxy_ssl_server_name on;
        proxy_ssl_name $API_TARGET;
        
        # Add request logging
        access_log /var/log/nginx/custom_api_access.log;
        error_log /var/log/nginx/custom_api_error.log;
    }
}
EOF

# Step 4: Check NGINX configuration
echo "Checking NGINX configuration..."
nginx -t

# Step 5: Reload NGINX if configuration is valid
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "NGINX configuration updated successfully."
else
    echo "NGINX configuration error. Please check the configuration manually."
    exit 1
fi

# Step 6: Update verification scripts
if [ -f "/usr/local/bin/verify-routing.js" ]; then
    echo "Updating Node.js verification script..."
    sed -i "s|const API_URL = .*$|const API_URL = 'http://$API_TARGET';|" /usr/local/bin/verify-routing.js
fi

if [ -f "/usr/local/bin/check-api-routing.sh" ]; then
    echo "Updating shell verification script..."
    sed -i "s|API_URL=.*$|API_URL=\"http://$API_TARGET\"|" /usr/local/bin/check-api-routing.sh
fi

# Step 7: Update routing rule for new domain
echo "Updating routing rules..."
ip rule del to api.ipify.org lookup apiroutes 2>/dev/null || true
ip rule add to $API_TARGET lookup $ROUTING_TABLE

# Step 8: Flush routing cache
ip route flush cache

# Add new domain health check script
echo "Creating domain health check script..."
cat > /usr/local/bin/check-domain-health.sh << EOF
#!/bin/bash

DOMAIN="$CUSTOM_DOMAIN"
PORT="$PORT"
LOG_FILE="$LOG_DIR/domain_health.log"

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

mkdir -p "\$(dirname "\$LOG_FILE")"
log "Checking health for \$DOMAIN:\$PORT"

# Resolve domain
IP=\$(host -t A \$DOMAIN | grep "has address" | head -n1 | awk '{print \$NF}')
if [ -z "\$IP" ]; then
    log "ERROR: Cannot resolve \$DOMAIN"
    exit 1
else
    log "Domain resolves to \$IP"
fi

# Check connectivity
if timeout 5 bash -c "</dev/tcp/\$DOMAIN/\$PORT" 2>/dev/null; then
    log "Connection successful"
else
    log "ERROR: Cannot connect to \$DOMAIN:\$PORT"
    # Send alert (customize as needed)
    echo "Domain \$DOMAIN is unreachable" | mail -s "API Domain Alert" admin@example.com
fi

# Check if route exists
if ip rule show | grep -q "to \$DOMAIN lookup apiroutes"; then
    log "Routing rule exists"
else
    log "ERROR: Routing rule missing, recreating"
    ip rule add to \$DOMAIN lookup apiroutes
    ip route flush cache
fi
EOF

chmod +x /usr/local/bin/check-domain-health.sh

# Add to crontab
echo "*/15 * * * * root /usr/local/bin/check-domain-health.sh" > /etc/cron.d/domain-health-check

echo ""
echo "===== Custom Domain API Routing Setup Complete! ====="
echo ""
echo "The following configurations have been updated:"
echo "1. learn-address script now targets $API_TARGET"
echo "2. client-connect script now targets $API_TARGET"
echo "3. NGINX configuration created for $API_TARGET"
echo "4. Verification scripts updated to use $API_TARGET"
echo "5. Routing rules updated for $API_TARGET"
echo "6. Domain health monitoring has been configured"
echo ""
echo "For MikroTik client configuration, update the route to:"
echo "/ip route add dst-address=$API_TARGET/32 gateway=<VPN_SERVER_INTERNAL_IP> distance=1"
echo ""
echo "For other clients, update the route directive to:"
echo "route $API_TARGET 255.255.255.255"
echo ""

# Create MikroTik example configuration for custom domain
cat > $(dirname $0)/custom_domain_mikrotik.txt << EOF
# MikroTik Configuration for Custom Domain API Routing

# Add a static route for the custom domain
/ip route
add dst-address=$API_TARGET/32 gateway=<VPN_SERVER_INTERNAL_IP> distance=1

# If you're using DNS-based routing:
/ip dns static
add address=<VPN_SERVER_INTERNAL_IP> name=$API_TARGET
EOF

echo "Setup for custom domain $API_TARGET completed successfully!"
