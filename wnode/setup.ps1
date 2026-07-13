<#
.SYNOPSIS
    Master setup script for node1 (Windows Server 2022 - Secondary DNS)
.DESCRIPTION
    Runs all node1 configuration scripts in order.
    Must be run as Administrator.
#>

param(
    [int]$X = 33
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " node1 (Windows Server 2022) Setup" -ForegroundColor Magenta
Write-Host " 192.168.$X.6/25 (ext) + 192.168.$X.132/25 (int)" -ForegroundColor Magenta
Write-Host " Domain: ${X}network.net" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# 1. Network configuration + hostname + routing
Write-Host ""
Write-Host "=== Step 1: Network Configuration ===" -ForegroundColor Yellow
& "$ScriptDir\Configure-Network.ps1" -X $X

# 2. Install and configure secondary DNS
Write-Host ""
Write-Host "=== Step 2: Secondary DNS Server ===" -ForegroundColor Yellow
& "$ScriptDir\Configure-DnsSecondary.ps1" -X $X

# 3. Configure firewall
Write-Host ""
Write-Host "=== Step 3: Windows Defender Firewall ===" -ForegroundColor Yellow
& "$ScriptDir\Configure-Firewall.ps1" -X $X

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host " node1 (Secondary DNS) setup complete!" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "Verify with:"
Write-Host "  Get-DnsServerZone"
Write-Host "  Get-DnsServerForwarder"
Write-Host "  Resolve-DnsName gateway.${X}network.net"
Write-Host "  Resolve-DnsName node2.${X}network.net"
Write-Host "  netsh advfirewall show allprofiles"
Write-Host "============================================"
Write-Host ""
Write-Host "NOTE: The computer name change requires a reboot."
Write-Host "After reboot, run: Request-DnsServerZoneTransfer to sync zones."
