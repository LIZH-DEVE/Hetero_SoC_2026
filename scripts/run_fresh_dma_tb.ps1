param(
    [Parameter(Mandatory = $true)]
    [string]$TbFile,

    [Parameter(Mandatory = $true)]
    [string]$TopModule,

    [Parameter(Mandatory = $true)]
    [string]$SimName,

    [Parameter(Mandatory = $true)]
    [string]$WorkSubdir,

    [string]$BaseFileList = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseFileList)) {
    $BaseFileList = Join-Path $repoRoot ".codex_sim\ps_csr_inject_smoke_full\files.f"
}

$tbPath = if ([System.IO.Path]::IsPathRooted($TbFile)) {
    $TbFile
} else {
    Join-Path $repoRoot $TbFile
}

if (!(Test-Path $tbPath)) {
    throw "TB file not found: $tbPath"
}

if (!(Test-Path $BaseFileList)) {
    throw "Base file list not found: $BaseFileList"
}

$vivadoBin = "D:\Xilinx\Vivado\2023.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim = Join-Path $vivadoBin "xsim.bat"

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (!(Test-Path $tool)) {
        throw "Vivado tool not found: $tool"
    }
}

$workDir = Join-Path $repoRoot ".codex_sim\$WorkSubdir"
if (Test-Path $workDir) {
    Remove-Item -Recurse -Force $workDir
}
New-Item -ItemType Directory -Path $workDir | Out-Null

$baseFiles = Get-Content $BaseFileList | Select-Object -SkipLast 1
($baseFiles + $tbPath.Replace('\', '/')) | Set-Content (Join-Path $workDir "files.f")

Push-Location $workDir
try {
    & $xvlog --work work --sv -f files.f
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $xelab ("work.{0}" -f $TopModule) -s $SimName
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $xsim $SimName -runall
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
