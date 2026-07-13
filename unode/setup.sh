#!/bin/bash
# unode/setup.sh
# Master setup script for node2 (Ubuntu 26 LTS - Primary DNS)
# Run this as root on node2.
#
# Usage: sudo ./setup.sh [X-value]

set -euo pipefail

X="${1:-33}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " node2 Setup - Primary DNS"
echo " 192.168.${X}.133/25 on internal network"
echo " Domain: ${X}network.net"
echo "============================================"

# 1. Network configuration
echo ""
echo "=== Step 1: Network Configuration ==="
bash "${SCRIPT_DIR}/configure-network.sh" "$X"

# 2. Install and configure BIND9 as primary DNS
echo ""
echo "=== Step 2: BIND9 Primary DNS ==="
bash "${SCRIPT_DIR}/configure-bind-primary.sh" "$X"

# 3. Configure firewall
echo ""
echo "=== Step 3: Firewall (nftables) ==="
bash "${SCRIPT_DIR}/configure-firewall.sh" "$X"

echo ""
echo "============================================"
echo " node2 (Primary DNS) setup complete!"
echo "============================================"
echo ""
echo "Verify with:"
echo "  ip addr show"
echo "  nft list ruleset"
echo "  systemctl status named"
echo "  dig @localhost ${X}network.net"
echo "  dig @192.168.${X}.133 node2.${X}network.net"
echo "  dig @192.168.${X}.133 -x 192.168.${X}.5"
echo "============================================"
