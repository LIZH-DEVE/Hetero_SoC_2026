@echo off
echo ========================================
echo   完整回退包创建脚本
echo ========================================
echo.

set BACKUP_DIR=uart_test_package_complete
set SOURCE_DIR=HCS_SOC

echo [1] 创建备份目录...
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

echo [2] 复制 XSA 文件...
copy "%SOURCE_DIR%\design_1_wrapper.xsa" "%BACKUP_DIR%\" 

echo [3] 复制位流文件...
copy "%SOURCE_DIR%\HCS_SOC.runs\impl_1\design_1_wrapper.bit" "%BACKUP_DIR%\"

echo [4] 复制 PS 初始化文件...
copy "%SOURCE_DIR%\platform\hw\ps7_init.tcl" "%BACKUP_DIR%\"

echo [5] 复制测试程序源码...
copy "%SOURCE_DIR%\crypto_test_app\src\main.c" "%BACKUP_DIR%\main_uart_test.c"

echo [6] 复制已编译的 ELF 文件...
if exist "%SOURCE_DIR%\crypto_test_app\build\crypto_test_app.elf" (
    copy "%SOURCE_DIR%\crypto_test_app\build\crypto_test_app.elf" "%BACKUP_DIR%\"
) else (
    echo [WARNING] ELF file not found! Please build the project first.
)

echo [7] 复制 XSDB 脚本...
copy "uart_test_package\run_test.tcl" "%BACKUP_DIR%\"

echo [8] 复制进度文档...
copy "PROGRESS_SAVE_UART_SUCCESS.md" "%BACKUP_DIR%\"

echo.
echo ========================================
echo   备份完成！
echo ========================================
echo.
echo 备份位置: %BACKUP_DIR%
echo.
pause
