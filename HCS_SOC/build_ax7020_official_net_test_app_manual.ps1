[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\\Xilinx\\Vitis\\2024.1"
)

$ErrorActionPreference = "Stop"

function Add-Unique {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Resolve-DriverSrcDir {
    param(
        [string]$BspRoot,
        [string]$DriverName,
        [string]$LegacyDirName = $null
    )

    $candidates = @()
    if ($LegacyDirName) {
        $candidates += (Join-Path $BspRoot "libsrc\\$LegacyDirName\\src")
    }
    $candidates += (Join-Path $BspRoot "libsrc\\$DriverName\\src")
    $candidates += (Join-Path $BspRoot "libsrc\\$DriverName")

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Unable to resolve source directory for driver '$DriverName' under $BspRoot"
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "ax7020_official_net_test_app\\src"
$manualBuildDir = Join-Path $workspace "ax7020_official_net_test_app\\manual_build"
$objDir = Join-Path $manualBuildDir "obj"
$elfPath = Join-Path $manualBuildDir "ax7020_official_net_test_app.elf"
$mapPath = Join-Path $manualBuildDir "ax7020_official_net_test_app.map"

$platformBspRoot = Join-Path $workspace "platform\\ps7_cortexa9_0\\standalone_ps7_cortexa9_0\\bsp"
$platformExportInclude = Join-Path $workspace "platform\\export\\platform\\sw\\standalone_ps7_cortexa9_0\\include"
$officialNetTestBspRoot = Join-Path $workspace "ax7020_official_net_test\\design_1_wrapper\\ps7_cortexa9_0\\standalone_domain\\bsp\\ps7_cortexa9_0"
$standaloneSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "standalone" -LegacyDirName "standalone_v9_1"
$standaloneArmDir = Join-Path $standaloneSrcDir "arm\\cortexa9"
$scugicSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "scugic" -LegacyDirName "scugic_v5_3"
$scutimerSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "scutimer" -LegacyDirName "scutimer_v2_6"
$emacpsSrcDir = Resolve-DriverSrcDir -BspRoot $platformBspRoot -DriverName "emacps" -LegacyDirName "emacps_v3_20"
$lwipBaseDir = Join-Path $officialNetTestBspRoot "libsrc\\lwip220_v1_0\\src\\lwip-2.2.0"
$lwipCoreIncludeDir = Join-Path $lwipBaseDir "src\\include"
$lwipCoreFlatIncludeDir = Join-Path $lwipCoreIncludeDir "lwip"
$lwipPortIncludeDir = Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\include"

$toolchainLibDir = Join-Path $platformBspRoot "lib"
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$specsFile = Join-Path $VitisRoot "data\\embeddedsw\\scripts\\specs\\arm\\Xilinx.spec"
$gcc = Join-Path $VitisRoot "gnu\\aarch32\\nt\\gcc-arm-none-eabi\\bin\\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\\aarch32\\nt\\gcc-arm-none-eabi\\bin\\arm-none-eabi-size.exe"

foreach ($path in @(
    $appSrcDir,
    $platformBspRoot,
    $platformExportInclude,
    $officialNetTestBspRoot,
    $standaloneSrcDir,
    $standaloneArmDir,
    $scugicSrcDir,
    $scutimerSrcDir,
    $emacpsSrcDir,
    $lwipCoreIncludeDir,
    $lwipPortIncludeDir,
    $toolchainLibDir,
    $linkerScript,
    $specsFile,
    $gcc
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

if (Test-Path $manualBuildDir) {
    Remove-Item -Recurse -Force $manualBuildDir
}
New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$includeArgs = [System.Collections.Generic.List[string]]::new()
foreach ($inc in @(
    $platformExportInclude,
    (Join-Path $platformBspRoot "include"),
    $standaloneSrcDir,
    $standaloneArmDir,
    $scugicSrcDir,
    $scutimerSrcDir,
    $emacpsSrcDir,
    $lwipCoreIncludeDir,
    $lwipCoreFlatIncludeDir,
    $lwipPortIncludeDir
)) {
    Add-Unique -List $includeArgs -Value "-I$inc"
}

$commonCompileArgs = @(
    "-O2",
    "-DXIL_INTERRUPT",
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-specs=$specsFile",
    "-Wall",
    "-Wextra",
    "-Os",
    "-ffunction-sections",
    "-fdata-sections",
    "-U__clang__"
)

$appSources = @(
    (Join-Path $appSrcDir "main.c"),
    (Join-Path $appSrcDir "platform_zynq.c"),
    (Join-Path $appSrcDir "udp_crypto_gateway.c")
)

$lwipSources = @(
    (Join-Path $lwipBaseDir "src\\core\\init.c"),
    (Join-Path $lwipBaseDir "src\\core\\def.c"),
    (Join-Path $lwipBaseDir "src\\core\\dns.c"),
    (Join-Path $lwipBaseDir "src\\core\\inet_chksum.c"),
    (Join-Path $lwipBaseDir "src\\core\\ip.c"),
    (Join-Path $lwipBaseDir "src\\core\\mem.c"),
    (Join-Path $lwipBaseDir "src\\core\\memp.c"),
    (Join-Path $lwipBaseDir "src\\core\\netif.c"),
    (Join-Path $lwipBaseDir "src\\core\\pbuf.c"),
    (Join-Path $lwipBaseDir "src\\core\\raw.c"),
    (Join-Path $lwipBaseDir "src\\core\\stats.c"),
    (Join-Path $lwipBaseDir "src\\core\\sys.c"),
    (Join-Path $lwipBaseDir "src\\core\\altcp.c"),
    (Join-Path $lwipBaseDir "src\\core\\altcp_alloc.c"),
    (Join-Path $lwipBaseDir "src\\core\\altcp_tcp.c"),
    (Join-Path $lwipBaseDir "src\\core\\tcp.c"),
    (Join-Path $lwipBaseDir "src\\core\\tcp_in.c"),
    (Join-Path $lwipBaseDir "src\\core\\tcp_out.c"),
    (Join-Path $lwipBaseDir "src\\core\\timeouts.c"),
    (Join-Path $lwipBaseDir "src\\core\\udp.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\autoip.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\dhcp.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\etharp.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\icmp.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\igmp.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\ip4_frag.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\ip4.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\ip4_addr.c"),
    (Join-Path $lwipBaseDir "src\\core\\ipv4\\acd.c"),
    (Join-Path $lwipBaseDir "src\\netif\\ethernet.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\sys_arch_raw.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xadapter.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xpqueue.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xtopology_g.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xemacpsif_dma.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xemacpsif_physpeed.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xemacpsif_hw.c"),
    (Join-Path $lwipBaseDir "contrib\\ports\\xilinx\\netif\\xemacpsif.c")
)

$allSources = @($appSources + $lwipSources)
$objects = [System.Collections.Generic.List[string]]::new()

foreach ($src in $allSources) {
    if (-not (Test-Path $src)) {
        throw "Source file not found: $src"
    }

    $objName = "{0}_{1}.o" -f [IO.Path]::GetFileNameWithoutExtension($src), ([Math]::Abs($src.GetHashCode()))
    $objPath = Join-Path $objDir $objName
    $compileArgs = @()
    $compileArgs += $includeArgs
    $compileArgs += $commonCompileArgs
    $compileArgs += @("-c", $src, "-o", $objPath)

    & $gcc @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed: $src"
    }

    $objects.Add($objPath) | Out-Null
}

$linkArgs = @()
$linkArgs += $commonCompileArgs
$linkArgs += $objects
$linkArgs += @(
    "-Wl,-T,$linkerScript",
    "-Wl,-Map,$mapPath",
    "-Wl,--gc-sections",
    "-L$toolchainLibDir",
    "-Wl,--start-group",
    "-lxil",
    "-lxilstandalone",
    "-lxiltimer",
    "-lc",
    "-lgcc",
    "-lm",
    "-Wl,--end-group",
    "-o",
    $elfPath
)

& $gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed."
}

if (Test-Path $size) {
    & $size $elfPath
}

Write-Host "Built manual Stage A app:"
Write-Host $elfPath
