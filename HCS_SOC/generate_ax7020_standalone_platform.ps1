[CmdletBinding()]
param(
    [string]$XsctBat = "D:\Xilinx\Vitis\2024.1\bin\xsct.bat",
    [Parameter(Mandatory = $true)]
    [string]$XsaPath,
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)]
    [string]$PlatformName
)

$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$xsctTcl = Join-Path $workspace "generate_ax7020_standalone_platform_xsct.tcl"

foreach ($pathInfo in @(
    @{ Label = "xsct.bat"; Path = $XsctBat },
    @{ Label = "XSA"; Path = $XsaPath },
    @{ Label = "XSCT Tcl"; Path = $xsctTcl }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

if (Test-Path $WorkspaceRoot) {
    Remove-Item -Recurse -Force $WorkspaceRoot
}
New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null

& $XsctBat $xsctTcl $WorkspaceRoot $XsaPath $PlatformName
if ($LASTEXITCODE -ne 0) {
    throw "XSCT platform generation failed with exit code $LASTEXITCODE"
}

$fsblElf = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter fsbl.elf |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $fsblElf) {
    throw "fsbl.elf not found under $WorkspaceRoot"
}

$specFile = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter Xilinx.spec |
    Where-Object { $_.DirectoryName -match 'standalone_ps7_cortexa9_0' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $specFile) {
    $specFile = Get-ChildItem -Path $WorkspaceRoot -Recurse -File -Filter Xilinx.spec |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}
if ($null -eq $specFile) {
    throw "Xilinx.spec not found under $WorkspaceRoot"
}

$platformSwDir = $specFile.DirectoryName

Write-Host "Generated standalone platform from fresh XSA."
Write-Host "Workspace root:"
Write-Host $WorkspaceRoot
Write-Host "Platform name:"
Write-Host $PlatformName
Write-Host "FSBL ELF:"
Write-Host $fsblElf.FullName
Write-Host "Platform SW dir:"
Write-Host $platformSwDir
