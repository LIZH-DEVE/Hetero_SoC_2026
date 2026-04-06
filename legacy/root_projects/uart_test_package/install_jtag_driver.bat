@echo off
echo ========================================
echo   Digilent JTAG 驱动安装脚本
echo ========================================
echo.

set VIVADO_PATH=

REM 检查常见安装路径
if exist "C:\Xilinx\Vivado\2023.1\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=C:\Xilinx\Vivado\2023.1\data\xicom\cable_drivers\nt64\digilent
)
if exist "C:\Xilinx\Vivado\2023.2\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=C:\Xilinx\Vivado\2023.2\data\xicom\cable_drivers\nt64\digilent
)
if exist "C:\Xilinx\Vivado\2024.1\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=C:\Xilinx\Vivado\2024.1\data\xicom\cable_drivers\nt64\digilent
)
if exist "D:\Xilinx\Vivado\2023.1\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=D:\Xilinx\Vivado\2023.1\data\xicom\cable_drivers\nt64\digilent
)
if exist "D:\Xilinx\Vivado\2023.2\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=D:\Xilinx\Vivado\2023.2\data\xicom\cable_drivers\nt64\digilent
)
if exist "D:\Xilinx\Vivado\2024.1\data\xicom\cable_drivers\nt64\digilent" (
    set VIVADO_PATH=D:\Xilinx\Vivado\2024.1\data\xicom\cable_drivers\nt64\digilent
)

if "%VIVADO_PATH%"=="" (
    echo 错误: 找不到 Vivado 安装路径！
    echo.
    echo 请手动安装：
    echo 1. 找到 Vivado 安装目录
    echo 2. 进入 data\xicom\cable_drivers\nt64\digilent
    echo 3. 运行 install_digilent.exe
    echo.
    pause
    exit /b 1
)

echo 找到 Vivado 路径: %VIVADO_PATH%
echo.

if exist "%VIVADO_PATH%\install_digilent.exe" (
    echo 正在运行 Digilent 驱动安装程序...
    "%VIVADO_PATH%\install_digilent.exe"
) else (
    echo 正在安装驱动...
    pnputil /add-driver "%VIVADO_PATH%\digilent.inf" /install
    pnputil /scan-devices
)

echo.
echo 检查 JTAG 设备状态...
powershell -Command "Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Serial Converter*' -or $_.FriendlyName -like '*Digilent*' } | Format-Table Status, FriendlyName -AutoSize"

echo.
pause
