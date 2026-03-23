[CmdletBinding()]
param(
    [string]$VitisRoot = "D:\Xilinx\Vitis\2023.1",
    [string[]]$TestCase = @("read_only"),
    [switch]$AllCases
)

$ErrorActionPreference = "Stop"

if ($AllCases) {
    $TestCase = @(
        "read_only",
        "write_ctrl",
        "write_key_1c",
        "write_key_18",
        "write_key_14",
        "write_key_10"
    )
}

function Add-Unique {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Get-TestCaseId {
    param([string]$Name)

    switch ($Name) {
        "read_only"   { return 1 }
        "write_ctrl"  { return 2 }
        "write_key_1c" { return 3 }
        "write_key_18" { return 4 }
        "write_key_14" { return 5 }
        "write_key_10" { return 6 }
        default { throw "Unsupported test case: $Name" }
    }
}

$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$appSrcDir = Join-Path $workspace "crypto_direct_write_smoke_app\src"
$buildRoot = Join-Path $workspace "crypto_direct_write_smoke_app\build"

$platformBspRoot = Join-Path $workspace "vitis_2023_udp_gateway_ws_design1\ax7020_udp_gateway_platform_design1\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0"
$workingBspLibRoot = Join-Path $workspace "platform\export\platform\sw\standalone_ps7_cortexa9_0\lib"
$platformInclude = Join-Path $platformBspRoot "include"
$generatedStandaloneRoot = Join-Path $platformBspRoot "libsrc\standalone_v8_1\src"
$embeddedswStandaloneRoot = Join-Path $VitisRoot "data\embeddedsw\lib\bsp\standalone_v8_1\src"
$standaloneCommonDir = Join-Path $embeddedswStandaloneRoot "common"
$standaloneArmCommonDir = Join-Path $embeddedswStandaloneRoot "arm\common"
$standaloneGccCommonDir = Join-Path $embeddedswStandaloneRoot "arm\common\gcc"
$standaloneArchDir = Join-Path $embeddedswStandaloneRoot "arm\cortexa9"
$toolchainLibDir = $workingBspLibRoot
$linkerScript = Join-Path $appSrcDir "lscript.ld"
$specsFile = Join-Path $VitisRoot "data\embeddedsw-sdt\scripts\specs\arm\Xilinx.spec"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$size = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-size.exe"
$sourceFile = Join-Path $appSrcDir "main.c"

foreach ($path in @(
    $appSrcDir,
    $platformBspRoot,
    $platformInclude,
    $generatedStandaloneRoot,
    $embeddedswStandaloneRoot,
    $standaloneCommonDir,
    $standaloneArmCommonDir,
    $standaloneArchDir,
    $standaloneGccCommonDir,
    $toolchainLibDir,
    $linkerScript,
    $specsFile,
    $gcc,
    $sourceFile
)) {
    if (-not (Test-Path $path)) {
        throw "Required path not found: $path"
    }
}

$includeArgs = [System.Collections.Generic.List[string]]::new()
foreach ($inc in @(
    $platformInclude,
    $generatedStandaloneRoot,
    $standaloneCommonDir,
    $standaloneArmCommonDir,
    $standaloneArchDir,
    $standaloneGccCommonDir
)) {
    Add-Unique -List $includeArgs -Value "-I$inc"
}

$commonCompileArgs = @(
    "-O2",
    "-DSDT",
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

foreach ($caseName in $TestCase) {
    $caseId = Get-TestCaseId -Name $caseName
    $caseBuildDir = Join-Path $buildRoot $caseName
    $objDir = Join-Path $caseBuildDir "obj"
    $elfPath = Join-Path $caseBuildDir "ax7020_crypto_direct_write_smoke_$caseName.elf"
    $mapPath = Join-Path $caseBuildDir "ax7020_crypto_direct_write_smoke_$caseName.map"
    $objPath = Join-Path $objDir "main.o"

    if (Test-Path $caseBuildDir) {
        Remove-Item -Recurse -Force $caseBuildDir
    }
    New-Item -ItemType Directory -Force -Path $objDir | Out-Null

    $compileArgs = @()
    $compileArgs += $includeArgs
    $compileArgs += $commonCompileArgs
    $compileArgs += @(
        "-DTEST_CASE_ID=$caseId",
        "-c",
        $sourceFile,
        "-o",
        $objPath
    )

    & $gcc @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed for test case '$caseName'."
    }

    $linkArgs = @()
    $linkArgs += $commonCompileArgs
    $linkArgs += $objPath
    $linkArgs += @(
        "-Wl,-T,$linkerScript",
        "-Wl,-Map,$mapPath",
        "-Wl,--gc-sections",
        "-L$toolchainLibDir",
        "-Wl,--start-group",
        "-lxilstandalone",
        "-lxiltimer",
        "-lxil",
        "-lc",
        "-lgcc",
        "-lm",
        "-Wl,--end-group",
        "-o",
        $elfPath
    )

    & $gcc @linkArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Link failed for test case '$caseName'."
    }

    if (Test-Path $size) {
        & $size $elfPath
    }

    Write-Host "Built crypto direct write smoke ELF for test case '$caseName':"
    Write-Host $elfPath
}
