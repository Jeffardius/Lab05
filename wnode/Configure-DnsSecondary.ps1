<#
.SYNOPSIS
    Configures node1 (Windows Server 2022) as a secondary DNS server.
.DESCRIPTION
    Installs DNS Server role and configures secondary zones for forward
    and reverse lookups. Zone data is transferred from the primary DNS
    server (node2). Unknown queries are forwarded to gateway caching server.
#>

param(
    [int]$X = 33
)

$Domain = "${X}network.net"
$PrimaryIP = "192.168.$X.133"   # node2 (primary DNS)
$ForwarderIP = "192.168.$X.5"   # gateway (caching forwarder)

Write-Host "=== Installing DNS Server Role ===" -ForegroundColor Cyan
Install-WindowsFeature -Name DNS -IncludeManagementTools

Write-Host "=== Configuring Secondary Forward Lookup Zone ===" -ForegroundColor Cyan
Add-DnsServerSecondaryZone -Name $Domain `
    -ZoneFile "$Domain.dns" `
    -MasterServers $PrimaryIP `
    -Verbose

Write-Host "=== Configuring Secondary Reverse Lookup Zone ===" -ForegroundColor Cyan
Add-DnsServerSecondaryZone -Name "$X.168.192.in-addr.arpa" `
    -ZoneFile "$X.168.192.in-addr.arpa.dns" `
    -MasterServers $PrimaryIP `
    -Verbose

Write-Host "=== Configuring Forwarders ===" -ForegroundColor Cyan
Set-DnsServerForwarder -IPAddress $ForwarderIP -PassThru

Write-Host "=== Forcing Zone Transfer from Primary ===" -ForegroundColor Cyan
Start-Sleep -Seconds 2
Request-DnsServerZoneTransfer -ZoneName $Domain -FullTransfer -ComputerName $PrimaryIP -PassThru
Request-DnsServerZoneTransfer -ZoneName "$X.168.192.in-addr.arpa" -FullTransfer -ComputerName $PrimaryIP -PassThru

Write-Host "=== Verifying Zones ===" -ForegroundColor Cyan
Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsAutoCreated

Write-Host "=== Secondary DNS configuration complete ===" -ForegroundColor Green
Write-Host "  Secondary zones: $Domain, $X.168.192.in-addr.arpa"
Write-Host "  Primary server:  $PrimaryIP"
Write-Host "  Forwarder:       $ForwarderIP"
