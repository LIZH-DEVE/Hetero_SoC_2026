[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)

    Write-Host ""
    Write-Host ("===== {0} =====" -f $Title)
}

function Stop-XilinxJtagProcesses {
    $targets = @("hw_server.exe", "xsdb.exe")
    $results = @()

    foreach ($target in $targets) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($target)
        $existing = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)

        if ($existing.Count -eq 0) {
            $results += [PSCustomObject]@{
                Target   = $target
                ExitCode = 0
                Output   = "not running"
            }
            continue
        }

        $output = & taskkill.exe /F /IM $target /T 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $results += [PSCustomObject]@{
            Target   = $target
            ExitCode = $exitCode
            Output   = $output.TrimEnd()
        }
    }

    return $results
}

function Resolve-VivadoRoot {
    param([string]$ConfiguredRoot)

    $candidates = @()
    if ($ConfiguredRoot) {
        $candidates += $ConfiguredRoot
    }
    $candidates += @(
        "D:\Xilinx\Vivado\2024.1",
        "C:\Xilinx\Vivado\2024.1"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "bin\program_ftdi.bat"))) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Vivado 2024.1 with program_ftdi.bat was not found. Pass -VivadoRoot explicitly."
}

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

function Get-WorkspaceRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-RecoveryRoot {
    $workspace = Get-WorkspaceRoot
    $root = Join-Path (Split-Path -Parent $workspace) "ftdi_recovery"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function New-RecoverySessionDirectory {
    param(
        [string]$BasePath,
        [string]$Prefix = "ft_prog_recovery"
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        $BasePath = Get-RecoveryRoot
    }

    New-Item -ItemType Directory -Force -Path $BasePath | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dir = Join-Path $BasePath ("{0}_{1}" -f $Prefix, $stamp)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Get-FtdiUsbDevices {
    $devices = Get-PnpDevice -PresentOnly | Where-Object {
        $_.InstanceId -match '^USB\\VID_0403&PID_[0-9A-F]{4}'
    } | Sort-Object InstanceId

    return @($devices)
}

function Get-TopLevelFtdiUsbDevices {
    return @(Get-FtdiUsbDevices | Where-Object { $_.InstanceId -match '^USB\\VID_0403&PID_[0-9A-F]{4}\\' })
}

function Get-Ax7020BoardFtdiDevice {
    return @(Get-FtdiUsbDevices | Where-Object {
        $_.InstanceId -match '^USB\\VID_0403&PID_6014\\'
    })
}

function Test-SingleTopLevelFtdiDevice {
    $devices = @(Get-TopLevelFtdiUsbDevices)
    return ($devices.Count -eq 1)
}

function Get-BoardSerialFallback {
    $boardDevice = Get-Ax7020BoardFtdiDevice | Select-Object -First 1
    if (-not $boardDevice) {
        return $null
    }

    $parts = $boardDevice.InstanceId -split '\\'
    if ($parts.Count -lt 3) {
        return $null
    }

    return $parts[-1]
}

function New-LogDirectory {
    $workspace = Get-WorkspaceRoot
    $dir = Join-Path $workspace "logs\ftdi_jtag"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Get-FtProgDownloadUrl {
    return "https://ftdichip.com/wp-content/uploads/2026/02/FT_Prog_v3.12.80.6925-Installer.zip"
}

function Find-FtProgExecutable {
    $candidates = @(
        "C:\Program Files\FTDI\FT_Prog\FT_Prog.exe",
        "C:\Program Files (x86)\FTDI\FT_Prog\FT_Prog.exe",
        "D:\FPGAhanjia\Hetero_SoC_2026_3\tools\ft_prog\FT_Prog.exe",
        "D:\FPGAhanjia\Hetero_SoC_2026_3\tools\ft_prog\FT_Prog\FT_Prog.exe",
        "D:\FPGAhanjia\Hetero_SoC_2026_3\FT_Prog\FT_Prog.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Find-FtProgInstaller {
    $candidates = @(
        "D:\FPGAhanjia\Hetero_SoC_2026_3\FT_Prog_v3.12.80.6925 Installer.exe",
        "D:\FPGAhanjia\Hetero_SoC_2026_3\tools\ft_prog\FT_Prog_v3.12.80.6925 Installer.exe",
        "C:\Users\Li\Downloads\FT_Prog_v3.12.80.6925 Installer.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function New-TimestampedPath {
    param(
        [string]$Prefix,
        [string]$Extension
    )

    $dir = New-LogDirectory
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    return (Join-Path $dir ("{0}_{1}.{2}" -f $Prefix, $stamp, $Extension.TrimStart('.')))
}

function New-FtdiRuntimeDirectory {
    param([string]$VivadoRoot)

    $runtimeRoot = Join-Path $env:TEMP "ax7020_ftdi_runtime"
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

    $copyMap = @(
        @{ Source = Join-Path $VivadoRoot "lib\win64.o\libtclftd2xx.dll"; Name = "libtclftd2xx.dll" },
        @{ Source = Join-Path $VivadoRoot "lib\win64.o\FTD2XX.dll"; Name = "FTD2XX.dll" },
        @{ Source = Join-Path $VivadoRoot "lib\win64.o\tcl86t.dll"; Name = "tcl86t.dll" },
        @{ Source = Join-Path $VivadoRoot "tps\win64\msvcp140.dll"; Name = "msvcp140.dll" },
        @{ Source = Join-Path $VivadoRoot "tps\win64\msvcp140_1.dll"; Name = "msvcp140_1.dll" },
        @{ Source = Join-Path $VivadoRoot "tps\win64\msvcp140_2.dll"; Name = "msvcp140_2.dll" },
        @{ Source = Join-Path $VivadoRoot "tps\win64\vcruntime140.dll"; Name = "vcruntime140.dll" },
        @{ Source = Join-Path $VivadoRoot "tps\win64\vcruntime140_1.dll"; Name = "vcruntime140_1.dll" }
    )

    foreach ($item in $copyMap) {
        if (Test-Path $item.Source) {
            Copy-Item $item.Source -Destination (Join-Path $runtimeRoot $item.Name) -Force
        }
    }

    return $runtimeRoot
}

function Get-ProgramFtdiRuntimeStatus {
    param([string]$VivadoRoot)

    $checks = @(
        @{ Name = "libtclftd2xx.dll"; Path = Join-Path $VivadoRoot "lib\win64.o\libtclftd2xx.dll" },
        @{ Name = "FTD2XX.dll"; Path = Join-Path $VivadoRoot "lib\win64.o\FTD2XX.dll" },
        @{ Name = "tcl85t.dll"; Path = Join-Path $VivadoRoot "lib\win64.o\tcl85t.dll" },
        @{ Name = "tcl86t.dll"; Path = Join-Path $VivadoRoot "lib\win64.o\tcl86t.dll" },
        @{ Name = "vcruntime140.dll"; Path = Join-Path $VivadoRoot "tps\win64\vcruntime140.dll" },
        @{ Name = "msvcp140.dll"; Path = Join-Path $VivadoRoot "tps\win64\msvcp140.dll" }
    )

    return @($checks | ForEach-Object {
        [PSCustomObject]@{
            Name   = $_.Name
            Exists = (Test-Path $_.Path)
            Path   = $_.Path
        }
    })
}

function Get-PnpDriverSnapshot {
    param([string]$InstanceId)

    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        return $null
    }

    return Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceID -eq $InstanceId
    } | Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, InfName
}

function Export-Ax7020FtdiSnapshot {
    param(
        [string]$OutputDirectory,
        [string]$XsdbPath,
        [string]$Prefix = "snapshot"
    )

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    $presentPath = Join-Path $OutputDirectory ("{0}_present_ftdi_devices.txt" -f $Prefix)
    $boardPath = Join-Path $OutputDirectory ("{0}_board_device.txt" -f $Prefix)
    $driverPath = Join-Path $OutputDirectory ("{0}_board_driver.txt" -f $Prefix)
    $targetsPath = Join-Path $OutputDirectory ("{0}_xsdb_targets.txt" -f $Prefix)

    $devices = @(Get-FtdiUsbDevices | Select-Object Status, Class, FriendlyName, InstanceId)
    if ($devices.Count -eq 0) {
        "No present FTDI USB devices detected." | Set-Content -Path $presentPath -Encoding UTF8
    } else {
        $devices | Format-Table -Auto | Out-String | Set-Content -Path $presentPath -Encoding UTF8
    }

    $board = Get-Ax7020BoardFtdiDevice | Select-Object -First 1
    if ($board) {
        $board | Format-List Status, Class, FriendlyName, InstanceId | Out-String | Set-Content -Path $boardPath -Encoding UTF8
        $driver = Get-PnpDriverSnapshot -InstanceId $board.InstanceId
        if ($driver) {
            $driver | Format-List * | Out-String | Set-Content -Path $driverPath -Encoding UTF8
        } else {
            "No Win32_PnPSignedDriver record found for $($board.InstanceId)" | Set-Content -Path $driverPath -Encoding UTF8
        }
    } else {
        "AX7020 VID_0403&PID_6014 device not present." | Set-Content -Path $boardPath -Encoding UTF8
        "AX7020 VID_0403&PID_6014 device not present." | Set-Content -Path $driverPath -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($XsdbPath) -and (Test-Path $XsdbPath)) {
        $xsdbResult = Invoke-XsdbTargetsCheck -XsdbPath $XsdbPath -LogPath $targetsPath
        if (-not (Test-Path $targetsPath)) {
            $xsdbResult.Output | Set-Content -Path $targetsPath -Encoding UTF8
        }
    } else {
        "xsdb path not provided." | Set-Content -Path $targetsPath -Encoding UTF8
    }

    [PSCustomObject]@{
        PresentDevicesPath = $presentPath
        BoardDevicePath    = $boardPath
        BoardDriverPath    = $driverPath
        TargetsPath        = $targetsPath
    }
}

function Invoke-ProgramFtdi {
    param(
        [string]$VivadoRoot,
        [string[]]$Arguments,
        [string]$LogPath
    )

    $programFtdi = Join-Path $VivadoRoot "bin\program_ftdi.bat"
    $runtimeRoot = New-FtdiRuntimeDirectory -VivadoRoot $VivadoRoot

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $oldPath = $env:PATH
    $oldTclLibPath = $env:TCLLIBPATH
    try {
        $env:TCLLIBPATH = (($runtimeRoot, (Join-Path $VivadoRoot "lib\win64.o")) | ForEach-Object {
            $_.Replace('\', '/')
        }) -join ' '
        $env:PATH = @(
            $runtimeRoot,
            (Join-Path $VivadoRoot "bin"),
            (Join-Path $VivadoRoot "lib\win64.o"),
            (Join-Path $VivadoRoot "tps\win64"),
            (Join-Path $VivadoRoot "bin\unwrapped\win64.o\Microsoft.VC141.CRT"),
            $oldPath
        ) -join ';'

        $proc = Start-Process -FilePath $programFtdi -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $output = ((Get-Content -Raw $stdoutPath) + (Get-Content -Raw $stderrPath))
        $exitCode = $proc.ExitCode
    } finally {
        $env:PATH = $oldPath
        if ($null -eq $oldTclLibPath) {
            Remove-Item Env:TCLLIBPATH -ErrorAction SilentlyContinue
        } else {
            $env:TCLLIBPATH = $oldTclLibPath
        }
        Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }

    if ($LogPath) {
        Set-Content -Path $LogPath -Value $output -Encoding ASCII
    }

    $success = $true
    if ($exitCode -ne 0) {
        $success = $false
    }
    if ($output -match "couldn't load library ""libtclftd2xx.dll""" -or
        $output -match "(?m)^ERROR:" -or
        $output -match "(?m)^FATAL:") {
        $success = $false
    }

    [PSCustomObject]@{
        Success      = $success
        ExitCode     = $exitCode
        Output       = $output.TrimEnd()
        LogPath      = $LogPath
        RuntimeDir   = $runtimeRoot
        Arguments    = ($Arguments -join ' ')
        ProgramFtdi  = $programFtdi
    }
}

function Invoke-XsdbTargetsCheck {
    param(
        [string]$XsdbPath,
        [string]$LogPath
    )

    Stop-XilinxJtagProcesses | Out-Null
    Start-Sleep -Milliseconds 500

    $script = @'
connect
puts "===TARGETS==="
targets
exit
'@

    $output = $script | & $XsdbPath 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($LogPath) {
        Set-Content -Path $LogPath -Value $output -Encoding ASCII
    }

    $success = ($exitCode -eq 0) -and ($output -match 'DAP|APU|Cortex-A9')
    [PSCustomObject]@{
        Success  = $success
        ExitCode = $exitCode
        Output   = $output.TrimEnd()
        LogPath  = $LogPath
    }
}

function Read-KeyValueConfig {
    param([string]$Path)

    $map = [ordered]@{}
    foreach ($line in Get-Content $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) {
            continue
        }
        $map[$parts[0].Trim()] = $parts[1]
    }
    return $map
}

function Write-KeyValueConfig {
    param(
        [System.Collections.IDictionary]$Config,
        [string]$Path
    )

    $order = @(
        "Device location",
        "ftdi",
        "serial",
        "vendor",
        "board",
        "manufacturer",
        "description"
    )

    $lines = foreach ($key in $order) {
        if ($Config.ContainsKey($key)) {
            "{0}={1}" -f $key, $Config[$key]
        }
    }

    Set-Content -Path $Path -Value $lines -Encoding ASCII
}

function Get-RequiredWriteConfig {
    param([string]$BackupPath)

    $config = Read-KeyValueConfig -Path $BackupPath
    if (-not $config.ContainsKey("serial")) {
        throw "Backup file is missing serial."
    }

    $serial = [string]$config["serial"]
    if ([string]::IsNullOrWhiteSpace($serial)) {
        $serial = Get-BoardSerialFallback
    }
    if ([string]::IsNullOrWhiteSpace($serial)) {
        throw "No serial could be derived from EEPROM backup or USB instance ID."
    }

    $vendor = [string]$config["vendor"]
    if ([string]::IsNullOrWhiteSpace($vendor)) {
        $vendor = "FTDI"
    }

    [ordered]@{
        "Device location" = $config["Device location"]
        "ftdi"            = "FT232H"
        "serial"          = $serial
        "vendor"          = $vendor
        "board"           = "Xilinx USB Cable"
        "manufacturer"    = "Xilinx"
        "description"     = "Xilinx USB Cable"
    }
}
