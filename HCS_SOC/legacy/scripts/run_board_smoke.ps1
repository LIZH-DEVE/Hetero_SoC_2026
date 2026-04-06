[CmdletBinding()]
param(
    [ValidateSet("program", "status", "program_and_status")]
    [string]$Action = "program_and_status",

    [string]$XsdbPath
)

$ErrorActionPreference = "Stop"

function Resolve-XsdbExecutable {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath) {
        return (Resolve-Path $ConfiguredPath).Path
    }

    $candidates = @(
        "D:\Xilinx\Vitis\2024.1\bin\xsdb.bat",
        "C:\Xilinx\Vitis\2024.1\bin\xsdb.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "xsdb.bat was not found. Pass -XsdbPath explicitly."
}

$xsdb = Resolve-XsdbExecutable -ConfiguredPath $XsdbPath
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$downloadTcl = Join-Path $workspace "download_bitstream.tcl"
$statusTcl = Join-Path $workspace "xsdb_check_status.tcl"

function Invoke-XsdbScript {
    param(
        [string]$XsdbExe,
        [string]$ScriptPath,
        [string]$StepName
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $XsdbExe -ArgumentList $ScriptPath -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $text = ((Get-Content -Raw $stdoutPath) + (Get-Content -Raw $stderrPath))
    } finally {
        Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }
    if ($text) {
        Write-Host $text.TrimEnd()
    }

    if ($proc.ExitCode -ne 0) {
        throw "xsdb $StepName step failed with exit code $($proc.ExitCode)"
    }

    $failurePatterns = @(
        "AHB AP transaction error",
        "Context does not support memory read",
        "no targets found",
        "Socket bind error",
        "^FAIL:"
    )

    foreach ($pattern in $failurePatterns) {
        if ($text -match $pattern) {
            throw "xsdb $StepName step reported failure: $pattern"
        }
    }
}

switch ($Action) {
    "program" {
        Invoke-XsdbScript -XsdbExe $xsdb -ScriptPath $downloadTcl -StepName "program"
    }

    "status" {
        Invoke-XsdbScript -XsdbExe $xsdb -ScriptPath $statusTcl -StepName "status"
    }

    "program_and_status" {
        Invoke-XsdbScript -XsdbExe $xsdb -ScriptPath $downloadTcl -StepName "program"
        Invoke-XsdbScript -XsdbExe $xsdb -ScriptPath $statusTcl -StepName "status"
    }
}
