# OpenVPN Routing Conclusion for MikroTik ISP Setup

**Scenario:**
- OpenVPN server running on a cloud machine.
- MikroTik RouterOS connects to the OpenVPN server as a client.
- MikroTik RouterOS provides internet service to end users (RouterOS -> OLT -> ONU).

**Question:** Which IP address will the end users get for internet access (VPN IP or ISP IP)?

**Conclusion:**

The end users will get the **ISP IP address of the OpenVPN server** (the public IP of the cloud machine) for their internet access.

**Reasoning:**

1.  **`redirect-gateway def1 bypass-dhcp`:** Your OpenVPN server configuration pushes this directive to clients. This forces all client internet traffic (including the MikroTik router's traffic) through the VPN tunnel.
2.  **`net.ipv4.ip_forward=1`:** This setting is enabled on your OpenVPN server, allowing it to act as a router and forward packets between interfaces.
3.  **NAT (Masquerading):** Network Address Translation must be configured on the OpenVPN server's external network interface (e.g., `eth0`). This rewrites the source IP address of packets leaving the server from the internal VPN IP (e.g., 10.8.0.x) to the server's public ISP IP.

**Required Configuration Steps on OpenVPN Server:**

1.  **Server Config (`/etc/openvpn/server.conf`):**
    *   Ensure `push "redirect-gateway def1 bypass-dhcp"` is present.
    *   Ensure `push "dhcp-option DNS <DNS_IP>"` is present (e.g., `push "dhcp-option DNS 8.8.8.8"`).
2.  **IP Forwarding:**
    *   Ensure `net.ipv4.ip_forward=1` is set (e.g., in `/etc/sysctl.conf` or `/etc/sysctl.d/99-openvpn.conf`) and applied (`sudo sysctl -p`).
3.  **NAT/Masquerading (Example using UFW):**
    *   Edit `/etc/ufw/before.rules`.
    *   Add the following lines *before* the `*filter` section:
        ```
        *nat
        :POSTROUTING ACCEPT [0:0]
        -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
        COMMIT
        ```
        *(Replace `10.8.0.0/24` with your VPN subnet and `eth0` with your server's actual public network interface)*.
    *   Ensure UFW's default forward policy is ACCEPT: Edit `/etc/default/ufw` and set `DEFAULT_FORWARD_POLICY="ACCEPT"`.
    *   Allow the OpenVPN port: `sudo ufw allow <port>/<protocol>` (e.g., `sudo ufw allow 1194/udp`).
    *   Reload UFW: `sudo ufw reload`.
4.  **Restart OpenVPN:**
    *   `sudo systemctl restart openvpn@server` (or the appropriate service name).

By following these steps, all internet traffic originating from the end users behind the MikroTik router will be routed through the OpenVPN tunnel and appear to originate from the OpenVPN server's public IP address.