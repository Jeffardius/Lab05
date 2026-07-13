<#
.SYNOPSIS
    Installs OpenSSH Server on node1 (Windows Server 2022).
.DESCRIPTION
    Run this as Administrator on the Windows VM first.
    Then run gateway/setup-passwordless-ssh-to-windows.sh from the gateway.
#>

Write-Host "=== Installing OpenSSH Server ===" -ForegroundColor Cyan

# 1. Install via Add-WindowsCapability
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
if ($cap.State -ne "Installed") {
    Write-Host "  Installing OpenSSH Server capability..."
    $result = Add-WindowsCapability -Online -Name "OpenSSH.Server*"
    if ($result.RestartNeeded) {
        Write-Host "  Restart required. Rebooting..." -ForegroundColor Yellow
        Restart-Computer -Force
        exit
    }
    Write-Host "  OpenSSH Server installed."
} else {
    Write-Host "  OpenSSH Server already installed."
}

# 2. Verify sshd.exe
$sshdPath = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
if (-not (Test-Path $sshdPath)) {
    Write-Host "  ERROR: sshd.exe not found at $sshdPath" -ForegroundColor Red
    exit 1
}
Write-Host "  Found: $sshdPath"

# 3. Install and start sshd service
$svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if (-not $svc) {
    & "$sshdPath" --install
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
}
if ($svc) {
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    Write-Host "  sshd service: RUNNING" -ForegroundColor Green
} else {
    Write-Host "  WARNING: sshd service not found" -ForegroundColor Yellow
}

# 4. Firewall rule
if (-not (Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
        -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
    Write-Host "  Firewall rule added."
} else {
    Write-Host "  Firewall rule already exists."
}

Write-Host ""
Write-Host "=== NEXT STEP ===" -ForegroundColor Yellow
Write-Host "From the gateway VM, run:" -ForegroundColor Yellow
Write-Host "  sudo ./gateway/setup-passwordless-ssh-to-windows.sh 33 rumash1!" -ForegroundColor Green
