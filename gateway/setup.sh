#!/bin/bash
# gateway/setup.sh
# Master setup script for the gateway VM (Ubuntu 26 LTS)
# Run this as root on the gateway machine.
#
# Usage: sudo ./setup.sh [X-value]
#   X-value defaults to 33 if not provided

set -euo pipefail

X="${1:-33}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " Gateway Setup - 192.168.${X}.0/24"
echo " Domain: ${X}network.net"
echo "============================================"

# 1. Network configuration + hostname + IP forwarding
echo ""
echo "=== Step 1: Network Configuration ==="
bash "${SCRIPT_DIR}/configure-network.sh" "$X"

# 2. Install and configure BIND9 as caching forwarder
echo ""
echo "=== Step 2: BIND9 Caching Forwarder ==="
bash "${SCRIPT_DIR}/configure-bind.sh" "$X"

# 3. Configure firewall with nftables
echo ""
echo "=== Step 3: Firewall (nftables) ==="
bash "${SCRIPT_DIR}/configure-firewall.sh" "$X"

echo ""
echo "============================================"
echo " Gateway setup complete!"
echo "============================================"
echo ""
echo "Verify with:"
echo "  ip addr show"
echo "  ip route show"
echo "  nft list ruleset"
echo "  systemctl status named"
echo "  dig @localhost google.com"
echo "  dig @${X}.5 google.com"
echo "============================================"
