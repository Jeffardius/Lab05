<#
.SYNOPSIS
    Configures Windows Defender Firewall on node1.
.DESCRIPTION
    Uses the Public zone profile to secure node1.
    Allows essential traffic (DNS, ICMP, RDP for management).
    Blocks all other inbound traffic by default.
#>

param(
    [int]$X = 33
)

$Domain = "${X}network.net"

Write-Host "=== Configuring Windows Defender Firewall ===" -ForegroundColor Cyan

# Ensure all profiles are active
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True

# Set Public as the active profile (lab requirement)
Set-NetFirewallProfile -Profile Public -DefaultInboundAction Block -DefaultOutboundAction Allow

# Allow DNS (TCP/UDP 53) from trusted subnets
$extSubnet = "192.168.$X.0/25"
$intSubnet = "192.168.$X.128/25"

New-NetFirewallRule -DisplayName "DNS-In-TCP" `
    -Direction Inbound -Protocol TCP -LocalPort 53 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

New-NetFirewallRule -DisplayName "DNS-In-UDP" `
    -Direction Inbound -Protocol UDP -LocalPort 53 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

New-NetFirewallRule -DisplayName "DNS-Out-TCP" `
    -Direction Outbound -Protocol TCP -LocalPort 53 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

New-NetFirewallRule -DisplayName "DNS-Out-UDP" `
    -Direction Outbound -Protocol UDP -LocalPort 53 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

# Allow ICMP (ping) from trusted subnets
New-NetFirewallRule -DisplayName "ICMP-In" `
    -Direction Inbound -Protocol ICMPv4 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

# Allow RDP for management
New-NetFirewallRule -DisplayName "RDP-In" `
    -Direction Inbound -Protocol TCP -LocalPort 3389 `
    -RemoteAddress $extSubnet, $intSubnet -Action Allow | Out-Null

# Allow zone transfer from primary DNS (node2) - needed
New-NetFirewallRule -DisplayName "ZoneTransfer-from-Primary" `
    -Direction Inbound -Protocol TCP -LocalPort 53 `
    -RemoteAddress "192.168.$X.133" -Action Allow | Out-Null

# Display results
Write-Host "=== Active Firewall Rules ===" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "DNS*" -or $_.DisplayName -like "ICMP*" -or $_.DisplayName -like "RDP*" -or $_.DisplayName -like "ZoneTransfer*" } | Format-Table DisplayName, Action, Enabled

Write-Host "=== Firewall configuration complete ===" -ForegroundColor Green
Write-Host "  Profile: Public (default-inbound: Block)"
Write-Host "  Allowed: DNS, ICMP, RDP from trusted subnets"
