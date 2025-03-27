#!/bin/bash
# Cleanup script - Remove unnecessary files and fix routing table duplicates

# Remove unnecessary scripts
echo "Removing unnecessary files..."
rm -f gateway-fix.sh diagnostics.sh api-routing-fix.sh fix-routing-errors.sh \
      fix-api-routing.sh setup-mikrotik-routing.sh verify_routing.sh

# Fix duplicate routing table entries
if [ -f /etc/iproute2/rt_tables ]; then
    echo "Fixing duplicate routing table entries..."
    grep -v "apiroutes" /etc/iproute2/rt_tables > /tmp/rt_tables.new
    echo "200 apiroutes" >> /tmp/rt_tables.new
    mv /tmp/rt_tables.new /etc/iproute2/rt_tables
    echo "Routing tables fixed"
fi

echo "Cleanup complete"
