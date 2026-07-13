#!/bin/bash
# gateway/setup-passwordless-ssh-to-windows.sh
# Run on gateway AFTER wnode/Install-OpenSSH.ps1 ran on Windows.
# Uses schtasks as SYSTEM to write to administrators_authorized_keys
# (bypasses UAC - direct write is blocked by filtered admin token).
#
# Usage: sudo ./setup-passwordless-ssh-to-windows.sh [X] [AdminPassword]

set -euo pipefail

X="${1:-33}"
WIN_PASS="${2:-Password123!}"
NODE1_EXT_IP="192.168.${X}.6"
WIN_USER="Administrator"
KEY_COMMENT="gateway@${X}network.net"

# These paths must be absolute (schtasks as SYSTEM has different env vars)
ABS_TEMP="C:\\Users\\${WIN_USER}\\AppData\\Local\\Temp"
ABS_SSH="C:\\ProgramData\\ssh"

echo "============================================"
echo " Passwordless SSH Gateway -> node1 (Windows)"
echo " Target: ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"

echo ""
echo "=== Step 1: Generating SSH key ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    mkdir -p ~/.ssh
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "$KEY_COMMENT"
    echo "  New key generated."
else
    echo "  Key already exists, reusing it."
fi

PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

echo ""
echo "=== Step 2: Installing sshpass ==="
if ! command -v sshpass &>/dev/null; then
    apt update && apt install -y sshpass
fi

echo ""
echo "=== Step 3: Writing public key to Windows temp ==="
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" \
  "powershell -EncodedCommand $(echo -n "Set-Content -Path \"${ABS_TEMP}\\pubkey.txt\" -Value '${PUB_KEY}' -Encoding ASCII -Force" | iconv -t UTF-16LE | base64 -w0)" 2>&1 | grep -v CLIXML | grep -v Objs
echo "  Temp file written."

echo ""
echo "=== Step 4: Deploying key via SYSTEM schtasks ==="

schtask_run() {
    local name="$1" cmd="$2"
    sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" \
      "schtasks /create /tn ${name} /tr \"${cmd}\" /sc onlogon /ru SYSTEM /f" 2>&1
    sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" \
      "schtasks /run /tn ${name}" 2>&1
    sleep 2
    sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" \
      "schtasks /delete /tn ${name} /f" 2>&1
}

echo "  Deleting old key file..."
schtask_run "DelKey" "cmd /c if exist ${ABS_SSH}\\administrators_authorized_keys del /f /q ${ABS_SSH}\\administrators_authorized_keys"

echo "  Copying new key..."
schtask_run "CopyKey" "cmd /c copy /Y ${ABS_TEMP}\\pubkey.txt ${ABS_SSH}\\administrators_authorized_keys"

echo "  Setting permissions..."
schtask_run "LockKey" "cmd /c icacls ${ABS_SSH}\\administrators_authorized_keys /inheritance:r /grant SYSTEM:(R) /grant Administrator:(R)"

echo ""
echo "=== Step 5: Restarting sshd ==="
sshpass -p "$WIN_PASS" ssh -o StrictHostKeyChecking=no "${WIN_USER}@${NODE1_EXT_IP}" \
  "powershell Restart-Service sshd -Force" 2>&1 | grep -v CLIXML | grep -v Objs
sleep 2

echo ""
echo "=== Step 6: Testing passwordless login ==="
if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ~/.ssh/id_ed25519 \
     "${WIN_USER}@${NODE1_EXT_IP}" "hostname && echo SUCCESS" 2>&1; then
    echo ""
    echo "  PASSWORDLESS SSH IS WORKING!"
else
    echo ""
    echo "  FAILED. Debug: ssh -vvv -o BatchMode=yes ${WIN_USER}@${NODE1_EXT_IP}"
fi

echo ""
echo "============================================"
echo " Connect: ssh ${WIN_USER}@${NODE1_EXT_IP}"
echo "============================================"
