#!/bin/bash

# Minimal API Routing Setup Script
# This script configures routing for api.ipify.org through MikroTik OpenVPN clients

# Exit on any error
set -e

# Parameters
API_TARGET="api.ipify.org"
ROUTING_TABLE="apiroutes"
ROUTING_TABLE_ID="200"
ROUTERS_FILE="/etc/openvpn/active_routers"
LOG_DIR="/var/log/api_routing"
SCRIPT_DIR="/etc/openvpn/scripts"
BACKUP_DIR="/etc/openvpn/backups/$(date +%Y%m%d%H%M%S)"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check for required packages
echo "Checking prerequisites..."
required_commands=("openvpn" "nginx" "host" "curl" "ip")  # Changed iproute2 to ip
missing_packages=()

for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    # Map command to package name (in case they differ)
    case "$cmd" in
      "ip")
        missing_packages+=("iproute2")
        ;;
      *)
        missing_packages+=("$cmd")
        ;;
    esac
  fi
done

if [ ${#missing_packages[@]} -ne 0 ]; then
  echo "Error: The following required packages are missing:"
  printf "  - %s\n" "${missing_packages[@]}"
  echo "Please install them before continuing."
  exit 1
fi

# Create necessary directories
mkdir -p $SCRIPT_DIR $LOG_DIR $BACKUP_DIR

echo "===== Setting up API routing for $API_TARGET ====="

# Backup existing configurations
echo "Creating backups of existing configurations..."
if [ -f /etc/iproute2/rt_tables ]; then
  cp /etc/iproute2/rt_tables $BACKUP_DIR/rt_tables.bak
fi

if [ -f /etc/openvpn/server.conf ]; then
  cp /etc/openvpn/server.conf $BACKUP_DIR/server.conf.bak
fi

if [ -f /etc/nginx/conf.d/api-ipify-proxy.conf ]; then
  cp /etc/nginx/conf.d/api-ipify-proxy.conf $BACKUP_DIR/api-ipify-proxy.conf.bak
fi

echo "===== Setting up API routing for $API_TARGET ====="

# Step 1: Create a dedicated routing table
echo "Creating routing table for API traffic..."
grep -q "$ROUTING_TABLE_ID $ROUTING_TABLE" /etc/iproute2/rt_tables || \
    echo "$ROUTING_TABLE_ID $ROUTING_TABLE" >> /etc/iproute2/rt_tables

# Step 2: Create the learn-address script
echo "Creating learn-address script..."
cat > $SCRIPT_DIR/learn-address.sh << 'EOF'
#!/bin/bash

# Learn-address hook for OpenVPN
# Arguments: operation(add/update/delete) client_ip common_name

ACTION=$1
CLIENT_IP=$2
COMMON_NAME=$3

LOG_FILE="/var/log/api_routing/learn-address.log"
ROUTERS_FILE="/etc/openvpn/active_routers"
API_TARGET="api.ipify.org"
ROUTING_TABLE="apiroutes"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Initialize log file if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log "Called with: $ACTION $CLIENT_IP $COMMON_NAME"

# Only process MikroTik clients
if [[ "$COMMON_NAME" == "mikrotik_"* ]]; then
    log "Processing MikroTik router: $COMMON_NAME ($CLIENT_IP)"
    
    case "$ACTION" in
        add|update)
            # Add to active routers list
            echo "$CLIENT_IP" >> "$ROUTERS_FILE"
            sort -u "$ROUTERS_FILE" -o "$ROUTERS_FILE"
            log "Added $CLIENT_IP to active routers list"
            
            # Add route in the API routing table
            ip route add default via "$CLIENT_IP" table "$ROUTING_TABLE" metric "$(date +%s)" 2>/dev/null || \
                ip route change default via "$CLIENT_IP" table "$ROUTING_TABLE" metric "$(date +%s)"
            log "Updated route via $CLIENT_IP in $ROUTING_TABLE table"
            
            # Ensure rule exists to use this table for API traffic
            ip rule show | grep -q "to $API_TARGET lookup $ROUTING_TABLE" || \
                ip rule add to "$API_TARGET" lookup "$ROUTING_TABLE"
            
            # Flush routing cache to apply changes
            ip route flush cache
            log "Flushed routing cache"
            ;;
            
        delete)
            # Remove from active routers list
            if [ -f "$ROUTERS_FILE" ]; then
                grep -v "^$CLIENT_IP$" "$ROUTERS_FILE" > "${ROUTERS_FILE}.tmp"
                mv "${ROUTERS_FILE}.tmp" "$ROUTERS_FILE"
                log "Removed $CLIENT_IP from active routers list"
                
                # Remove the route from the API routing table
                ip route del default via "$CLIENT_IP" table "$ROUTING_TABLE" 2>/dev/null || true
                log "Removed route via $CLIENT_IP from $ROUTING_TABLE table"
                
                # Flush routing cache to apply changes
                ip route flush cache
                log "Flushed routing cache"
            fi
            ;;
    esac
    
    # Output current active routers for debugging
    ACTIVE_ROUTERS=$(cat "$ROUTERS_FILE" 2>/dev/null || echo "None")
    log "Current active routers: $ACTIVE_ROUTERS"
fi

exit 0
EOF

chmod +x $SCRIPT_DIR/learn-address.sh

# Step 3: Create client connect script to handle API domain resolution
echo "Creating client-connect script..."
cat > $SCRIPT_DIR/client-connect.sh << 'EOF'
#!/bin/bash

# Get API domain IP address
API_TARGET="api.ipify.org"
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')

# If we can resolve the API domain
if [[ -n "$API_IP" ]]; then
    # Ensure we have a specific route for the API IP
    ip route show table main | grep -q "$API_IP" || \
        ip route add $API_IP dev $dev
    
    # For MikroTik routers, push a route for the API target
    if [[ "$common_name" == "mikrotik_"* ]]; then
        echo "push \"route $API_TARGET 255.255.255.255\"" >> $1
    fi
fi

exit 0
EOF

chmod +x $SCRIPT_DIR/client-connect.sh

# Step 4: Create client config directory if it doesn't exist
mkdir -p /etc/openvpn/ccd

# Step 5: Create minimal verification script 
echo "Creating simple API test script..."
cat > /usr/local/bin/test-api-routing.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/api_routing/verification.log"
TOTAL_REQUESTS=${1:-5}
API_URL="http://api.ipify.org?format=json"

echo "Testing API routing with $TOTAL_REQUESTS requests..." | tee -a "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"

declare -A ip_count
unique_ips=0

for i in $(seq 1 $TOTAL_REQUESTS); do
    echo -n "Request $i: " | tee -a "$LOG_FILE"
    response=$(curl -s "$API_URL")
    
    if [ $? -eq 0 ]; then
        ip=$(echo "$response" | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
        echo "$ip" | tee -a "$LOG_FILE"
        
        if [ -n "$ip" ]; then
            if [ -z "${ip_count[$ip]}" ]; then
                ip_count[$ip]=1
                ((unique_ips++))
            else
                ((ip_count[$ip]++))
            fi
        fi
    else
        echo "Failed" | tee -a "$LOG_FILE"
    fi
    
    sleep 1
done

echo "" | tee -a "$LOG_FILE"
echo "Summary:" | tee -a "$LOG_FILE"
echo "Total requests: $TOTAL_REQUESTS" | tee -a "$LOG_FILE"
echo "Unique IPs: $unique_ips" | tee -a "$LOG_FILE"

echo "IP distribution:" | tee -a "$LOG_FILE"
for ip in "${!ip_count[@]}"; do
    echo "$ip: ${ip_count[$ip]} requests" | tee -a "$LOG_FILE"
done

echo "" | tee -a "$LOG_FILE"
EOF

chmod +x /usr/local/bin/test-api-routing.sh

# Step 6: Add configuration to OpenVPN server config
echo "Updating OpenVPN server configuration..."
cat >> /etc/openvpn/server.conf << EOF

# API Routing Configuration
script-security 2
learn-address $SCRIPT_DIR/learn-address.sh
client-connect $SCRIPT_DIR/client-connect.sh
client-config-dir /etc/openvpn/ccd

EOF

# Step 7: Add NGINX configuration for API domain
echo "Creating NGINX configuration for API domain..."
cat > /etc/nginx/conf.d/api-ipify-proxy.conf << EOF
# API Routing proxy for api.ipify.org
server {
    listen 80;
    server_name api.ipify.org;

    location / {
        resolver 8.8.8.8;
        proxy_pass https://api.ipify.org;
        proxy_set_header Host api.ipify.org;
        proxy_ssl_server_name on;
        proxy_ssl_name api.ipify.org;
        
        # Add request logging
        access_log /var/log/nginx/api_ipify_access.log;
        error_log /var/log/nginx/api_ipify_error.log;
    }
}
EOF

# Step 8: Ensure NGINX configuration is valid
nginx -t

# Step 9: Restart NGINX if configuration is valid
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "NGINX configuration updated successfully."
else
    echo "NGINX configuration error. Please check the configuration manually."
    exit 1
fi

# Step 10: Create a systemd service for persistence
echo "Setting up routing persistence across reboots..."
cat > /etc/systemd/system/api-routing.service << 'EOF'
[Unit]
Description=API Routing Service
After=network.target openvpn.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'grep -q "200 apiroutes" /etc/iproute2/rt_tables || echo "200 apiroutes" >> /etc/iproute2/rt_tables; ip rule add to api.ipify.org lookup apiroutes || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable api-routing.service
systemctl start api-routing.service

# Step 11: Create a simple monitoring script
echo "Creating simple route monitoring script..."
cat > /usr/local/bin/monitor-api-routes.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/api_routing/monitor.log"
API_TARGET="api.ipify.org"
ROUTING_TABLE="apiroutes"
ROUTERS_FILE="/etc/openvpn/active_routers"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")"
log "Starting API routing monitor"

# Check if rule exists, recreate if missing
if ! ip rule show | grep -q "to $API_TARGET lookup $ROUTING_TABLE"; then
    log "API routing rule missing, recreating..."
    ip rule add to "$API_TARGET" lookup "$ROUTING_TABLE"
    ip route flush cache
    log "Rule recreated"
fi

# Check if we have any active routers
if [ -f "$ROUTERS_FILE" ] && [ -s "$ROUTERS_FILE" ]; then
    # Check if the routing table has a default route
    if ! ip route show table "$ROUTING_TABLE" | grep -q "default"; then
        log "No default route in $ROUTING_TABLE table, recreating..."
        # Get the first active router
        ROUTER=$(head -1 "$ROUTERS_FILE")
        ip route add default via "$ROUTER" table "$ROUTING_TABLE" metric "$(date +%s)"
        log "Default route via $ROUTER added"
    fi
else
    log "No active routers found"
fi
EOF

chmod +x /usr/local/bin/monitor-api-routes.sh

# Setup cron job for the monitor
echo "*/5 * * * * root /usr/local/bin/monitor-api-routes.sh" > /etc/cron.d/api-route-monitor

# Create MikroTik example configuration
cat > $(dirname $0)/mikrotik_config.txt << 'EOF'
# MikroTik Minimal Configuration for API Routing

# 1. Create OpenVPN client connection
/interface ovpn-client
add connect-to=<YOUR_VPN_SERVER_IP> name=ovpn-out1 port=1194 \
    user=mikrotik_router1 password=<YOUR_PASSWORD> \
    mode=ip add-default-route=no 

# 2. Enable IP forwarding
/ip forward
set enabled=yes

# 3. Add route for the API domain
/ip route
add dst-address=api.ipify.org/32 gateway=<VPN_SERVER_INTERNAL_IP> distance=1
EOF

echo ""
echo "===== Minimal API Routing Setup Complete! ====="
echo ""
echo "The following configurations have been made:"
echo "1. Created dedicated routing table: $ROUTING_TABLE"
echo "2. Setup learn-address hook for OpenVPN"
echo "3. Configured client-connect script"
echo "4. Added NGINX configuration for api.ipify.org"
echo "5. Created simple verification and monitoring scripts"
echo ""
echo "To test your routing setup, run:"
echo "/usr/local/bin/test-api-routing.sh [number_of_requests]"
echo ""
echo "For MikroTik client configuration, see the mikrotik_config.txt file"
echo ""
echo "Backup of original configurations saved to $BACKUP_DIR"
echo ""
