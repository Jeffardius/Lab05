#!/bin/bash
# gateway/configure-firewall.sh
# Configures nftables firewall on the gateway:
#   - inet filter table: default-deny input/forward, allow essential services
#   - nat table: postrouting masquerade for traffic leaving via NAT interface
#
# Requirements from lab:
#   - Ubuntu machines use nftables (inet filter table)
#   - Gateway also uses postrouting chain of nat table to masquerade traffic
#   - Firewall must be active and restrictive (not allowing all traffic)
#   - AppArmor must remain active

set -euo pipefail

X="${1:-33}"
GATEWAY_EXT_IP="192.168.${X}.5"

echo "[FIREWALL] Installing nftables..."
apt install -y nftables

# Detect interfaces
NAT_IFACE=$(ip route show default | awk '{print $5}' | head -1)
if [ -z "$NAT_IFACE" ]; then
  echo "ERROR: Cannot detect NAT interface. Default route missing."
  exit 1
fi

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

echo "[FIREWALL] NAT interface: $NAT_IFACE"
echo "[FIREWALL] External interface: $EXT_IFACE"

# Flush existing rules
nft flush ruleset

cat > /etc/nftables.conf <<NFTEOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Allow loopback
        iif lo accept

        # Allow established/related connections
        ct state established,related accept

        # Allow SSH from anywhere on any interface
        tcp dport 22 accept

        # Allow DNS queries (UDP + TCP)
        tcp dport 53 accept
        udp dport 53 accept

        # Allow ICMP (ping)
        icmp type echo-request accept
        icmpv6 type echo-request accept

        # Allow traffic from lab networks to gateway services
        iifname "$EXT_IFACE" ip saddr 192.168.${X}.0/25 accept
        iifname "$EXT_IFACE" ip saddr 192.168.${X}.128/25 accept

        # Log and drop everything else
        log prefix "NFT_INPUT_DROP: " flags all counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;

        # Prevent routing within the same interface
        iif "${NAT_IFACE}" oif "${NAT_IFACE}" drop
        iif "$EXT_IFACE" oif "$EXT_IFACE" drop

        # From lab networks -> internet (out via NAT interface)
        iif "$EXT_IFACE" ip saddr 192.168.${X}.0/25 oif "${NAT_IFACE}" accept
        iif "$EXT_IFACE" ip saddr 192.168.${X}.128/25 oif "${NAT_IFACE}" accept

        # From internet -> lab networks (only established/related replies)
        iif "${NAT_IFACE}" oif "$EXT_IFACE" ct state established,related accept

        # Forward DNS between networks
        ip protocol { tcp, udp } th dport 53 accept

        # Forward established connections in both directions
        ct state established,related accept

        log prefix "NFT_FORWARD_DROP: " flags all counter drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        # Masquerade traffic from lab networks going out to the internet
        ip saddr 192.168.${X}.0/25 oif "${NAT_IFACE}" masquerade
        ip saddr 192.168.${X}.128/25 oif "${NAT_IFACE}" masquerade
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
    }
}
NFTEOF

echo "[FIREWALL] Loading nftables rules..."
nft -f /etc/nftables.conf

echo "[FIREWALL] Enabling nftables service..."
systemctl enable nftables
systemctl restart nftables

echo "[FIREWALL] Gateway firewall configured successfully."
echo "  NAT interface: $NAT_IFACE"
echo "  Rules: inet filter (drop by default) + ip nat (masquerade)"
