[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [Parameter(Mandatory = $true)]
    [string]$DcpPath,
    [Parameter(Mandatory = $true)]
    [string]$Pattern
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $VivadoBat)) {
    throw "vivado.bat not found: $VivadoBat"
}
if (-not (Test-Path $DcpPath)) {
    throw "Routed DCP not found: $DcpPath"
}

$resolvedDcp = (Resolve-Path $DcpPath).Path
$tclPath = Join-Path $env:TEMP ("ax7020_cell_query_" + [Guid]::NewGuid().ToString("N") + ".tcl")

try {
    $normalizedDcp = $resolvedDcp -replace '\\','/'
    @'
set dcp_path [file normalize {__DCP_PATH__}]
set pattern {__PATTERN__}
open_checkpoint $dcp_path
puts "CELL_QUERY_START"
foreach c [lsort [get_cells -hier $pattern]] {
    puts $c
}
puts "CELL_QUERY_END"
close_design
exit
'@.Replace('__DCP_PATH__', $normalizedDcp).Replace('__PATTERN__', $Pattern) | Set-Content -Path $tclPath -Encoding ASCII

    & $VivadoBat -mode batch -source $tclPath
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado cell query failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -Force $tclPath -ErrorAction SilentlyContinue
}
