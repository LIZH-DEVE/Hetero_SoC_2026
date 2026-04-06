[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,
    [string]$PlatformName = "ax7020_dma_stream_smoke_platform",
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$delaySpinCount = "500000U"

function Resolve-FsblProjectDir {
    param(
        [string]$WorkspaceRoot,
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "main.c")) {
            return (Resolve-Path $candidate).Path
        }
    }

    $fallback = Get-ChildItem -Path $WorkspaceRoot -Recurse -Directory -Filter zynq_fsbl -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "main.c") } |
        Select-Object -First 1
    if ($null -ne $fallback) {
        return $fallback.FullName
    }

    throw "Generated zynq_fsbl project not found under $WorkspaceRoot"
}

function Find-LineIndex {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Pattern,
        [int]$StartIndex = 0,
        [string]$Label = "line"
    )

    for ($i = $StartIndex; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) {
            return $i
        }
    }

    throw "Patch anchor not found for $Label"
}

function Insert-LinesAt {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [int]$Index,
        [string[]]$NewLines
    )

    for ($i = 0; $i -lt $NewLines.Length; $i++) {
        $Lines.Insert($Index + $i, $NewLines[$i])
    }
}

function Patch-MainSource {
    param([string]$MainPath)

    $text = Get-Content -Raw -Encoding UTF8 -Path $MainPath
    if ($text -like "*FSBL_DIAG *") {
        throw "Official stream-smoke FSBL main.c must not contain diagnostic breadcrumbs: $MainPath"
    }
    if ($text -like "*FsblDiagDelaySpin($delaySpinCount)*") {
        throw "Official stream-smoke FSBL main.c already appears stabilized: $MainPath"
    }

    $lineEnding = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -Encoding UTF8 -Path $MainPath)) {
        $lines.Add($line)
    }

    $helperIndex = Find-LineIndex -Lines $lines -Pattern ([regex]::Escape("/************************** Variable Definitions *****************************/")) -Label "delay helper insertion"
    Insert-LinesAt -Lines $lines -Index $helperIndex -NewLines @(
        "static void FsblDiagDelaySpin(u32 SpinCount)",
        "{",
        "	volatile u32 Index = 0U;",
        "",
        "	for (Index = 0U; Index < SpinCount; ++Index) {",
        "		/* dedicated stream-smoke FSBL stabilization spin */",
        "	}",
        "}",
        ""
    )

    $handoffStartIndex = Find-LineIndex -Lines $lines -Pattern "^\s*void\s+FsblHandoff\s*\(\s*u32\s+FsblStartAddr\s*\)\s*$" -Label "FsblHandoff() anchor"
    $handoffPostConfigIndex = Find-LineIndex -Lines $lines -Pattern "^\s*ps7_post_config\(\);\s*$" -StartIndex ($handoffStartIndex + 1) -Label "FsblHandoff ps7_post_config() anchor"
    Insert-LinesAt -Lines $lines -Index ($handoffPostConfigIndex + 1) -NewLines @(
        "		FsblDiagDelaySpin($delaySpinCount);"
    )

    $beforeHandoffIndex = Find-LineIndex -Lines $lines -Pattern "^\s*Status\s*=\s*FsblHookBeforeHandoff\(\);\s*$" -StartIndex ($handoffStartIndex + 1) -Label "FsblHookBeforeHandoff() anchor"
    Insert-LinesAt -Lines $lines -Index $beforeHandoffIndex -NewLines @(
        "	FsblDiagDelaySpin($delaySpinCount);"
    )

    $updatedText = [string]::Join($lineEnding, $lines)
    Set-Content -Path $MainPath -Value $updatedText -Encoding UTF8
}

$fsblDir = Resolve-FsblProjectDir -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
$mainPath = Join-Path $fsblDir "main.c"
$makeExe = Join-Path $VitisRoot "gnuwin\bin\make.exe"
$toolchainBin = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin"
$fsblElf = Join-Path $fsblDir "fsbl.elf"

foreach ($requiredPath in @($mainPath, $makeExe, $toolchainBin)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required FSBL stabilization input not found: $requiredPath"
    }
}

Patch-MainSource -MainPath $mainPath

$savedPath = $env:PATH
try {
    $env:PATH = "$toolchainBin;$([System.IO.Path]::GetDirectoryName($makeExe));$savedPath"

    Push-Location $fsblDir
    try {
        & $makeExe clean
        if ($LASTEXITCODE -ne 0) {
            throw "make clean failed for $fsblDir"
        }

        & $makeExe
        if ($LASTEXITCODE -ne 0) {
            throw "make failed for $fsblDir"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:PATH = $savedPath
}

if (-not (Test-Path $fsblElf)) {
    throw "Stabilized official FSBL ELF was not rebuilt: $fsblElf"
}

Write-Host "Stabilized official stream-smoke FSBL:"
Write-Host "  workspace: $WorkspaceRoot"
Write-Host "  main.c   : $mainPath"
Write-Host "  fsbl.elf : $fsblElf"
