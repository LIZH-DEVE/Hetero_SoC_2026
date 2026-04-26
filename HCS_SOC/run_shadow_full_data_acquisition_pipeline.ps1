[CmdletBinding()]
param(
    [ValidateSet("FullDataAcquisition")]
    [string]$Mode = "FullDataAcquisition",

    [ValidateSet("EngineeringDataCollected", "PaperCandidateCollected", "FullDataCollected")]
    [string]$AutoRunUntil = "EngineeringDataCollected",

    [switch]$PlanOnly,

    [switch]$DryRun,

    [switch]$AllowDiagnosticRTLFixes,

    [switch]$AllowBuild,

    [switch]$AllowJtagProgram,

    [switch]$AllowEngineeringData,

    [switch]$AllowPaperCandidate,

    [object]$AllowPaperExport = $false,

    [object]$ManualFinalExportAck = $false,

    [int]$MaxRetriesPerGate = 2
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function ConvertTo-PipelineBool {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return [bool]$Value
    }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text.StartsWith('$')) {
        $text = $text.Substring(1)
    }
    if ($text -in @("1", "true", "yes", "on")) {
        return $true
    }
    if ($text -in @("0", "false", "no", "off", "")) {
        return $false
    }
    throw "Cannot convert pipeline boolean value '$Value'. Use true/false, 1/0, yes/no, or on/off."
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $workspace
$runner = Join-Path $repoRoot "scripts\shadow_full_data_acquisition_pipeline.py"
$registry = Join-Path $workspace "shadow_pipeline\stage_registry.json"
$state = Join-Path $repoRoot "doc\reports\engineering_evidence\pipeline_state\current_state.json"
$template = Join-Path $workspace "shadow_pipeline\current_state.template.json"
$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source

$argv = @(
    $runner,
    "--mode", $Mode,
    "--auto-run-until", $AutoRunUntil,
    "--repo-root", $repoRoot,
    "--registry", $registry,
    "--state", $state,
    "--state-template", $template,
    "--max-retries-per-gate", "$MaxRetriesPerGate"
)

if ($PlanOnly) { $argv += "--plan-only" }
if ($DryRun) { $argv += "--dry-run" }
if ($AllowDiagnosticRTLFixes) { $argv += "--allow-diagnostic-rtl-fixes" }
if ($AllowBuild) { $argv += "--allow-build" }
if ($AllowJtagProgram) { $argv += "--allow-jtag-program" }
if ($AllowEngineeringData) { $argv += "--allow-engineering-data" }
if ($AllowPaperCandidate) { $argv += "--allow-paper-candidate" }
if (ConvertTo-PipelineBool $AllowPaperExport) { $argv += "--allow-paper-export" }
if (ConvertTo-PipelineBool $ManualFinalExportAck) { $argv += "--manual-final-export-ack" }

# Documentation guard: default autonomous invocation keeps final paper export locked.
# powershell ... run_shadow_full_data_acquisition_pipeline.ps1 -AllowPaperExport:$false -ManualFinalExportAck:$false
& $pythonExe @argv
exit $LASTEXITCODE
