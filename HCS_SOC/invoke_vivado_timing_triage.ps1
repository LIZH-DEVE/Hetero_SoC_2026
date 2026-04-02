[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [Parameter(Mandatory = $true)]
    [string]$DcpPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [int]$HierarchicalDepth = 8
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $VivadoBat)) {
    throw "vivado.bat not found: $VivadoBat"
}
if (-not (Test-Path $DcpPath)) {
    throw "Routed DCP not found: $DcpPath"
}

$resolvedDcp = (Resolve-Path $DcpPath).Path
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutputDir)

if (Test-Path $resolvedOutDir) {
    Remove-Item -Recurse -Force $resolvedOutDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$tclPath = Join-Path $env:TEMP ("ax7020_timing_triage_" + [Guid]::NewGuid().ToString("N") + ".tcl")

try {
    $normalizedDcp = $resolvedDcp -replace '\\','/'
    $normalizedOutDir = $resolvedOutDir -replace '\\','/'
    @'
set dcp_path [file normalize {__DCP_PATH__}]
set out_dir [file normalize {__OUT_DIR__}]
file mkdir $out_dir
open_checkpoint $dcp_path
report_timing_summary -file [file join $out_dir timing_summary.rpt]
report_timing -max_paths 10 -sort_by group -input_pins -routable_nets -file [file join $out_dir top_10_failing.rpt]
report_design_analysis -timing -logic_level_distribution -file [file join $out_dir design_analysis.rpt]
report_high_fanout_nets -timing -load_types -max_nets 50 -file [file join $out_dir high_fanout.rpt]
report_clock_interaction -file [file join $out_dir clock_interaction.rpt]
report_utilization -file [file join $out_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth __HIER_DEPTH__ -file [file join $out_dir utilization_hier.rpt]
close_design
exit
'@.Replace('__DCP_PATH__', $normalizedDcp).Replace('__OUT_DIR__', $normalizedOutDir).Replace('__HIER_DEPTH__', $HierarchicalDepth.ToString()) | Set-Content -Path $tclPath -Encoding ASCII

    & $VivadoBat -mode batch -source $tclPath
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado timing triage failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -Force $tclPath -ErrorAction SilentlyContinue
}

Write-Host "Generated timing triage reports:"
Write-Host $resolvedOutDir
Write-Host "  timing_summary.rpt"
Write-Host "  top_10_failing.rpt"
Write-Host "  design_analysis.rpt"
Write-Host "  high_fanout.rpt"
Write-Host "  clock_interaction.rpt"
Write-Host "  utilization.rpt"
Write-Host "  utilization_hier.rpt"
