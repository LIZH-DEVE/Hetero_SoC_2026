[CmdletBinding()]
param(
    [ValidateSet("verify", "publish", "rebuild")]
    [string]$Action = "verify",

    [string]$Workspace,

    [string]$VivadoPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = $PSScriptRoot
}

function Resolve-WorkspacePath {
    param([string]$PathValue)

    return (Resolve-Path $PathValue).Path
}

function Invoke-BitstreamManager {
    param(
        [string]$WorkspacePath,
        [ValidateSet("verify", "publish")]
        [string]$Command
    )

    & py -3 (Join-Path $WorkspacePath "bitstream_manager.py") $Command --workspace $WorkspacePath
    if ($LASTEXITCODE -ne 0) {
        throw "bitstream_manager.py $Command failed with exit code $LASTEXITCODE"
    }
}

function Resolve-VivadoExecutable {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath) {
        return (Resolve-Path $ConfiguredPath).Path
    }

    $command = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        "C:\Xilinx\Vivado\2025.1\bin\vivado.bat",
        "C:\Xilinx\Vivado\2024.2\bin\vivado.bat",
        "C:\Xilinx\Vivado\2024.1\bin\vivado.bat",
        "C:\Xilinx\Vivado\2023.2\bin\vivado.bat",
        "C:\Xilinx\Vivado\2023.1\bin\vivado.bat",
        "D:\Xilinx\Vivado\2025.1\bin\vivado.bat",
        "D:\Xilinx\Vivado\2024.2\bin\vivado.bat",
        "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
        "D:\Xilinx\Vivado\2023.2\bin\vivado.bat",
        "D:\Xilinx\Vivado\2023.1\bin\vivado.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Vivado was not found. Pass -VivadoPath or add vivado.bat to PATH."
}

$workspacePath = Resolve-WorkspacePath -PathValue $Workspace

switch ($Action) {
    "verify" {
        Invoke-BitstreamManager -WorkspacePath $workspacePath -Command "verify"
    }

    "publish" {
        Invoke-BitstreamManager -WorkspacePath $workspacePath -Command "publish"
        Invoke-BitstreamManager -WorkspacePath $workspacePath -Command "verify"
    }

    "rebuild" {
        $vivadoExecutable = Resolve-VivadoExecutable -ConfiguredPath $VivadoPath
        $rebuildScript = Join-Path $workspacePath "rebuild_authoritative_bitstream.tcl"

        & $vivadoExecutable -mode batch -source $rebuildScript
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado rebuild failed with exit code $LASTEXITCODE"
        }

        Invoke-BitstreamManager -WorkspacePath $workspacePath -Command "publish"
        Invoke-BitstreamManager -WorkspacePath $workspacePath -Command "verify"
    }
}
