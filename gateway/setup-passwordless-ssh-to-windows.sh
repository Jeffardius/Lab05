#!/bin/bash
# gateway/setup-passwordless-ssh-to-windows.sh
# Run this on the gateway to enable passwordless SSH into node1 (Windows Server 2022).
#
# Prerequisites:
#   - gateway can reach node1 (ping 192.168.X.6)
#   - Windows node1 has OpenSSH Server installed (script handles this remotely via PowerShell)
#   - Windows Administrator password is known
#
# Usage: sudo ./setup-passwordless-ssh-to-windows.sh [X-value] [WindowsAdminPassword]

set -euo pipefail

X="${1:-33}"
WIN_PASS="${2:-Password123!}"  # default, user should override
NODE1_EXT_IP="192.168.${X}.6"
WIN_USER="Administrator"

echo "============================================"
echo " Passwordless SSH Gateway -> node1 (Windows)"
echo " Target: ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"

# 1. Generate SSH key if not exists
echo ""
echo "=== Step 1: Generating SSH key ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    mkdir -p ~/.ssh
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "gateway@${X}network.net"
    echo "  Key generated: ~/.ssh/id_ed25519.pub"
else
    echo "  Key already exists, reusing it."
fi

PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
echo "  Public key: $PUB_KEY"

# 2. Install sshpass for non-interactive password entry
echo ""
echo "=== Step 2: Installing sshpass ==="
if ! command -v sshpass &>/dev/null; then
    apt update && apt install -y sshpass
fi
echo "  sshpass installed."

# 3. Ensure OpenSSH Server is running on Windows node1
echo ""
echo "=== Step 3: Configuring OpenSSH Server on node1 ==="
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" <<'POWERSHELL'
    Write-Host "  Installing OpenSSH Server..."
    $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
    if ($cap.State -ne "Installed") {
        Add-WindowsCapability -Online -Name "OpenSSH.Server*"
    }
    Write-Host "  Enabling sshd service..."
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    Write-Host "  Configuring firewall for SSH..."
    New-NetFirewallRule -DisplayName "SSH-In" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -ErrorAction SilentlyContinue
    Write-Host "  Windows OpenSSH setup complete."
POWERSHELL
echo "  OpenSSH Server configured on node1."

# 4. Copy the public key to Windows node1's authorized_keys
echo ""
echo "=== Step 4: Copying public key to node1 ==="
# Ensure the .ssh directory and authorized_keys file exist on Windows
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" "powershell -Command \"
    \$sshDir = \"\$env:USERPROFILE\\.ssh\";
    if (-not (Test-Path \$sshDir)) { New-Item -ItemType Directory -Path \$sshDir };
    \$authKeys = Join-Path \$sshDir 'authorized_keys';
    if (-not (Test-Path \$authKeys)) { New-Item -ItemType File -Path \$authKeys };
    Get-Content \$authKeys | Select-String -Pattern 'gateway@${X}network.net' -Quiet
\""

# Append the public key (idempotent - uses cat to pipe)
echo "$PUB_KEY" | sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" "powershell -Command \"
    \$sshDir = \"\$env:USERPROFILE\\.ssh\";
    \$authKeys = Join-Path \$sshDir 'authorized_keys';
    \$key = '$PUB_KEY';
    \$existing = Get-Content \$authKeys -ErrorAction SilentlyContinue;
    if (\$existing -notcontains \$key) {
        Add-Content -Path \$authKeys -Value \$key;
        Write-Host '  Public key added to authorized_keys.';
    } else {
        Write-Host '  Public key already present.';
    }
\""

# Fix permissions on Windows (sshd is picky about authorized_keys permissions)
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" "powershell -Command \"
    \$sshDir = \"\$env:USERPROFILE\\.ssh\";
    \$authKeys = Join-Path \$sshDir 'authorized_keys';
    # Remove inheritance and set explicit permissions (only Administrator)
    icacls \$authKeys /inheritance:r /grant 'Administrator:R' /grant 'SYSTEM:R'
    icacls \$sshDir /inheritance:r /grant 'Administrator:RX' /grant 'SYSTEM:RX'
    Write-Host '  Permissions fixed.'
\""

# 5. Test passwordless login
echo ""
echo "=== Step 5: Testing passwordless SSH ==="
sleep 2
ssh -o StrictHostKeyChecking=no -o BatchMode=yes "${WIN_USER}@${NODE1_EXT_IP}" "hostname && whoami" && \
    echo "  SUCCESS: Passwordless SSH to node1 is working!" || \
    echo "  FAIL: Still prompted for password. Check permissions."

echo ""
echo "============================================"
echo " Done. You can now SSH without a password:"
echo "   ssh ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"
