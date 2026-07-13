<#
.SYNOPSIS
    Installs and configures OpenSSH Server on node1 (Windows Server 2022).
.DESCRIPTION
    Run this as Administrator on the Windows VM.
    Uses winget or Add-WindowsCapability to install OpenSSH Server.
#>

Write-Host "=== Installing OpenSSH Server ===" -ForegroundColor Cyan
$sshdPath = $null

# Attempt 1: winget (App Installer, built into Windows Server 2022)
Write-Host "  Attempt 1: winget..."
$wingetResult = winget install "Microsoft.OpenSSH.Beta" --accept-source-agreements --accept-package-agreements 2>&1
if ($LASTEXITCODE -eq 0) {
    # Check where winget installed it
    $possiblePaths = @(
        "$env:SystemRoot\System32\OpenSSH\sshd.exe",
        "${env:ProgramFiles}\OpenSSH\sshd.exe",
        "${env:ProgramFiles}\OpenSSH-Win64\sshd.exe"
    )
    foreach ($p in $possiblePaths) {
        if (Test-Path $p) { $sshdPath = $p; break }
    }
}

# Attempt 2: Add-WindowsCapability
if (-not $sshdPath) {
    Write-Host "  Attempt 2: Add-WindowsCapability..."
    $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
    if ($cap.State -ne "Installed") {
        $result = Add-WindowsCapability -Online -Name "OpenSSH.Server*"
        if ($result.RestartNeeded) {
            Write-Host "  Restart needed. Rebooting..." -ForegroundColor Yellow
            Restart-Computer -Force
            exit
        }
    }
    # After install, check the expected location
    $normalPath = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
    if (Test-Path $normalPath) { $sshdPath = $normalPath }
}

# Attempt 3: Search PATH
if (-not $sshdPath) {
    Write-Host "  Attempt 3: Searching PATH..."
    $sshdPath = (Get-Command sshd.exe -ErrorAction SilentlyContinue).Source
}

# Attempt 4: Full search (excluding Git as it's not the right one)
if (-not $sshdPath) {
    Write-Host "  Attempt 4: Searching system drive..."
    $sshdPath = Get-ChildItem -Path "$env:SystemDrive\" -Filter "sshd.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*Git*" } |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $sshdPath) {
    Write-Host "  ERROR: Could not find sshd.exe. Trying DISM offline deployment..." -ForegroundColor Red
    dism /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0
    $normalPath = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
    Start-Sleep -Seconds 5
    if (Test-Path $normalPath) { $sshdPath = $normalPath }
}

if (-not $sshdPath) {
    Write-Host "  FATAL: sshd.exe not found. Reboot the VM and try again." -ForegroundColor Red
    exit 1
}

Write-Host "  Found sshd.exe at: $sshdPath" -ForegroundColor Green

# Install and start the sshd service
$sshdService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if (-not $sshdService) {
    Write-Host "  Installing sshd service..."
    & "$sshdPath" --install
    Start-Sleep -Seconds 2
    $sshdService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
}

if ($sshdService) {
    Set-Service -Name $sshdService.Name -StartupType Automatic
    Start-Service -Name $sshdService.Name
    Write-Host "  sshd service started (automatic)." -ForegroundColor Green
} else {
    Write-Host "  Starting sshd directly..."
    Start-Process -FilePath $sshdPath -WindowStyle Hidden
}

# Firewall rule
$fwRule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
        -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
    Write-Host "  Firewall rule added."
}

# Create .ssh dir
$sshDir = "$env:USERPROFILE\.ssh"
$authKeys = Join-Path $sshDir "authorized_keys"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

Write-Host ""
Write-Host "=== NEXT STEP ===" -ForegroundColor Yellow
Write-Host "From gateway, run:" -ForegroundColor Yellow
Write-Host "  sudo ./gateway/setup-passwordless-ssh-to-windows.sh 33 YourAdminPassword" -ForegroundColor Green
Write-Host ""

# Verify
Write-Host "=== Verification ===" -ForegroundColor Cyan
$svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
$proc = Get-Process -Name "sshd" -ErrorAction SilentlyContinue
$port = netstat -ano 2>$null | Select-String ":22 "

if ($svc -and $svc.Status -eq "Running") {
    Write-Host "  sshd service: RUNNING" -ForegroundColor Green
} elseif ($proc) {
    Write-Host "  sshd process: RUNNING" -ForegroundColor Green
} else {
    Write-Host "  sshd: NOT running" -ForegroundColor Red
}
if ($port) { Write-Host "  Port 22: LISTENING" -ForegroundColor Green }
else { Write-Host "  Port 22: NOT listening" -ForegroundColor Red }
