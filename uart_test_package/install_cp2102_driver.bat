@echo off
echo ========================================
echo   CP2102 UART 驱动安装脚本
echo ========================================
echo.

echo [1] 添加驱动到系统...
pnputil /add-driver "D:\FPGAhanjia\Hetero_SoC_2026_3\CP210x_Universal_Windows_Driver\silabser.inf" /install

echo.
echo [2] 扫描硬件变化...
pnputil /scan-devices

echo.
echo [3] 等待设备识别...
timeout /t 5 /nobreak

echo.
echo [4] 检查设备状态...
powershell -Command "Get-PnpDevice | Where-Object { $_.FriendlyName -like '*CP210*' } | Format-Table Status, FriendlyName -AutoSize"

echo.
echo ========================================
echo   安装完成！
echo ========================================
echo.
echo 如果设备状态还是 Unknown，请：
echo 1. 打开设备管理器
echo 2. 右键 CP210x 设备
echo 3. 选择"更新驱动程序"
echo 4. 选择"浏览计算机以查找驱动程序"
echo 5. 选择: D:\FPGAhanjia\Hetero_SoC_2026_3\CP210x_Universal_Windows_Driver
echo.
pause
