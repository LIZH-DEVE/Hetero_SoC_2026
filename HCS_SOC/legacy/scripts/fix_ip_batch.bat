@echo off
echo Running Vivado in batch mode to fix IP references...

cd /d D:\FPGAhanjia\Hetero_SoC_2026\HCS_SOC

vivado -mode batch -source fix_ip_references.tcl HCS_SOC.xpr

echo.
echo Done! Check the output above for any errors.
echo You can now open Vivado GUI and try synthesis again.
pause
