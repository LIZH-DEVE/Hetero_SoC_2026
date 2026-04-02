[CmdletBinding()]
param(
    [string]$VivadoBat = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    [string]$ImplRunDir = "",
    [string]$ReleaseDir = "",
    [string]$CheckpointPath = "",
    [string]$OutputDir = "",
    [switch]$SkipVivado
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "$Description not found. Candidates: $($Candidates -join ', ')"
}

function Copy-ExistingArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    foreach ($name in $Names) {
        $sourcePath = Join-Path $SourceDir $name
        if (Test-Path $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $DestinationDir $name) -Force
        }
    }
}

function Copy-OptionalDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )

    if (-not (Test-Path $SourceDir)) {
        return $false
    }

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir '*') -Destination $DestinationDir -Recurse -Force
    return $true
}

function Get-RegexValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $content = Get-Content -Path $Path -Raw
    $match = [regex]::Match($content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

function Get-LatestReportDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParentDir,
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if (-not (Test-Path $ParentDir)) {
        return $null
    }

    $directory = Get-ChildItem -Path $ParentDir -Directory |
        Where-Object { $_.Name -like "$Prefix*" } |
        Sort-Object Name |
        Select-Object -Last 1

    if ($null -eq $directory) {
        return $null
    }

    return $directory.FullName
}

function Get-PblockCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SummaryPath
    )

    if (-not (Test-Path $SummaryPath)) {
        return 0
    }

    $content = Get-Content -Path $SummaryPath -Raw
    if ($content -match 'No pblocks found\.') {
        return 0
    }

    return ([regex]::Matches($content, '^==== ', [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
}

function Write-EvidenceSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SummaryPath,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Manifest
    )

    $lines = @(
        "# Shadow Mirror Engineering Evidence Pack",
        "",
        "- Generated at: ``$($Manifest.generated_at)``",
        "- Output dir: ``$($Manifest.output_dir)``",
        "- Checkpoint: ``$($Manifest.checkpoint_path)``",
        "- BOOT.BIN SHA256: ``$($Manifest.boot_bin_sha256)``",
        "- Timing clean: ``$($Manifest.timing.TimingClean)``",
        "- Setup WNS (ns): ``$($Manifest.timing.SetupWnsNs)``",
        "- Hold WHS (ns): ``$($Manifest.timing.HoldWhsNs)``",
        "- Total on-chip power (W): ``$($Manifest.power.total_on_chip_power_w)``",
        "- Dynamic power (W): ``$($Manifest.power.dynamic_power_w)``",
        "- Static power (W): ``$($Manifest.power.device_static_power_w)``",
        "- Power confidence: ``$($Manifest.power.confidence_level)``",
        "- Methodology violations: ``$($Manifest.methodology.violations_found)``",
        "- Pblock count: ``$($Manifest.pblock.count)``",
        "",
        "## Report Roots",
        "",
        "- Raw implementation reports: ``$($Manifest.artifacts.raw_impl_reports_dir)``",
        "- Fresh reports: ``$($Manifest.artifacts.fresh_reports_dir)``",
        "- Release artifacts: ``$($Manifest.artifacts.release_artifacts_dir)``",
        "- Acceptance reports: ``$($Manifest.artifacts.acceptance_reports_dir)``",
        "",
        "## Referenced Acceptance Artifacts",
        "",
        "- Latest benchmark dir: ``$($Manifest.acceptance.latest_board_benchmark_dir)``",
        "- Latest soak dir: ``$($Manifest.acceptance.latest_board_soak_dir)``",
        "- Phase audit: ``$($Manifest.acceptance.phase_audit_md)``",
        "- Final handoff: ``$($Manifest.acceptance.final_handoff_md)``",
        "- Thesis data: ``$($Manifest.acceptance.thesis_data_md)``"
    )

    Set-Content -Path $SummaryPath -Value $lines -Encoding utf8
}

# export_ax7020_udp_gateway_shadow_mirror_evidence_pack.ps1
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$timingParser = Join-Path $workspace "read_vivado_timing_summary.ps1"
$evidenceTcl = Join-Path $workspace "export_udp_gateway_shadow_mirror_evidence_pack.tcl"

if ([string]::IsNullOrWhiteSpace($ImplRunDir)) {
    $ImplRunDir = Join-Path $workspace "HCS_SOC.runs\impl_1"
}
if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $workspace "sd_boot\ax7020_udp_gateway_shadow_mirror"
}
if ([string]::IsNullOrWhiteSpace($CheckpointPath)) {
    $CheckpointPath = Resolve-ExistingPath -Candidates @(
        (Join-Path $ImplRunDir "udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp"),
        (Join-Path $ImplRunDir "udp_gateway_shadow_mirror_wrapper_routed.dcp")
    ) -Description "Shadow mirror implementation checkpoint"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot ("doc\reports\engineering_evidence\shadow_mirror_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

if (-not (Test-Path $ImplRunDir)) {
    throw "Implementation run directory not found: $ImplRunDir"
}
if (-not (Test-Path $ReleaseDir)) {
    throw "Release directory not found: $ReleaseDir"
}
if (-not (Test-Path $timingParser)) {
    throw "Timing parser not found: $timingParser"
}
if (-not $SkipVivado) {
    if (-not (Test-Path $VivadoBat)) {
        throw "Vivado not found: $VivadoBat"
    }
    if (-not (Test-Path $evidenceTcl)) {
        throw "Engineering evidence Tcl not found: $evidenceTcl"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

$rawImplDir = Join-Path $OutputDir "raw_impl_reports"
$freshReportsDir = Join-Path $OutputDir "fresh_reports"
$releaseArtifactsDir = Join-Path $OutputDir "release_artifacts"
$acceptanceReportsDir = Join-Path $OutputDir "acceptance_reports"

$rawImplArtifacts = @(
    "runme.log",
    "udp_gateway_shadow_mirror_wrapper.bit",
    "udp_gateway_shadow_mirror_wrapper_routed.dcp",
    "udp_gateway_shadow_mirror_wrapper_postroute_physopt.dcp",
    "udp_gateway_shadow_mirror_wrapper_utilization_placed.rpt",
    "udp_gateway_shadow_mirror_wrapper_timing_summary_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_timing_summary_postroute_physopted.rpt",
    "udp_gateway_shadow_mirror_wrapper_power_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_clock_utilization_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_route_status.rpt",
    "udp_gateway_shadow_mirror_wrapper_drc_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_methodology_drc_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_io_placed.rpt",
    "udp_gateway_shadow_mirror_wrapper_control_sets_placed.rpt",
    "udp_gateway_shadow_mirror_wrapper_bus_skew_routed.rpt",
    "udp_gateway_shadow_mirror_wrapper_bus_skew_postroute_physopted.rpt"
)
$releaseArtifacts = @(
    "BOOT.BIN",
    "bootgen_read.txt",
    "readme.txt",
    "fsbl.elf",
    "udp_gateway_shadow_mirror_wrapper.bit",
    "ax7020_udp_gateway_shadow_mirror_app.elf"
)

Copy-ExistingArtifacts -SourceDir $ImplRunDir -DestinationDir $rawImplDir -Names $rawImplArtifacts
Copy-ExistingArtifacts -SourceDir $ReleaseDir -DestinationDir $releaseArtifactsDir -Names $releaseArtifacts

New-Item -ItemType Directory -Force -Path $freshReportsDir | Out-Null
if (-not $SkipVivado) {
    & $VivadoBat -mode batch -source $evidenceTcl -tclargs $CheckpointPath $freshReportsDir
    if ($LASTEXITCODE -ne 0) {
        throw "export_udp_gateway_shadow_mirror_evidence_pack.tcl failed"
    }
}

$benchmarkRoot = Join-Path $repoRoot "doc\reports\board_benchmarks"
$soakRoot = Join-Path $repoRoot "doc\reports\board_soak"
$latestBenchmarkDir = Get-LatestReportDirectory -ParentDir $benchmarkRoot -Prefix "shadow_mirror_"
$latestSoakDir = Get-LatestReportDirectory -ParentDir $soakRoot -Prefix "shadow_mirror_"

New-Item -ItemType Directory -Force -Path $acceptanceReportsDir | Out-Null
if ($latestBenchmarkDir) {
    Copy-OptionalDirectory -SourceDir $latestBenchmarkDir -DestinationDir (Join-Path $acceptanceReportsDir "board_benchmark_latest") | Out-Null
}
if ($latestSoakDir) {
    Copy-OptionalDirectory -SourceDir $latestSoakDir -DestinationDir (Join-Path $acceptanceReportsDir "board_soak_latest") | Out-Null
}

foreach ($docPath in @(
    (Join-Path $repoRoot "doc\reports\2026-04-01_project_phase_status_audit.md"),
    (Join-Path $repoRoot "doc\reports\2026-03-31_phasec_shadow_mirror_final_handoff.md"),
    (Join-Path $repoRoot "doc\reports\THESIS_DATA_TABLE.md")
)) {
    if (Test-Path $docPath) {
        Copy-Item -LiteralPath $docPath -Destination (Join-Path $acceptanceReportsDir ([System.IO.Path]::GetFileName($docPath))) -Force
    }
}

$timingReport = Resolve-ExistingPath -Candidates @(
    (Join-Path $freshReportsDir "udp_gateway_shadow_mirror_wrapper_timing_summary_postroute_physopted.rpt"),
    (Join-Path $rawImplDir "udp_gateway_shadow_mirror_wrapper_timing_summary_postroute_physopted.rpt"),
    (Join-Path $rawImplDir "udp_gateway_shadow_mirror_wrapper_timing_summary_routed.rpt")
) -Description "Timing summary report"
$powerReport = Resolve-ExistingPath -Candidates @(
    (Join-Path $freshReportsDir "udp_gateway_shadow_mirror_wrapper_power_routed.rpt"),
    (Join-Path $rawImplDir "udp_gateway_shadow_mirror_wrapper_power_routed.rpt")
) -Description "Power report"
$methodologyReport = Resolve-ExistingPath -Candidates @(
    (Join-Path $freshReportsDir "udp_gateway_shadow_mirror_wrapper_methodology_drc_routed.rpt"),
    (Join-Path $rawImplDir "udp_gateway_shadow_mirror_wrapper_methodology_drc_routed.rpt")
) -Description "Methodology report"
$pblockSummary = Resolve-ExistingPath -Candidates @(
    (Join-Path $freshReportsDir "udp_gateway_shadow_mirror_wrapper_pblock_summary.txt")
) -Description "Pblock summary report"
$bootBinPath = Resolve-ExistingPath -Candidates @(
    (Join-Path $releaseArtifactsDir "BOOT.BIN")
) -Description "BOOT.BIN"

$timing = & $timingParser -ReportPath $timingReport -Quiet
$bootHash = (Get-FileHash -Algorithm SHA256 $bootBinPath).Hash
$totalPower = Get-RegexValue -Path $powerReport -Pattern 'Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)' -Description 'Total on-chip power'
$dynamicPower = Get-RegexValue -Path $powerReport -Pattern 'Dynamic \(W\)\s*\|\s*([0-9.]+)' -Description 'Dynamic power'
$staticPower = Get-RegexValue -Path $powerReport -Pattern 'Device Static \(W\)\s*\|\s*([0-9.]+)' -Description 'Static power'
$confidenceLevel = Get-RegexValue -Path $powerReport -Pattern 'Confidence Level\s*\|\s*([A-Za-z]+)' -Description 'Power confidence'
$methodologyViolations = Get-RegexValue -Path $methodologyReport -Pattern 'Violations found:\s*([0-9]+)' -Description 'Methodology violations'
$pblockCount = Get-PblockCount -SummaryPath $pblockSummary

$manifestPath = Join-Path $OutputDir "engineering_evidence_manifest.json"
$summaryPath = Join-Path $OutputDir "engineering_evidence_summary.md"

$manifest = [pscustomobject]@{
    generated_at   = (Get-Date).ToString("s")
    output_dir     = $OutputDir
    checkpoint_path = $CheckpointPath
    skip_vivado    = [bool]$SkipVivado
    vivado_bat     = $VivadoBat
    boot_bin_sha256 = $bootHash
    timing         = $timing
    power          = [pscustomobject]@{
        total_on_chip_power_w = $totalPower
        dynamic_power_w       = $dynamicPower
        device_static_power_w = $staticPower
        confidence_level      = $confidenceLevel
        report_path           = $powerReport
    }
    methodology    = [pscustomobject]@{
        violations_found = if ($methodologyViolations) { [int]$methodologyViolations } else { $null }
        report_path      = $methodologyReport
    }
    pblock         = [pscustomobject]@{
        count        = $pblockCount
        summary_path = $pblockSummary
    }
    acceptance     = [pscustomobject]@{
        latest_board_benchmark_dir = $latestBenchmarkDir
        latest_board_soak_dir      = $latestSoakDir
        phase_audit_md             = Join-Path $repoRoot "doc\reports\2026-04-01_project_phase_status_audit.md"
        final_handoff_md           = Join-Path $repoRoot "doc\reports\2026-03-31_phasec_shadow_mirror_final_handoff.md"
        thesis_data_md             = Join-Path $repoRoot "doc\reports\THESIS_DATA_TABLE.md"
    }
    artifacts      = [pscustomobject]@{
        raw_impl_reports_dir = $rawImplDir
        fresh_reports_dir    = $freshReportsDir
        release_artifacts_dir = $releaseArtifactsDir
        acceptance_reports_dir = $acceptanceReportsDir
        manifest_json        = $manifestPath
        summary_md           = $summaryPath
    }
    copied_files    = [pscustomobject]@{
        raw_impl_reports = (Get-ChildItem -Path $rawImplDir -File | Sort-Object Name | ForEach-Object { $_.Name })
        fresh_reports    = (Get-ChildItem -Path $freshReportsDir -File | Sort-Object Name | ForEach-Object { $_.Name })
        release_artifacts = (Get-ChildItem -Path $releaseArtifactsDir -File | Sort-Object Name | ForEach-Object { $_.Name })
        acceptance_reports = (Get-ChildItem -Path $acceptanceReportsDir -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName })
    }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding utf8
Write-EvidenceSummary -SummaryPath $summaryPath -Manifest $manifest

Write-Host "Engineering evidence pack exported:"
Write-Host "  manifest = $manifestPath"
Write-Host "  summary  = $summaryPath"
Write-Host "  output   = $OutputDir"
