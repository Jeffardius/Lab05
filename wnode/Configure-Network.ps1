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
$DnsServer = "127.0.0.1"

Write-Host "=== Network Configuration for node1 ===" -ForegroundColor Cyan

# Rename computer and set DNS suffix
try {
    Rename-Computer -NewName "node1" -Force -ErrorAction Stop
} catch {
    Write-Host "  (hostname already 'node1' or rename deferred)" -ForegroundColor Yellow
}

# Identify adapters: filter by 192.168.X.x IP to find external and internal
# The NAT adapter (10.x.x.x) is excluded
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
Write-Host "Detected adapters:" ($adapters.Name -join ", ")

$extAdapter = $null
$intAdapter = $null

foreach ($ad in $adapters) {
    $ip = Get-NetIPAddress -InterfaceAlias $ad.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ip) {
        if ($ip.IPAddress -eq $ExtIP) { $extAdapter = $ad }
        elseif ($ip.IPAddress -eq $IntIP) { $intAdapter = $ad }
    }
}

# Fallback: if not found by IP, use name-based heuristics
if (-not $extAdapter -or -not $intAdapter) {
    Write-Host "  (identifying by order: first non-NAT = external, second = internal)" -ForegroundColor Yellow
    $nonNat = $adapters | Where-Object { 
        $ip = Get-NetIPAddress -InterfaceAlias $_.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        -not $ip -or $ip.IPAddress -notlike "10.*"
    }
    if ($nonNat.Count -ge 2) {
        $extAdapter = $nonNat[0]
        $intAdapter = $nonNat[1]
    } else {
        $extAdapter = $adapters[0]
        $intAdapter = $adapters[1]
    }
}

Write-Host "External adapter: $($extAdapter.Name) -> $ExtIP/$ExtMask"
Write-Host "Internal adapter: $($intAdapter.Name) -> $IntIP/$IntMask"

# Configure external NIC
$existingExt = Get-NetIPAddress -InterfaceAlias $extAdapter.Name -IPAddress $ExtIP -ErrorAction SilentlyContinue
if (-not $existingExt) {
    New-NetIPAddress -InterfaceAlias $extAdapter.Name -IPAddress $ExtIP -PrefixLength $ExtMask -DefaultGateway $ExtGW | Out-Null
} else {
    Write-Host "  (IP $ExtIP already on $($extAdapter.Name), skipping)" -ForegroundColor Yellow
}
Set-DnsClientServerAddress -InterfaceAlias $extAdapter.Name `
    -ServerAddresses $DnsServer
Set-DnsClient -InterfaceAlias $extAdapter.Name `
    -ConnectionSpecificSuffix $Domain -RegisterThisConnectionsAddress:$true

# Configure internal NIC
$existingInt = Get-NetIPAddress -InterfaceAlias $intAdapter.Name -IPAddress $IntIP -ErrorAction SilentlyContinue
if (-not $existingInt) {
    New-NetIPAddress -InterfaceAlias $intAdapter.Name -IPAddress $IntIP -PrefixLength $IntMask | Out-Null
} else {
    Write-Host "  (IP $IntIP already on $($intAdapter.Name), skipping)" -ForegroundColor Yellow
}
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
