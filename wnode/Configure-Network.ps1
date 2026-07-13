<#
.SYNOPSIS
    Configures networking on node1 (Windows Server 2022 - middle node)
.DESCRIPTION
    Sets static IPs on both interfaces:
      External NIC: 192.168.X.6/25  (gateway: 192.168.X.5)
      Internal NIC: 192.168.X.132/25 (gateway: none, uses node2 route via node1)
    Also sets DNS, hostname, and enables IP forwarding (routing).
#>

param(
    [int]$X = 33
)

$Domain = "${X}network.net"
$ExtIP   = "192.168.$X.6"
$ExtMask = 25
$ExtGW   = "192.168.$X.5"
$IntIP   = "192.168.$X.132"
$IntMask = 25
$DnsServer = "192.168.$X.133"

Write-Host "=== Network Configuration for node1 ===" -ForegroundColor Cyan

# Rename computer and set DNS suffix
Rename-Computer -NewName "node1" -Force
$netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
Write-Host "Detected adapters:" $netAdapter.Name

# We need to identify which adapter is external and which is internal.
# Strategy: The adapter with a default gateway is external (will get one after IP assignment).
# We'll prompt or try to set based on MAC order from the hypervisor.
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($adapters.Count -lt 2) {
    Write-Warning "Only $($adapters.Count) active adapters found. Expected 2."
}

# Set first adapter as external, second as internal by index
$extAdapter = $adapters[0]
$intAdapter = $adapters[1]

Write-Host "External adapter: $($extAdapter.Name) -> $ExtIP/$ExtMask"
Write-Host "Internal adapter: $($intAdapter.Name) -> $IntIP/$IntMask"

# Configure external NIC
New-NetIPAddress -InterfaceAlias $extAdapter.Name `
    -IPAddress $ExtIP -PrefixLength $ExtMask `
    -DefaultGateway $ExtGW | Out-Null
Set-DnsClientServerAddress -InterfaceAlias $extAdapter.Name `
    -ServerAddresses $DnsServer
Set-DnsClient -InterfaceAlias $extAdapter.Name `
    -ConnectionSpecificSuffix $Domain -RegisterThisConnectionsAddress:$true

# Configure internal NIC
New-NetIPAddress -InterfaceAlias $intAdapter.Name `
    -IPAddress $IntIP -PrefixLength $IntMask | Out-Null
Set-DnsClientServerAddress -InterfaceAlias $intAdapter.Name `
    -ServerAddresses $DnsServer
Set-DnsClient -InterfaceAlias $intAdapter.Name `
    -ConnectionSpecificSuffix $Domain -RegisterThisConnectionsAddress:$true

# Enable IP forwarding (routing)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "IPEnableRouter" -Value 1 -Type DWord

Write-Host "Enabling RRAS routing service (if available)..."
# For Windows Server, enable Routing role if not already done
try {
    Install-WindowsFeature -Name Routing -IncludeManagementTools
    Set-Service RemoteAccess -StartupType Automatic
    Start-Service RemoteAccess -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "Could not install/start Routing service: $_"
}

Write-Host "=== Network configuration complete ===" -ForegroundColor Green
Write-Host "  External: $($extAdapter.Name) = $ExtIP/$ExtMask gw:$ExtGW"
Write-Host "  Internal: $($intAdapter.Name) = $IntIP/$IntMask"
Write-Host "  DNS:      $DnsServer"
Write-Host "  Domain:   $Domain"
Write-Host "REBOOT REQUIRED for hostname change to take effect."
