# ===== ROUTER OS CONFIGURATION GUIDE =====
# Follow these steps after transferring the certificate files to RouterOS

# 1. Import certificates using WinBox:
#   - Go to System > Certificates
#   - Import ca.crt
#   - Import CLIENT_NAME.crt
#   - Import CLIENT_NAME.key

# 2. Or use these terminal commands:
/certificate import file-name=ca.crt
/certificate import file-name=CLIENT_NAME.crt
/certificate import file-name=CLIENT_NAME.key

# 3. Set up OpenVPN client (Replace placeholders with your values):
/interface ovpn-client add \
  name=ovpn-out \
  connect-to=YOUR_CLOUD_SERVER_IP \
  port=VPN_PORT \
  user=nobody \
  mode=ip \
  certificate=CLIENT_NAME.crt_0 \
  auth=sha1 \
  cipher=aes256 \
  add-default-route=yes

# 4. Check connection status:
/interface ovpn-client print
/ip address print