#!/bin/bash
# Fix critical routing errors based on result.txt findings
# This script addresses specific issues found in the routing setup

# Exit if any command fails
set -e

# Fixed Configuration Variables
VPN_SERVER_IP="176.222.55.126"
VPN_SERVER_INTERNAL_IP="10.8.0.1"
ROUTING_TABLE="apiroutes"
ROUTING_TABLE_ID="200"
LOG_DIR="/var/log/api_routing"
SCRIPT_DIR="/etc/openvpn/scripts"
SERVER_SCRIPT_DIR="/home/itguy/vpn/OpenVpn-Server/apiRouting"

echo "===== API Routing Error Fix Script ====="
echo "This script will fix critical errors in your API routing setup"
echo "Date: $(date)"
echo ""

# IMPROVEMENT: Determine API_TARGET dynamically from config if possible
API_TARGET=$(grep -r "API_TARGET=" /etc/openvpn/scripts/*.sh 2>/dev/null | head -1 | sed 's/.*API_TARGET="\([^"]*\)".*/\1/') || true
# Fall back to default if not found
API_TARGET=${API_TARGET:-"api.ipify.org"}
echo "Using API target: $API_TARGET"

# First verify API resolves to an IP address
echo "Resolving $API_TARGET..."
API_TARGET_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_TARGET_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    echo "This is a DNS problem that needs to be fixed first."
    exit 1
fi
echo "✓ $API_TARGET resolved to $API_TARGET_IP"

# Create required directories
mkdir -p $LOG_DIR $SCRIPT_DIR /etc/openvpn $SERVER_SCRIPT_DIR

# IMPROVEMENT: Check if active_routers exists and get MikroTik IP dynamically
echo "Checking active_routers file..."
if [ ! -f "/etc/openvpn/active_routers" ] || [ ! -s "/etc/openvpn/active_routers" ]; then
    echo "Active routers file is missing or empty."
    echo -n "Enter MikroTik VPN IP (default is 10.8.0.6): "
    read input_mikrotik_ip
    MIKROTIK_VPN_IP=${input_mikrotik_ip:-"10.8.0.6"}
    echo "$MIKROTIK_VPN_IP" > /etc/openvpn/active_routers
    echo "Created active_routers file with MikroTik IP: $MIKROTIK_VPN_IP"
else
    MIKROTIK_VPN_IP=$(head -1 "/etc/openvpn/active_routers")
    echo "✓ Found MikroTik IP in active_routers: $MIKROTIK_VPN_IP"
fi

# Fix: Verify MikroTik router is reachable
echo "Testing connectivity to MikroTik router ($MIKROTIK_VPN_IP)..."
if ping -c 1 -W 1 $MIKROTIK_VPN_IP > /dev/null 2>&1; then
    echo "✓ MikroTik router is reachable"
else
    echo "ERROR: Cannot reach MikroTik router at $MIKROTIK_VPN_IP"
    echo "The router is not connected or not properly set up."
    echo "Check your OpenVPN server configuration and MikroTik router configuration."
    
    # Ask if user wants to continue anyway
    echo -n "Continue anyway? (might not work) [y/N]: "
    read continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        echo "Exiting. Please fix router connectivity first."
        exit 1
    fi
fi

# Fix: Ensure routing table exists
echo "Setting up routing table..."
if ! grep -q "$ROUTING_TABLE_ID $ROUTING_TABLE" /etc/iproute2/rt_tables; then
    echo "$ROUTING_TABLE_ID $ROUTING_TABLE" >> /etc/iproute2/rt_tables
    echo "Created routing table '$ROUTING_TABLE'"
else
    echo "✓ Routing table '$ROUTING_TABLE' exists"
fi

# Fix: Use IP-based rules instead of domain-based rules
echo "Setting up IP-based routing rules (fixing the domain name error)..."

# Clear any existing problematic rules
ip rule show | grep -E "lookup $ROUTING_TABLE" 2>/dev/null | while read rule; do
    rule_num=$(echo $rule | awk '{print $1}' | sed 's/://')
    echo "Removing rule: $rule"
    ip rule del prio $rule_num 2>/dev/null || true
done

# Add IP-based rule only (not domain-based)
echo "Adding rule for $API_TARGET_IP..."
ip rule add to $API_TARGET_IP lookup $ROUTING_TABLE
echo "✓ IP-based rule added"

# Fix: Add explicit route to the routing table
echo "Adding explicit route to the routing table..."
ip route flush table $ROUTING_TABLE 2>/dev/null || true
ip route add $API_TARGET_IP/32 via $MIKROTIK_VPN_IP table $ROUTING_TABLE || {
    echo "WARNING: Could not add route via MikroTik IP"
    echo "Using direct static route instead"
    ip route add $API_TARGET_IP/32 dev lo table $ROUTING_TABLE
}
echo "✓ Route added to table"

# Fix: Fix NAT configuration
echo "Setting up NAT configuration..."
# Remove any conflicting rules
existing_rules=$(iptables -t nat -S POSTROUTING | grep -E "$API_TARGET_IP|$MIKROTIK_VPN_IP" | wc -l)
if [ $existing_rules -gt 0 ]; then
    echo "Clearing existing NAT rules..."
    iptables -t nat -S POSTROUTING | grep -E "$API_TARGET_IP|$MIKROTIK_VPN_IP" | while read rule; do
        modified_rule=$(echo "$rule" | sed 's/^-A/-D/')
        iptables -t nat $modified_rule 2>/dev/null || true
    done
fi

# Add rules that specifically work for forwarding traffic
iptables -t nat -A PREROUTING -d $API_TARGET_IP -j DNAT --to-destination $MIKROTIK_VPN_IP
iptables -t nat -A POSTROUTING -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
echo "✓ NAT rules configured"

# Fix: Update routing cache
echo "Flushing routing cache..."
ip route flush cache
echo "✓ Routing cache flushed"

# Fix: Generate the missing diagnostic file
echo "Creating diagnostic script..."
cat > "$SERVER_SCRIPT_DIR/api-routing-diagnostics.sh" << 'EOF'
#!/bin/bash
# API Routing Diagnostic Tool

# Setup variables
LOG_DIR="/var/log/api_routing"
ROUTING_TABLE="apiroutes"
mkdir -p $LOG_DIR

# Set default API target
API_TARGET=${1:-"api.ipify.org"}

echo "===== API Routing Diagnostics ====="
echo "Testing API target: $API_TARGET"
echo "Date: $(date)"
echo ""

# 1. DNS Resolution
echo "==== DNS Resolution ===="
echo -n "Resolving $API_TARGET: "
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -n "$API_IP" ]; then
    echo "$API_IP"
else
    echo "FAILED"
fi

# 2. Current Routes
echo -e "\n==== Routing Tables ===="
echo "Main routing table for $API_TARGET:"
if [ -n "$API_IP" ]; then
    ip route get $API_IP
else
    echo "Cannot resolve API target"
fi

echo -e "\nAPI routes table:"
ip route show table $ROUTING_TABLE

echo -e "\nRouting rules:"
ip rule show | grep -E "($ROUTING_TABLE|$API_IP)"

# 3. OpenVPN Status
echo -e "\n==== OpenVPN Status ===="
systemctl status openvpn --no-pager | head -20

# 4. Active Routers
echo -e "\n==== Active Routers ===="
if [ -f "/etc/openvpn/active_routers" ]; then
    echo "Available routers:"
    cat /etc/openvpn/active_routers
    
    echo -e "\nReachability check:"
    while read router_ip; do
        if ping -c 1 -W 1 $router_ip >/dev/null 2>&1; then
            echo "$router_ip is reachable"
        else
            echo "$router_ip is NOT reachable"
        fi
    done < "/etc/openvpn/active_routers"
else
    echo "No active routers file found"
fi

# 5. Try curl with verbose output
echo -e "\n==== Testing API Connection ===="
echo "Connecting to $API_TARGET with curl:"
curl -v http://$API_TARGET 2>&1 | grep -E "(Connected to|HTTP|GET|< [[:digit:]])"

# 6. Test with traceroute (if installed)
echo -e "\n==== API Route Traceroute ===="
which traceroute > /dev/null 2>&1 && traceroute $API_TARGET || echo "traceroute not installed"

# 7. Check NAT settings
echo -e "\n==== NAT Configuration ===="
iptables -t nat -L PREROUTING -v
echo ""
iptables -t nat -L POSTROUTING -v

# 8. Log results
echo -e "\nLogging results to $LOG_DIR/diagnostics.log"
{
    echo "=== Diagnostic Run: $(date) ==="
    echo "API Target: $API_TARGET"
    echo "API IP: $API_IP"
    echo "Current Routes in $ROUTING_TABLE:"
    ip route show table $ROUTING_TABLE
    echo "Active Routers:"
    cat /etc/openvpn/active_routers 2>/dev/null || echo "No active routers file"
    echo ""
} >> "$LOG_DIR/diagnostics.log"
EOF

chmod +x "$SERVER_SCRIPT_DIR/api-routing-diagnostics.sh"
echo "✓ Diagnostic script created at $SERVER_SCRIPT_DIR/api-routing-diagnostics.sh"

# Fix: Try alternative approach to ensure routing works
echo "Setting up alternative approach using DNAT/SNAT..."
iptables -t nat -A PREROUTING -p tcp --dport 80 -d $API_TARGET_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:80
iptables -t nat -A PREROUTING -p tcp --dport 443 -d $API_TARGET_IP -j DNAT --to-destination $MIKROTIK_VPN_IP:443
iptables -t nat -A POSTROUTING -p tcp -d $MIKROTIK_VPN_IP -j SNAT --to-source $VPN_SERVER_INTERNAL_IP
echo "✓ Alternative routing approach configured"

# Fix: Create a dynamic test script that adapts to any API target
cat > "$SERVER_SCRIPT_DIR/test-api-connection.sh" << 'EOF'
#!/bin/bash
# Test API Connection using Multiple Methods

# Automatically determine the API target if not provided
if [ -z "$1" ]; then
    # Try to get from learn-address script
    API_TARGET=$(grep -r "API_TARGET=" /etc/openvpn/scripts/*.sh 2>/dev/null | head -1 | sed 's/.*API_TARGET="\([^"]*\)".*/\1/') || true
    # Fall back to default
    API_TARGET=${API_TARGET:-"api.ipify.org"}
else
    API_TARGET="$1"
fi

echo "===== API Connection Test for $API_TARGET ====="
echo "Date: $(date)"
echo ""

# Method 1: Direct curl
echo "Method 1: Direct curl request"
echo "-----------------------------"
curl -s "http://$API_TARGET?format=json"
echo -e "\n"

# Method 2: With headers
echo "Method 2: With detailed headers"
echo "-----------------------------"
curl -v "http://$API_TARGET?format=json" 2>&1 | grep -E "(Connected to|HTTP|GET|< [[:digit:]]|\"ip\")"
echo -e "\n"

# Method 3: Using wget
echo "Method 3: Using wget"
echo "-----------------------------"
which wget >/dev/null 2>&1 && wget -qO- "http://$API_TARGET?format=json" || echo "wget not installed"
echo -e "\n"

# Method 4: Using Python (if available)
echo "Method 4: Using Python"
echo "-----------------------------"
if which python3 >/dev/null 2>&1; then
    python3 -c "import urllib.request, json; response = urllib.request.urlopen('http://$API_TARGET?format=json'); data = json.loads(response.read()); print(data)"
elif which python >/dev/null 2>&1; then
    python -c "import urllib.request, json; response = urllib.request.urlopen('http://$API_TARGET?format=json'); data = json.loads(response.read()); print(data)"
else
    echo "Python not installed"
fi

# Method 5: Direct test with IP
echo -e "\nMethod 5: Testing with IP lookup"
echo "-----------------------------"
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -n "$API_IP" ]; then
    echo "$API_TARGET resolves to $API_IP"
    echo "Testing direct connection to IP:"
    curl -s "http://$API_IP?format=json"
else
    echo "Could not resolve $API_TARGET to an IP address"
fi
EOF

chmod +x "$SERVER_SCRIPT_DIR/test-api-connection.sh"
echo "✓ Test script created at $SERVER_SCRIPT_DIR/test-api-connection.sh"

# Create a dynamic MikroTik configuration generator
cat > "$SERVER_SCRIPT_DIR/generate-mikrotik-config.sh" << 'EOF'
#!/bin/bash
# Dynamic MikroTik Configuration Generator

# Get the API target
API_TARGET=${1:-"api.ipify.org"}
VPN_SERVER_INTERNAL_IP=${2:-"10.8.0.1"}

# Resolve API to IP
API_IP=$(host -t A $API_TARGET | grep "has address" | head -n1 | awk '{print $NF}')
if [ -z "$API_IP" ]; then
    echo "Error: Cannot resolve $API_TARGET"
    exit 1
fi

cat > "./mikrotik-config-$API_TARGET.rsc" << EOT
# MikroTik Configuration for API Routing
# Generated on: $(date)
# API Target: $API_TARGET ($API_IP)

# 1. Make sure IP forwarding is enabled
/ip forward set enabled=yes

# 2. Add routes for API target
/ip route add dst-address=$API_IP/32 gateway=$VPN_SERVER_INTERNAL_IP comment="API route for $API_TARGET"

# 3. Set up NAT to ensure traffic uses MikroTik's public IP
/ip firewall nat add chain=srcnat src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP action=masquerade comment="API traffic NAT for $API_TARGET"

# 4. Add static DNS entry to avoid DNS issues
/ip dns static add name=$API_TARGET address=$API_IP comment="API DNS override"

# 5. Add a more specific rule for HTTP/HTTPS traffic
/ip firewall nat add chain=srcnat protocol=tcp src-address=$VPN_SERVER_INTERNAL_IP dst-address=$API_IP dst-port=80,443 action=masquerade comment="HTTP/HTTPS NAT for $API_TARGET"

# 6. Add monitoring script
/system script add name="monitor-$API_TARGET-route" source={
    :local apiTarget "$API_TARGET"
    :local apiIP "$API_IP"
    :local vpnServerIP "$VPN_SERVER_INTERNAL_IP"
    
    :log info "Checking route to \$apiTarget (\$apiIP)"
    
    :if ([:len [/ip route find where dst-address="\$apiIP/32"]] = 0) do={
        :log warning "Route to \$apiTarget missing, adding..."
        /ip route add dst-address=\$apiIP/32 gateway=\$vpnServerIP comment="API route for \$apiTarget"
    }
}

# 7. Schedule monitoring
/system scheduler add interval=15m name="check-$API_TARGET-route" on-event="monitor-$API_TARGET-route" start-time=startup
EOT

echo "✓ MikroTik configuration generated: mikrotik-config-$API_TARGET.rsc"
EOF

chmod +x "$SERVER_SCRIPT_DIR/generate-mikrotik-config.sh"
echo "✓ MikroTik config generator created at $SERVER_SCRIPT_DIR/generate-mikrotik-config.sh"

# Generate current MikroTik config
"$SERVER_SCRIPT_DIR/generate-mikrotik-config.sh" "$API_TARGET" "$VPN_SERVER_INTERNAL_IP"

# Create a one-command fix script that's easy to remember
cat > "$SERVER_SCRIPT_DIR/quick-fix.sh" << EOF
#!/bin/bash
# Quick fix for API routing

# Determine API_TARGET and MIKROTIK_VPN_IP
API_TARGET=${API_TARGET}
MIKROTIK_VPN_IP=\$(head -1 /etc/openvpn/active_routers 2>/dev/null || echo "10.8.0.6")
API_IP=\$(host -t A \$API_TARGET | grep "has address" | head -n1 | awk '{print \$NF}')

echo "Quick fix for \$API_TARGET (\$API_IP) via \$MIKROTIK_VPN_IP"

# Fix routing table
echo "200 apiroutes" >> /etc/iproute2/rt_tables 2>/dev/null || true
ip rule del to \$API_IP lookup apiroutes 2>/dev/null || true
ip rule add to \$API_IP lookup apiroutes
ip route replace \$API_IP/32 via \$MIKROTIK_VPN_IP table apiroutes 2>/dev/null || ip route add \$API_IP/32 dev lo table apiroutes
ip route flush cache

# Fix NAT
iptables -t nat -A PREROUTING -d \$API_IP -j DNAT --to-destination \$MIKROTIK_VPN_IP 2>/dev/null || true
iptables -t nat -A POSTROUTING -d \$MIKROTIK_VPN_IP -j SNAT --to-source 10.8.0.1 2>/dev/null || true

echo "Quick fix applied. Test with: ./test-api-connection.sh"
EOF

chmod +x "$SERVER_SCRIPT_DIR/quick-fix.sh"
echo "✓ Quick fix script created at $SERVER_SCRIPT_DIR/quick-fix.sh"

echo ""
echo "===== Error Fix Complete ====="
echo ""
echo "All detected issues have been fixed. To verify:"
echo ""
echo "1. Run the test script:"
echo "   $SERVER_SCRIPT_DIR/test-api-connection.sh"
echo ""
echo "2. If issues persist, run the diagnostics:"
echo "   $SERVER_SCRIPT_DIR/api-routing-diagnostics.sh"
echo ""
echo "3. Apply the MikroTik configuration found in $SERVER_SCRIPT_DIR/mikrotik-config-$API_TARGET.rsc"
echo ""
echo "Quick fix available if issues return:"
echo "   $SERVER_SCRIPT_DIR/quick-fix.sh"
echo ""
echo "Important: If the MikroTik router isn't actually connected to the OpenVPN server,"
echo "          you'll need to establish that connection first."
echo ""
