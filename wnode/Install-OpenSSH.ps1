<#
.SYNOPSIS
    Installs and configures OpenSSH Server on node1 (Windows Server 2022).
.DESCRIPTION
    Run this as Administrator on the Windows VM first, then from gateway
    you can use setup-passwordless-ssh-to-windows.sh to copy the key.
#>

Write-Host "=== Installing OpenSSH Server ===" -ForegroundColor Cyan

# 1. Install OpenSSH Server capability
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
if ($cap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name "OpenSSH.Server*"
    Write-Host "  OpenSSH Server installed."
} else {
    Write-Host "  OpenSSH Server already installed."
}

# 2. Start sshd service and set to auto-start
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Host "  sshd service started (automatic startup)."

# 3. Firewall rule for SSH
New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
    -Direction Inbound -Protocol TCP -LocalPort 22 `
    -Action Allow -ErrorAction SilentlyContinue
Write-Host "  Firewall rule added for SSH (TCP/22)."

# 4. Create .ssh directory and authorized_keys for Administrator
$sshDir = "$env:USERPROFILE\.ssh"
$authKeys = Join-Path $sshDir "authorized_keys"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}
Write-Host ""
Write-Host "=== NEXT STEP ===" -ForegroundColor Yellow
Write-Host "From your gateway VM, run this to add the public key:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  sudo ./gateway/setup-passwordless-ssh-to-windows.sh 33 YourAdminPassword" -ForegroundColor Green
Write-Host ""
Write-Host "Or manually paste the gateway's public key into this file:" -ForegroundColor Yellow
Write-Host "  $authKeys" -ForegroundColor Cyan
Write-Host ""

# 5. Verify sshd is running
$status = Get-Service sshd | Format-Table Status, Name, DisplayName -AutoSize | Out-String
Write-Host "=== Service Status ===" -ForegroundColor Cyan
Write-Host $status
