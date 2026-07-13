<#
.SYNOPSIS
    Installs and configures OpenSSH Server on node1 (Windows Server 2022).
.DESCRIPTION
    Downloads official Microsoft Win32-OpenSSH and installs it.
    Run this as Administrator, then run setup-passwordless-ssh-to-windows.sh
    from the gateway to copy the SSH key.
#>

Write-Host "=== Installing OpenSSH Server ===" -ForegroundColor Cyan

# 1. Download official Microsoft OpenSSH
$tmpDir = "$env:TEMP\OpenSSH"
$zipPath = "$tmpDir\OpenSSH.zip"
$installDir = "${env:ProgramFiles}\OpenSSH"
$sshdPath = "$installDir\sshd.exe"

if (-not (Test-Path $sshdPath)) {
    Write-Host "  Downloading Microsoft Win32-OpenSSH..."
    $repo = "PowerShell/Win32-OpenSSH"
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
    $downloadUrl = $release.assets | Where-Object { $_.name -like "*OpenSSH-Win64*" -or $_.name -like "*Win32-OpenSSH*" } | Select-Object -First 1 -ExpandProperty browser_download_url
    if (-not $downloadUrl) {
        Write-Host "  Trying alternative download URL..."
        $downloadUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64-v9.5.0.0.msi"
    }

    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "  Extracting to $installDir..."
    if ($zipPath -like "*.msi") {
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$zipPath`" /qn TARGETDIR=`"$installDir`""
    } else {
        Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\OpenSSH-Extracted" -Force
        $extracted = Get-ChildItem "$env:TEMP\OpenSSH-Extracted" -Directory | Select-Object -First 1
        if (-not $extracted) { $extracted = "$env:TEMP\OpenSSH-Extracted" }
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Copy-Item "$($extracted.FullName)\*" -Destination $installDir -Recurse -Force
    }
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $sshdPath)) {
    Write-Host "  ERROR: sshd.exe still not found. Trying DISM approach..." -ForegroundColor Red
    Add-WindowsCapability -Online -Name "OpenSSH.Server*" | Out-Null
    # Try again with system32 path
    $sshdPath = "$env:SystemRoot\System32\OpenSSH\sshd.exe"
    if (-not (Test-Path $sshdPath)) {
        Write-Host "  Install failed. Reboot and retry, or install manually." -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Found sshd.exe at: $sshdPath"

# 2. Install sshd service
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
    Write-Host "  sshd service started (automatic)."
} else {
    Write-Host "  Service install failed. Running sshd directly..."
    Start-Process -FilePath $sshdPath -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# 3. Firewall rule
$fwRule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" `
        -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
    Write-Host "  Firewall rule added."
} else {
    Write-Host "  Firewall rule already exists."
}

# 4. Create .ssh dir for Administrator
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
Write-Host "Or paste gateway's public key into: $authKeys" -ForegroundColor Yellow
Write-Host ""

# 5. Verify
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

if ($port) {
    Write-Host "  Port 22: LISTENING" -ForegroundColor Green
} else {
    Write-Host "  Port 22: NOT listening" -ForegroundColor Red
}
