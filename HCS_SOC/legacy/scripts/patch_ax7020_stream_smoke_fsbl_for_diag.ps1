[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,
    [string]$PlatformName = "ax7020_dma_stream_smoke_platform",
    [ValidateSet("trace", "nopostcfg", "handofflite", "handoffdelay")]
    [string]$Variant,
    [string]$VitisRoot = "D:\Xilinx\Vitis\2024.1"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FsblRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $WorkspaceRoot "$PlatformName\zynq_fsbl"),
        (Join-Path $WorkspaceRoot "zynq_fsbl")
    )

    foreach ($candidate in $candidates) {
        if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "main.c"))) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Dedicated stream-smoke zynq_fsbl root not found under $WorkspaceRoot"
}

function Resolve-FsblBspXparameters {
    param([string]$FsblRoot)

    $candidate = Join-Path $FsblRoot "zynq_fsbl_bsp\ps7_cortexa9_0\include\xparameters.h"
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    throw "Dedicated stream-smoke FSBL BSP xparameters.h not found under $FsblRoot"
}

function Replace-Once {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Evaluator,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $match = [regex]::Match($InputText, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        throw "Unable to locate patch anchor for $Label"
    }

    $replacement = & $Evaluator $match
    return $InputText.Substring(0, $match.Index) + $replacement + $InputText.Substring($match.Index + $match.Length)
}

function Get-FunctionRange {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [string]$SignaturePattern,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $signatureMatch = [regex]::Match(
        $InputText,
        $SignaturePattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $signatureMatch.Success) {
        throw "Unable to locate function signature for $Label"
    }

    $openBraceIndex = $InputText.IndexOf('{', $signatureMatch.Index + $signatureMatch.Length)
    if ($openBraceIndex -lt 0) {
        throw "Unable to locate opening brace for $Label"
    }

    $braceDepth = 0
    for ($i = $openBraceIndex; $i -lt $InputText.Length; $i++) {
        $ch = $InputText[$i]
        if ($ch -eq '{') {
            $braceDepth++
        } elseif ($ch -eq '}') {
            $braceDepth--
            if ($braceDepth -eq 0) {
                return @{
                    StartIndex = $signatureMatch.Index
                    Length = ($i - $signatureMatch.Index + 1)
                }
            }
        }
    }

    throw "Unable to locate closing brace for $Label"
}

function Replace-Once-InRange {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText,
        [Parameter(Mandatory = $true)]
        [int]$StartIndex,
        [Parameter(Mandatory = $true)]
        [int]$Length,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Evaluator,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ($StartIndex -lt 0 -or $Length -le 0 -or ($StartIndex + $Length) -gt $InputText.Length) {
        throw "Invalid replacement range for $Label"
    }

    $prefix = $InputText.Substring(0, $StartIndex)
    $target = $InputText.Substring($StartIndex, $Length)
    $suffix = $InputText.Substring($StartIndex + $Length)
    $replacedTarget = Replace-Once -InputText $target -Pattern $Pattern -Evaluator $Evaluator -Label $Label
    return $prefix + $replacedTarget + $suffix
}

function Invoke-FsblMake {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FsblRoot,
        [Parameter(Mandatory = $true)]
        [string]$VitisRoot
    )

    $makeExe = Join-Path $VitisRoot "gnuwin\bin\make.exe"
    $gccBin = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin"

    foreach ($required in @($makeExe, $gccBin)) {
        if (-not (Test-Path $required)) {
            throw "Required FSBL rebuild tool not found: $required"
        }
    }

    $previousPath = $env:PATH
    try {
        $env:PATH = "$([System.IO.Path]::GetDirectoryName($makeExe));$gccBin;$previousPath"
        Push-Location $FsblRoot
        try {
            foreach ($staleArtifact in @("main.o", "main.d", "fsbl.elf")) {
                $stalePath = Join-Path $FsblRoot $staleArtifact
                if (Test-Path $stalePath) {
                    Remove-Item -Force -LiteralPath $stalePath
                }
            }

            & $makeExe
            if ($LASTEXITCODE -ne 0) {
                throw "make failed in $FsblRoot"
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $env:PATH = $previousPath
    }
}

$usesUartDiag = @("trace", "nopostcfg", "handofflite") -contains $Variant
$usesDelayDiag = $Variant -eq "handoffdelay"
$includeAfterPs7Init = @("trace", "nopostcfg") -contains $Variant
$includePcapBreadcrumbs = @("trace", "nopostcfg") -contains $Variant
$delaySpinCount = "500000U"

$fsblRoot = Resolve-FsblRoot -WorkspaceRoot $WorkspaceRoot -PlatformName $PlatformName
$mainPath = Join-Path $fsblRoot "main.c"
$xparametersPath = Resolve-FsblBspXparameters -FsblRoot $fsblRoot
$mainText = Get-Content -Raw -Encoding ASCII -Path $mainPath
$xparametersText = Get-Content -Raw -Encoding ASCII -Path $xparametersPath

foreach ($requiredMacro in @("STDOUT_BASEADDRESS", "XPAR_XUARTPS_0_BASEADDR")) {
    if ($xparametersText -notmatch [regex]::Escape($requiredMacro)) {
        throw "Dedicated stream-smoke FSBL BSP missing required UART macro '$requiredMacro': $xparametersPath"
    }
}

if ($mainText -match "FSBL_DIAG ENTER_MAIN") {
    throw "Generated FSBL main.c already contains forbidden ENTER_MAIN breadcrumb: $mainPath"
}
if ($mainText -match "FsblDiagPrintAndFlush") {
    throw "Generated FSBL main.c already appears patched for diagnostics: $mainPath"
}
if ($mainText -match "FsblDiagDelaySpin") {
    throw "Generated FSBL main.c already appears patched for delay diagnostics: $mainPath"
}

$uartHelperFunction = @"
static void FsblDiagPrintAndFlush(const char *Message)
{
#if defined(STDOUT_BASEADDRESS) && defined(XPAR_XUARTPS_0_BASEADDR)
	u32 UartReg = 0U;

	xil_printf("%s\r\n", Message);
	UartReg = Xil_In32(STDOUT_BASEADDRESS + XUARTPS_SR_OFFSET);
	while ((UartReg & XUARTPS_SR_TXEMPTY) != XUARTPS_SR_TXEMPTY) {
		UartReg = Xil_In32(STDOUT_BASEADDRESS + XUARTPS_SR_OFFSET);
	}
#else
	(void)Message;
#endif
}

"@

$delayHelperFunction = @"
static void FsblDiagDelaySpin(u32 Iterations)
{
	volatile u32 Index = 0U;

	for (Index = 0U; Index < Iterations; ++Index) {
		/* intentional handoff-window perturbation */
	}
}

"@

$helperBlock = ""
if ($usesUartDiag) {
    $helperBlock += $uartHelperFunction
}
if ($usesDelayDiag) {
    $helperBlock += $delayHelperFunction
}

if (-not [string]::IsNullOrWhiteSpace($helperBlock)) {
    $mainText = Replace-Once -InputText $mainText `
        -Pattern 'int main\(void\)\r?\n\{' `
        -Label "diagnostic helper insertion" `
        -Evaluator {
            param($match)
            return $helperBlock + $match.Value
        }
}

if ($includeAfterPs7Init) {
    $mainText = Replace-Once -InputText $mainText `
        -Pattern '(?s)\tStatus = ps7_init\(\);\r?\n\tif \(Status != FSBL_PS7_INIT_SUCCESS\) \{.*?\r?\n\t\}' `
        -Label "AFTER_PS7_INIT breadcrumb" `
        -Evaluator {
            param($match)
            return $match.Value + "`r`n`r`n`tFsblDiagPrintAndFlush(""FSBL_DIAG AFTER_PS7_INIT"");"
        }
}

if ($includePcapBreadcrumbs) {
    $mainText = Replace-Once -InputText $mainText `
        -Pattern '\tHandoffAddress = LoadBootImage\(\);' `
        -Label "LoadBootImage breadcrumbs" `
        -Evaluator {
            param($match)
            return @"
	FsblDiagPrintAndFlush("FSBL_DIAG BEFORE_PCAP_LOAD");
	HandoffAddress = LoadBootImage();
	FsblDiagPrintAndFlush("FSBL_DIAG AFTER_PCAP_LOAD");
"@
        }
}

$postConfigReplacement = switch ($Variant) {
    "trace" {
@"
#ifdef PS7_POST_CONFIG
		FsblDiagPrintAndFlush("FSBL_DIAG BEFORE_POST_CONFIG");
		ps7_post_config();
		FsblDiagPrintAndFlush("FSBL_DIAG AFTER_POST_CONFIG");
		/*
"@
    }
    "handofflite" {
@"
#ifdef PS7_POST_CONFIG
		FsblDiagPrintAndFlush("FSBL_DIAG BEFORE_POST_CONFIG");
		ps7_post_config();
		FsblDiagPrintAndFlush("FSBL_DIAG AFTER_POST_CONFIG");
		/*
"@
    }
    "nopostcfg" {
@"
#ifdef PS7_POST_CONFIG
		FsblDiagPrintAndFlush("FSBL_DIAG BEFORE_POST_CONFIG");
		FsblDiagPrintAndFlush("FSBL_DIAG AFTER_POST_CONFIG");
		/*
"@
    }
    "handoffdelay" {
@"
#ifdef PS7_POST_CONFIG
		ps7_post_config();
		FsblDiagDelaySpin($delaySpinCount);
		/*
"@
    }
}

$fsblHandoffRange = Get-FunctionRange -InputText $mainText -SignaturePattern 'void FsblHandoff\(u32 FsblStartAddr\)' -Label "FsblHandoff()"

$mainText = Replace-Once-InRange -InputText $mainText `
    -StartIndex $fsblHandoffRange.StartIndex `
    -Length $fsblHandoffRange.Length `
    -Pattern '#ifdef PS7_POST_CONFIG\r?\n\t\tps7_post_config\(\);\r?\n\t\t/\*' `
    -Label "post-config diagnostic handling" `
    -Evaluator {
        param($match)
        return $postConfigReplacement
    }

$fsblHandoffRange = Get-FunctionRange -InputText $mainText -SignaturePattern 'void FsblHandoff\(u32 FsblStartAddr\)' -Label "FsblHandoff() after post-config patch"

if ($usesUartDiag) {
    $mainText = Replace-Once-InRange -InputText $mainText `
        -StartIndex $fsblHandoffRange.StartIndex `
        -Length $fsblHandoffRange.Length `
        -Pattern '\tStatus = FsblHookBeforeHandoff\(\);' `
        -Label "BEFORE_HANDOFF breadcrumb" `
        -Evaluator {
            param($match)
            return @"
	FsblDiagPrintAndFlush("FSBL_DIAG BEFORE_HANDOFF");
	Status = FsblHookBeforeHandoff();
"@
        }
} elseif ($usesDelayDiag) {
    $mainText = Replace-Once-InRange -InputText $mainText `
        -StartIndex $fsblHandoffRange.StartIndex `
        -Length $fsblHandoffRange.Length `
        -Pattern '\tStatus = FsblHookBeforeHandoff\(\);' `
        -Label "handoff delay insertion" `
        -Evaluator {
            param($match)
            return @"
	FsblDiagDelaySpin($delaySpinCount);
	Status = FsblHookBeforeHandoff();
"@
        }
}

Set-Content -Path $mainPath -Value $mainText -Encoding ASCII

Invoke-FsblMake -FsblRoot $fsblRoot -VitisRoot $VitisRoot

$fsblElf = Join-Path $fsblRoot "fsbl.elf"
if (-not (Test-Path $fsblElf)) {
    throw "Patched FSBL rebuild did not produce fsbl.elf: $fsblElf"
}

$patchedMain = Get-Content -Raw -Encoding ASCII -Path $mainPath
if ($includeAfterPs7Init -and $patchedMain -notmatch "FSBL_DIAG AFTER_PS7_INIT") {
    throw "Patched FSBL main.c does not contain AFTER_PS7_INIT breadcrumb"
}
if ($patchedMain -match "FSBL_DIAG ENTER_MAIN") {
    throw "Patched FSBL main.c still contains forbidden ENTER_MAIN breadcrumb"
}
if ($Variant -eq "handofflite") {
    foreach ($forbidden in @("FSBL_DIAG AFTER_PS7_INIT", "FSBL_DIAG BEFORE_PCAP_LOAD", "FSBL_DIAG AFTER_PCAP_LOAD")) {
        if ($patchedMain -match [regex]::Escape($forbidden)) {
            throw "handofflite variant must not include breadcrumb '$forbidden'"
        }
    }
}
if ($Variant -eq "handoffdelay") {
    if ($patchedMain -match "FSBL_DIAG ") {
        throw "handoffdelay variant must not include UART diagnostic breadcrumbs"
    }
    if ($patchedMain -notmatch "FsblDiagDelaySpin\($([regex]::Escape($delaySpinCount))\);") {
        throw "handoffdelay variant does not include required handoff delay calls"
    }
}

Write-Host "Patched and rebuilt dedicated stream-smoke FSBL:"
Write-Host "  Variant: $Variant"
Write-Host "  FSBL root: $fsblRoot"
Write-Host "  main.c: $mainPath"
Write-Host "  fsbl.elf: $fsblElf"
