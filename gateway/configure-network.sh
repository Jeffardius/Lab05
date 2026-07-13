#!/bin/bash
# gateway/configure-network.sh
# Configures netplan for gateway:
#   NIC1: DHCP (NAT) - internet
#   NIC2: Static 192.168.33.5/25 - external network
# Also sets hostname and enables IP forwarding

set -euo pipefail

X="${1:-33}"
DOMAIN="${2:-${X}network.net}"
GATEWAY_EXT_IP="192.168.${X}.5/25"

echo "[NETWORK] Setting hostname to gateway.${DOMAIN}"
hostnamectl set-hostname "gateway.${DOMAIN}"
sed -i "s/127.0.1.1.*/127.0.1.1\tgateway.${DOMAIN} gateway/" /etc/hosts

echo "[NETWORK] Detecting interfaces..."
# Find the interface that currently has a default route (NAT/DHCP interface)
NAT_IFACE=$(ip route show default | awk '{print $5}' | head -1)
if [ -z "$NAT_IFACE" ]; then
  echo "ERROR: No default route found. Is the NAT interface connected?"
  exit 1
fi
echo "[NETWORK] NAT interface detected: $NAT_IFACE"

# Pick the other interface as the external/static one
EXT_IFACE=""
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  [ "$name" = "lo" ] && continue
  [ "$name" = "$NAT_IFACE" ] && continue
  EXT_IFACE="$name"
  break
done
if [ -z "$EXT_IFACE" ]; then
  echo "ERROR: Could not find a second interface for external network."
  exit 1
fi
echo "[NETWORK] External interface detected: $EXT_IFACE"

# Write netplan config
NETPLAN_FILE="/etc/netplan/01-gateway.yaml"
cat > "$NETPLAN_FILE" <<NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $NAT_IFACE:
      dhcp4: true
    $EXT_IFACE:
      dhcp4: false
      addresses:
        - $GATEWAY_EXT_IP
      nameservers:
        addresses:
          - 127.0.0.1
        search:
          - $DOMAIN
NETEOF

echo "[NETWORK] Netplan written to $NETPLAN_FILE"
netplan apply
echo "[NETWORK] Netplan applied successfully"

# Enable IP forwarding
echo "[NETWORK] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
cat > /etc/sysctl.d/99-gateway-forwarding.conf <<SYSCTLEOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTLEOF

echo "[NETWORK] Gateway network configuration complete."
echo "  NAT interface: $NAT_IFACE (DHCP)"
echo "  External interface: $EXT_IFACE ($GATEWAY_EXT_IP)"
echo "  Hostname: gateway.${DOMAIN}"
