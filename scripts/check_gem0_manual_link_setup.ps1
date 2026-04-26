[CmdletBinding()]
param(
    [string]$AdapterAlias = "",
    [string]$ExpectedHostIp = "192.168.1.10",
    [string]$BoardIp = "192.168.1.20"
)

$ErrorActionPreference = "Stop"

function Resolve-AdapterName {
    param([string]$RequestedAlias)

    if ($RequestedAlias) {
        return (Get-NetAdapter -Name $RequestedAlias -ErrorAction Stop).Name
    }

    $candidate = Get-NetAdapter |
        Where-Object {
            $_.HardwareInterface -eq $true -and
            (
                $_.InterfaceDescription -like "*Ethernet*" -or
                $_.InterfaceDescription -like "*GbE*" -or
                $_.Name -like "*Ethernet*"
            )
        } |
        Sort-Object @{ Expression = { $_.Status -eq "Up" }; Descending = $true }, Name |
        Select-Object -First 1

    if (-not $candidate) {
        throw "No physical Ethernet adapter candidate was found. Pass -AdapterAlias explicitly."
    }

    return $candidate.Name
}

$resolvedAdapterAlias = Resolve-AdapterName -RequestedAlias $AdapterAlias
$adapter = Get-NetAdapter -Name $resolvedAdapterAlias -ErrorAction Stop
$ipConfig = Get-NetIPConfiguration -InterfaceAlias $resolvedAdapterAlias -ErrorAction SilentlyContinue
$arpEntry = Get-NetNeighbor -InterfaceAlias $resolvedAdapterAlias -IPAddress $BoardIp -ErrorAction SilentlyContinue

Write-Host "===== GEM0 Manual Link Setup Check ====="
Write-Host ("AdapterAlias : {0}" -f $adapter.Name)
Write-Host ("Status       : {0}" -f $adapter.Status)
Write-Host ("LinkSpeed    : {0}" -f $adapter.LinkSpeed)
Write-Host ("MacAddress   : {0}" -f $adapter.MacAddress)
Write-Host ""

Write-Host "IPv4 addresses on adapter:"
if ($ipConfig -and $ipConfig.IPv4Address) {
    foreach ($addr in $ipConfig.IPv4Address) {
        Write-Host ("  - {0}" -f $addr.IPAddress)
    }
} else {
    Write-Host "  - NONE"
}
Write-Host ""

if ($ipConfig -and $ipConfig.IPv4Address -and ($ipConfig.IPv4Address.IPAddress -contains $ExpectedHostIp)) {
    Write-Host ("PASS: expected host IP {0} is present on {1}" -f $ExpectedHostIp, $resolvedAdapterAlias)
} else {
    Write-Warning ("Expected host IP {0} is not present on {1}" -f $ExpectedHostIp, $resolvedAdapterAlias)
}

Write-Host ""
Write-Host ("Current ARP entry for {0}:" -f $BoardIp)
if ($arpEntry) {
    Write-Host ("  LinkLayerAddress : {0}" -f $arpEntry.LinkLayerAddress)
    Write-Host ("  State            : {0}" -f $arpEntry.State)
} else {
    Write-Host "  - NONE"
}

Write-Host ""
Write-Host "Recommended manual next steps:"
Write-Host "  1. arp -d *"
Write-Host ("  2. ping {0} -n 1" -f $BoardIp)
Write-Host ("  3. Verify ARP reply from 02:0A:35:00:01:20 in Wireshark on adapter {0}" -f $resolvedAdapterAlias)
