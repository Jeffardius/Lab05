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
    if ($result.RestartNeeded -eq $true -or $result.RestartNeeded -eq $True) {
        Write-Host "  A restart is required. Rebooting now..."
        Restart-Computer -Force
        exit
    }
    Write-Host "  OpenSSH Server installed."
} else {
    Write-Host "  OpenSSH Server already installed."
}

# 2. Locate sshd.exe (could be in multiple possible locations)
$sshdPaths = @(
    "$env:SystemRoot\System32\OpenSSH\sshd.exe",
    "$env:SystemRoot\SysWOW64\OpenSSH\sshd.exe",
    "${env:ProgramFiles}\OpenSSH\bin\sshd.exe",
    "${env:ProgramFiles(x86)}\OpenSSH\bin\sshd.exe",
    "$env:SystemRoot\System32\sshd.exe"
)

$sshdPath = $null
foreach ($p in $sshdPaths) {
    if (Test-Path $p) {
        $sshdPath = $p
        break
    }
}

if (-not $sshdPath) {
    Write-Host "  Searching all drives for sshd.exe..."
    $sshdPath = Get-ChildItem -Path "$env:SystemDrive\" -Filter "sshd.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $sshdPath) {
    Write-Host "  ERROR: sshd.exe not found anywhere. OpenSSH install may have failed." -ForegroundColor Red
    Write-Host "  Try rebooting the VM and running this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "  Found sshd.exe at: $sshdPath"

# 3. Install and start the sshd service
$sshdDir = Split-Path $sshdPath -Parent

# Check if service already exists
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
    Write-Host "  sshd service started (automatic startup)."
} else {
    Write-Host "  Service registration failed. Running sshd directly..."
    Start-Process -FilePath $sshdPath -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# 4. Firewall rule for SSH
$fwRule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
        -Direction Inbound -Protocol TCP -LocalPort 22 `
        -Action Allow
    Write-Host "  Firewall rule added for SSH (TCP/22)."
} else {
    Write-Host "  Firewall rule already exists."
}

# 5. Create .ssh directory and authorized_keys for Administrator
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

# 6. Verify
Write-Host "=== Verification ===" -ForegroundColor Cyan
$svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
$proc = Get-Process -Name "sshd" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host "  sshd service is RUNNING" -ForegroundColor Green
} elseif ($proc) {
    Write-Host "  sshd process is RUNNING (PID: $($proc.Id))" -ForegroundColor Green
} else {
    Write-Host "  sshd is NOT running. Try rebooting the VM." -ForegroundColor Yellow
}

$port = netstat -ano | Select-String ":22 "
if ($port) {
    Write-Host "  SSH port 22 is LISTENING" -ForegroundColor Green
} else {
    Write-Host "  SSH port 22 is NOT listening" -ForegroundColor Red
}
