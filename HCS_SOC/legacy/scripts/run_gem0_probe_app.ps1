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
$programTcl = Join-Path $workspace "download_gem0_probe_app.tcl"
$statusTcl = Join-Path $workspace "xsdb_check_status.tcl"
$transientFailurePatterns = @(
    "AHB AP transaction error",
    "APB AP transaction error",
    "Context does not support memory read",
    "no targets found",
    "Socket bind error",
    "^FAIL:",
    "transient failure"
)

function Test-TransientXsdbFailure {
    param([string]$Text)

    foreach ($pattern in $transientFailurePatterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Invoke-XsdbScriptOnce {
    param(
        [string]$XsdbExe,
        [string]$ScriptPath,
        [string]$StepName,
        [int]$Attempt
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
        Write-Host ("[{0} attempt {1}]" -f $StepName, $Attempt)
        Write-Host $text.TrimEnd()
    }

    if ($proc.ExitCode -ne 0) {
        throw "xsdb $StepName step failed with exit code $($proc.ExitCode) on attempt $Attempt"
    }

    if (Test-TransientXsdbFailure -Text $text) {
        throw "xsdb $StepName step reported transient failure on attempt $Attempt"
    }
}

function Invoke-XsdbScriptWithRetry {
    param(
        [string]$XsdbExe,
        [string]$ScriptPath,
        [string]$StepName
    )

    try {
        Invoke-XsdbScriptOnce -XsdbExe $XsdbExe -ScriptPath $ScriptPath -StepName $StepName -Attempt 1
        return
    } catch {
        $firstError = $_
        if (-not (Test-TransientXsdbFailure -Text $firstError.ToString())) {
            throw
        }

        Write-Warning ("retrying once after transient xsdb/jtag failure ({0}, attempt 1)" -f $StepName)
        Start-Sleep -Seconds 2
    }

    try {
        Invoke-XsdbScriptOnce -XsdbExe $XsdbExe -ScriptPath $ScriptPath -StepName $StepName -Attempt 2
    } catch {
        throw "xsdb $StepName failed after 2 attempts. Last error: $($_.Exception.Message)"
    }
}

switch ($Action) {
    "program" {
        Invoke-XsdbScriptWithRetry -XsdbExe $xsdb -ScriptPath $programTcl -StepName "program"
    }
    "status" {
        Invoke-XsdbScriptWithRetry -XsdbExe $xsdb -ScriptPath $statusTcl -StepName "status"
    }
    "program_and_status" {
        Invoke-XsdbScriptWithRetry -XsdbExe $xsdb -ScriptPath $programTcl -StepName "program"
        Invoke-XsdbScriptWithRetry -XsdbExe $xsdb -ScriptPath $statusTcl -StepName "status"
    }
}
