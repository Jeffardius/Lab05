#!/bin/bash
# unode/configure-network.sh
# Configures netplan for node2 (end node):
#   NIC1: Static 192.168.X.133/25 on internal network
#   Gateway: 192.168.X.132 (node1's internal IP)
#   DNS: self (192.168.X.133), then gateway (192.168.X.5)

set -euo pipefail

X="${1:-33}"
DOMAIN="${2:-${X}network.net}"
NODE2_IP="192.168.${X}.133/25"
GATEWAY_EXT_IP="192.168.${X}.5"

echo "[NETWORK] Setting hostname to node2.${DOMAIN}"
hostnamectl set-hostname "node2.${DOMAIN}"
sed -i "s/127.0.1.1.*/127.0.1.1\tnode2.${DOMAIN} node2/" /etc/hosts

echo "[NETWORK] Detecting network interface..."
# Find the single non-loopback interface
INT_IFACE=""
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  [ "$name" = "lo" ] && continue
  INT_IFACE="$name"
  break
done
if [ -z "$INT_IFACE" ]; then
  echo "ERROR: No network interface found."
  exit 1
fi
echo "[NETWORK] Internal interface detected: $INT_IFACE"

# Write netplan config
NETPLAN_FILE="/etc/netplan/01-node2.yaml"
cat > "$NETPLAN_FILE" <<NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INT_IFACE:
      dhcp4: false
      addresses:
        - $NODE2_IP
      routes:
        - to: default
          via: 192.168.${X}.132
      nameservers:
        addresses:
          - 127.0.0.1
          - $GATEWAY_EXT_IP
        search:
          - $DOMAIN
NETEOF

echo "[NETWORK] Netplan written to $NETPLAN_FILE"
netplan apply
echo "[NETWORK] Netplan applied successfully"
echo "  Interface: $INT_IFACE ($NODE2_IP)"
echo "  Gateway: 192.168.${X}.132"
echo "  DNS: 127.0.0.1, ${GATEWAY_EXT_IP}"
