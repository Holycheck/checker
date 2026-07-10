<#
.SYNOPSIS
    Downloads, sets, and locks the desktop wallpaper, then creates a scheduled task to reapply lock at each logon.
.DESCRIPTION
    - Checks for admin rights and restarts elevated if needed.
    - Downloads image from a given URL.
    - Sets wallpaper using SystemParametersInfo.
    - Locks wallpaper via registry policies.
    - Creates a scheduled task that runs at logon to restore the lock.
.NOTES
    All output is in English.
#>

#region Admin rights check & auto-elevation
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "Script is not running as administrator. Restarting with elevation..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}
#endregion

#region Parameters
$imageUrl = "https://cdn.discordapp.com/attachments/1525080738205274152/1525093430101803189/preview_320.png?ex=6a522170&is=6a50cff0&hm=cbdc09dc0fef2339dc9b68458d7182b9649aa03df9ae094036c00aa27aa829f5&"
$picturesFolder = [Environment]::GetFolderPath('MyPictures')
$wallpaperPath = Join-Path $picturesFolder "mymom_wallpaper.jpg"
$taskScriptPath = "$env:USERPROFILE\Documents\LockWallpaperTask.ps1"
#endregion

#region Helper functions
function Set-Wallpaper {
    param([string]$Path)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    # SPI_SETDESKWALLPAPER = 0x0014, SPIF_UPDATEINIFILE = 0x01, SPIF_SENDWININICHANGE = 0x02
    $result = [Wallpaper]::SystemParametersInfo(0x0014, 0, $Path, 0x01 -bor 0x02)
    if ($result -eq 0) {
        throw "Failed to set wallpaper (SystemParametersInfo returned 0)."
    }
}

function Set-RegistryLock {
    # Create registry keys if missing
    $paths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    )
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    }

    # Set lock values
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -Name "NoChangingWallPaper" -Value 1 -Type DWord
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -Value $wallpaperPath -Type String
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -Value 2 -Type DWord  # 2 = Stretch
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDispSettingsPage" -Value 1 -Type DWord
}
#endregion

#region Main execution
try {
    Write-Host "=== Desktop Wallpaper Lock Script ===" -ForegroundColor Cyan

    # 1. Check URL availability
    Write-Host "Checking image URL..." -ForegroundColor Gray
    try {
        $head = Invoke-WebRequest -Uri $imageUrl -Method Head -TimeoutSec 10
        if ($head.StatusCode -ne 200) { throw "Server returned status $($head.StatusCode)" }
        Write-Host "URL is reachable." -ForegroundColor Green
    } catch {
        throw "URL check failed: $_"
    }

    # 2. Download image
    Write-Host "Downloading image to '$wallpaperPath'..." -ForegroundColor Gray
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($imageUrl, $wallpaperPath)
    if (-not (Test-Path $wallpaperPath) -or (Get-Item $wallpaperPath).Length -eq 0) {
        throw "Downloaded file is missing or empty."
    }
    Write-Host "Download successful." -ForegroundColor Green

    # 3. Set wallpaper
    Write-Host "Setting wallpaper..." -ForegroundColor Gray
    Set-Wallpaper -Path $wallpaperPath
    Write-Host "Wallpaper set." -ForegroundColor Green

    # 4. Apply registry locks
    Write-Host "Applying registry locks..." -ForegroundColor Gray
    Set-RegistryLock
    Write-Host "Registry locks applied." -ForegroundColor Green

    # 5. Create scheduled task to reapply lock at logon
    Write-Host "Creating scheduled task 'LockMyWallpaper'..." -ForegroundColor Gray

    # Generate the task script content (all in English)
    $taskScriptContent = @"
# Reapply wallpaper lock at logon (auto-generated)
`$wallpaperPath = "$wallpaperPath"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
[Wallpaper]::SystemParametersInfo(0x0014, 0, `$wallpaperPath, 0x01 -bor 0x02)
# Restore registry locks
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -Name "NoChangingWallPaper" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -Value `$wallpaperPath -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -Value 2 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDispSettingsPage" -Value 1 -Type DWord -ErrorAction SilentlyContinue
"@
    # Write the task script file
    $taskScriptContent | Out-File -FilePath $taskScriptPath -Encoding utf8 -Force

    # Create scheduled task action and trigger
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$taskScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

    # Register (overwrite if exists)
    Register-ScheduledTask -TaskName "LockMyWallpaper" -Action $action -Trigger $trigger -Settings $settings -Description "Re-locks wallpaper at logon" -Force -RunLevel Highest | Out-Null

    Write-Host "Scheduled task created." -ForegroundColor Green

    Write-Host "`n✅ All done! Wallpaper is set, locked, and will be reapplied at each logon." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ ERROR: $_" -ForegroundColor Red
    Write-Host "Script halted." -ForegroundColor Red
    # Optional: log to file
    # $_ | Out-File "$env:USERPROFILE\Desktop\wallpaper_error.log" -Append
    exit 1
}
#endregion

<#
# ---- REMOVAL / ROLLBACK (run separately if needed) ----
Unregister-ScheduledTask -TaskName "LockMyWallpaper" -Confirm:$false
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -Name "NoChangingWallPaper" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDispSettingsPage" -ErrorAction SilentlyContinue
Remove-Item -Path $taskScriptPath -ErrorAction SilentlyContinue
#>
