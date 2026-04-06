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
$workspaceParent = Split-Path -Parent $WorkspaceRoot
$workspaceDrive = [System.IO.Path]::GetPathRoot($WorkspaceRoot)
if ([string]::IsNullOrWhiteSpace($workspaceDrive)) {
    throw "Unable to determine workspace drive for $WorkspaceRoot"
}

$shortStagingParent = Join-Path $workspaceDrive "_xsct_stage"
$stagingRoot = Join-Path $shortStagingParent ("rcplat_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
$bspRoot = Join-Path $stagingRoot "standalone_bsp"
$hsiTcl = Join-Path $env:TEMP ("ax7020_standalone_bsp_" + [Guid]::NewGuid().ToString("N") + ".tcl")

function Remove-PathTreeRobust {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathToRemove
    )

    if (-not (Test-Path $PathToRemove)) {
        return
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($PathToRemove)
    $longPath = if ($normalizedPath.StartsWith("\\?\")) { $normalizedPath } else { "\\?\$normalizedPath" }

    try {
        Remove-Item -Recurse -Force -LiteralPath $longPath -ErrorAction Stop
    }
    catch {
        & cmd.exe /c "attrib -r -s -h /s /d `"$normalizedPath\*`" 2>nul" | Out-Null
        & cmd.exe /c "rmdir /s /q `"$longPath`"" | Out-Null
    }

    if (Test-Path -LiteralPath $PathToRemove) {
        throw "Failed to remove directory cleanly: $PathToRemove"
    }
}

function Resolve-FsblElfPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchRoot,
        [Parameter(Mandatory = $true)]
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $SearchRoot "$PlatformName\zynq_fsbl\fsbl.elf"),
        (Join-Path $SearchRoot "$PlatformName\export\$PlatformName\sw\$PlatformName\boot\fsbl.elf")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Get-Item $candidate)
        }
    }

    return Get-ChildItem -Path $SearchRoot -Recurse -File -Filter fsbl.elf -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

foreach ($pathInfo in @(
    @{ Label = "xsct.bat"; Path = $XsctBat },
    @{ Label = "XSA"; Path = $XsaPath },
    @{ Label = "XSCT Tcl"; Path = $xsctTcl }
)) {
    if (-not (Test-Path $pathInfo.Path)) {
        throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
    }
}

if (Test-Path $stagingRoot) {
    Remove-PathTreeRobust -PathToRemove $stagingRoot
}
New-Item -ItemType Directory -Force -Path $shortStagingParent | Out-Null
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

try {
    & $XsctBat $xsctTcl $stagingRoot $XsaPath $PlatformName
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT platform generation failed with exit code $LASTEXITCODE"
    }

    $fsblElf = Resolve-FsblElfPath -SearchRoot $stagingRoot -PlatformName $PlatformName
    if ($null -eq $fsblElf) {
        throw "fsbl.elf not found under $stagingRoot"
    }

    if (Test-Path $bspRoot) {
        Remove-PathTreeRobust -PathToRemove $bspRoot
    }
    New-Item -ItemType Directory -Force -Path $bspRoot | Out-Null

    @"
hsi open_hw_design {$($XsaPath -replace '\\','/')}
hsi create_sw_design temp_sw -proc ps7_cortexa9_0 -os standalone
hsi generate_bsp -sw temp_sw -dir {$($bspRoot -replace '\\','/')}
puts "BSP generation done"
exit
"@ | Set-Content -Path $hsiTcl -Encoding ASCII

    & $XsctBat $hsiTcl
    if ($LASTEXITCODE -ne 0) {
        throw "Standalone BSP generation failed with exit code $LASTEXITCODE"
    }

    if (Test-Path $WorkspaceRoot) {
        Remove-PathTreeRobust -PathToRemove $WorkspaceRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($workspaceParent) -and -not (Test-Path $workspaceParent)) {
        New-Item -ItemType Directory -Force -Path $workspaceParent | Out-Null
    }
    Move-Item -Path $stagingRoot -Destination $WorkspaceRoot

    $finalFsblElf = Resolve-FsblElfPath -SearchRoot $WorkspaceRoot -PlatformName $PlatformName
    if ($null -eq $finalFsblElf) {
        throw "fsbl.elf not found under finalized workspace $WorkspaceRoot"
    }

    $fsblRoot = $finalFsblElf.DirectoryName
    $standaloneProcessorRoot = Join-Path $WorkspaceRoot "standalone_bsp\ps7_cortexa9_0"

    Write-Host "Generated standalone platform from fresh XSA."
    Write-Host "Workspace root:"
    Write-Host $WorkspaceRoot
    Write-Host "Platform name:"
    Write-Host $PlatformName
    Write-Host "FSBL ELF:"
    Write-Host $finalFsblElf.FullName
    Write-Host "FSBL BSP root:"
    Write-Host $fsblRoot
    Write-Host "Standalone BSP processor root:"
    Write-Host $standaloneProcessorRoot
}
finally {
    Remove-Item -Force $hsiTcl -ErrorAction SilentlyContinue
    if (Test-Path $stagingRoot) {
        Remove-PathTreeRobust -PathToRemove $stagingRoot
    }
}
