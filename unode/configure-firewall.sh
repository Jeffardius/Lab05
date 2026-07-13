#!/bin/bash
# unode/configure-firewall.sh
# Configures nftables firewall on node2 (Ubuntu end node):
#   - inet filter table: default-deny input/forward
#   - Allow DNS, SSH, ICMP from internal network
#   - No NAT needed (node2 is not a gateway)

set -euo pipefail

X="${1:-33}"
NODE2_INT_IP="192.168.${X}.133"

echo "[FIREWALL] Installing nftables..."
apt install -y nftables

# Detect the internal interface
INT_IFACE=$(ip -o addr show | grep "${NODE2_INT_IP}" | awk '{print $2}' | head -1)
if [ -z "$INT_IFACE" ]; then
  echo "WARNING: Could not detect interface with ${NODE2_INT_IP}, using first non-lo"
  INT_IFACE=""
  for iface in /sys/class/net/*; do
    name=$(basename "$iface")
    [ "$name" = "lo" ] && continue
    INT_IFACE="$name"
    break
  done
fi
echo "[FIREWALL] Internal interface: $INT_IFACE"

nft flush ruleset

cat > /etc/nftables.conf <<NFTEOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        iif lo accept
        ct state established,related accept
        tcp dport 22 accept
        tcp dport 53 accept
        udp dport 53 accept
        icmp type echo-request accept
        icmpv6 type echo-request accept

        # Allow zone transfer from secondary (node1) - TCP
        ip saddr 192.168.${X}.0/25 tcp dport 53 accept

        log prefix "NFT_INPUT_DROP: " flags all counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        log prefix "NFT_FORWARD_DROP: " flags all counter drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
NFTEOF

echo "[FIREWALL] Loading nftables rules..."
nft -f /etc/nftables.conf

echo "[FIREWALL] Enabling nftables service..."
systemctl enable nftables
systemctl restart nftables

echo "[FIREWALL] node2 firewall configured successfully."
