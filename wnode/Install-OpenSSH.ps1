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
    Write-Host "  Installing OpenSSH Server capability..."
    $result = Add-WindowsCapability -Online -Name "OpenSSH.Server*"
    if ($result.RestartNeeded -eq $true) {
        Write-Host "  A restart will be required. Rebooting now..."
        Restart-Computer -Force
        exit
    }
    Write-Host "  OpenSSH Server installed."
} else {
    Write-Host "  OpenSSH Server already installed."
}

# 2. Try to find the sshd service (may be under different name)
$sshd = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if (-not $sshd) {
    $sshd = Get-Service | Where-Object { $_.DisplayName -like "*OpenSSH*SSH*Server*" } | Select-Object -First 1
}
if (-not $sshd) {
    Write-Host "  sshd service not found. Checking if deployment needs to be finalized..."
    # Sometimes Start-Service deployment finalization helps
    & "$env:SystemRoot\System32\OpenSSH\sshd.exe" --install 2>$null
    Start-Sleep -Seconds 2
    $sshd = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
}
if (-not $sshd) {
    Write-Host "  sshd service still not found. Attempting direct sshd execution..."
    & "$env:SystemRoot\System32\OpenSSH\sshd.exe" 2>$null
    Start-Sleep -Seconds 2
}

if ($sshd) {
    Set-Service -Name $sshd.Name -StartupType Automatic
    Start-Service -Name $sshd.Name
    Write-Host "  sshd service started (automatic startup)."
} else {
    Write-Host "  Could not register sshd as a service, but sshd may be running directly."
    Write-Host "  Check with: Get-Process sshd"
}

# 3. Firewall rule for SSH
$fwRule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
        -Direction Inbound -Protocol TCP -LocalPort 22 `
        -Action Allow
    Write-Host "  Firewall rule added for SSH (TCP/22)."
} else {
    Write-Host "  Firewall rule already exists."
}

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

# 5. Verify
Write-Host "=== Service Status ===" -ForegroundColor Cyan
$proc = Get-Process -Name "sshd" -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "  sshd is RUNNING (PID: $($proc.Id))" -ForegroundColor Green
} else {
    Write-Host "  sshd process not found. Try rebooting the VM." -ForegroundColor Yellow
}
