#!/bin/bash
# gateway/setup-passwordless-ssh-to-windows.sh
# Run this on the gateway AFTER running wnode/Install-OpenSSH.ps1 on Windows.
# Copies the gateway's public key to node1 for passwordless SSH.
#
# Prerequisites:
#   - OpenSSH Server running on node1 (run Install-OpenSSH.ps1 first)
#   - gateway can reach node1 (ping 192.168.X.6)
#   - Windows Administrator password is known
#
# Usage: sudo ./setup-passwordless-ssh-to-windows.sh [X-value] [AdminPassword]

set -euo pipefail

X="${1:-33}"
WIN_PASS="${2:-Password123!}"
NODE1_EXT_IP="192.168.${X}.6"
WIN_USER="Administrator"

echo "============================================"
echo " Passwordless SSH Gateway -> node1 (Windows)"
echo " Target: ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"

echo ""
echo "=== Step 1: Generating SSH key ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    mkdir -p ~/.ssh
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "gateway@${X}network.net"
    echo "  New key generated."
else
    echo "  Key already exists, reusing it."
fi

PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
echo "  Public key: $PUB_KEY"

echo ""
echo "=== Step 2: Installing sshpass ==="
if ! command -v sshpass &>/dev/null; then
    apt update && apt install -y sshpass
fi
echo "  sshpass installed."

echo ""
echo "=== Step 3: Copying public key to Windows node1 ==="
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" "powershell -Command \"
    \$sshDir = \"\$env:USERPROFILE\\.ssh\";
    if (-not (Test-Path \$sshDir)) { New-Item -ItemType Directory -Path \$sshDir -Force };

    \$authKeys = Join-Path \$sshDir 'authorized_keys';
    \$existingKeys = Get-Content \$authKeys -ErrorAction SilentlyContinue;

    \$key = '$PUB_KEY';
    if (\$existingKeys -notcontains \$key) {
        Add-Content -Path \$authKeys -Value \$key;
        Write-Host '  Public key added.';
    } else {
        Write-Host '  Public key already present.';
    }

    # Fix permissions
    icacls \$authKeys /inheritance:r /grant 'Administrator:R' /grant 'SYSTEM:R'
    icacls \$sshDir /inheritance:r /grant 'Administrator:RX' /grant 'SYSTEM:RX'
    Write-Host '  Permissions fixed.'
\""

echo ""
echo "=== Step 4: Testing passwordless login ==="
sleep 2
if ssh -o StrictHostKeyChecking=no -o BatchMode=yes "${WIN_USER}@${NODE1_EXT_IP}" "hostname && echo 'SUCCESS'" 2>&1; then
    echo ""
    echo "  Passwordless SSH is working!"
else
    echo ""
    echo "  FAILED. Check that:"
    echo "    1. OpenSSH Server is running on node1 (Install-OpenSSH.ps1)"
    echo "    2. Firewall on node1 allows TCP/22"
    echo "    3. Administrator password is correct"
    echo "    4. node1 is reachable from gateway"
fi

echo ""
echo "============================================"
echo " Connect: ssh ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"
