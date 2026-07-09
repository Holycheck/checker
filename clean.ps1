Get-Disk | Where-Object { $_.Size -ge 512MB } | ForEach-Object {
    $Disk = $_
    $DiskNumber = $Disk.Number
    $SizeGB = [math]::Round($Disk.Size / 1GB, 2)
    try {
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        Initialize-Disk -Number $DiskNumber -PartitionStyle MBR -ErrorAction Stop

        $PartSizeMB = 32
        $MaxParts = 4
        $Created = 0

        for ($i = 1; $i -le $MaxParts; $i++) {
            $Partition = New-Partition -DiskNumber $DiskNumber -Size ($PartSizeMB * 1MB) -IsActive:($i -eq 1) -ErrorAction Stop
            $Partition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "pridurok" -Confirm:$false -Force | Out-Null
            $Created++
        }
    }
    catch {
        Write-Host "  ✗ Ошибка на диске $DiskNumber: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
