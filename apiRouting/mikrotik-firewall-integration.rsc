# MikroTik Firewall Integration for API Routing
# This configuration integrates with your existing firewall rules

# 1. Create an address list for API targets (makes it easy to add more APIs later)
/ip firewall address-list
add address=api.ipify.org list=api_targets comment="API Targets for Routing"

# 2. Add proper NAT rules that won't conflict with existing rules
/ip firewall nat
add chain=srcnat action=masquerade src-address=10.8.0.1 dst-address-list=api_targets \
    comment="API Traffic NAT" place-before=0

# 3. Add required routes
/ip route
add dst-address=104.26.12.205/32 gateway=10.8.0.1 distance=1 comment="API ipify route"
add dst-address=104.26.13.205/32 gateway=10.8.0.1 distance=1 comment="API ipify route alt"
add dst-address=172.67.74.152/32 gateway=10.8.0.1 distance=1 comment="API ipify route alt2"

# 4. Static DNS entries to prevent DNS leakage
/ip dns static
add type=A name=api.ipify.org address=104.26.12.205 comment="API DNS Entry"

# 5. Automatic API IP tracker script
/system script
add name=track-api-ips source={
    :local apiDomains {"api.ipify.org"};
    :log info "Checking API IP addresses...";
    
    :foreach domain in=$apiDomains do={
        :local apiIP [:resolve $domain];
        :log info "Domain $domain resolved to $apiIP";
        
        # Check if route exists
        :local routeExists false;
        :foreach r in=[/ip route find where comment~"API .* route"] do={
            :local dst [/ip route get $r dst-address];
            :if ($dst = "$apiIP/32") do={
                :set routeExists true;
            }
        }
        
        # Add new route if needed
        :if (!$routeExists) do={
            :log info "Adding new route for $domain to $apiIP"; 
            /ip route add dst-address="$apiIP/32" gateway=10.8.0.1 distance=1 comment="API $domain route";
            # Update address list too
            :local inList false;
            :foreach i in=[/ip firewall address-list find where list="api_targets"] do={
                :local addr [/ip firewall address-list get $i address];
                :if ($addr = "$apiIP") do={
                    :set inList true;
                }
            }
            :if (!$inList) do={
                /ip firewall address-list add address=$apiIP list=api_targets comment="$domain IP";
            }
        }
    }
}

# 6. Schedule automatic updates
/system scheduler
add interval=30m name=update-api-routes on-event=track-api-ips policy=read,write,test \
    start-time=startup comment="Update API routes every 30 minutes"
