$ServerInstance = "localhost"
$Db1 = "DatabaseA"
$Db2 = "DatabaseB"
$TableName = "MyTable"
$BatchSize = 200000  # 每次處理 20 萬筆，視你的 RAM 調整
$LogFile = "C:\temp\DiffResults.txt"

# 1. 先取得 ID 的範圍 (Min 和 Max)
$RangeQuery = "SELECT MIN(ID) as MinID, MAX(ID) as MaxID FROM $TableName"
$Range = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Db1 -Query $RangeQuery -TrustServerCertificate

$CurrentMin = $Range.MinID
$MaxID = $Range.MaxID

# 清空 Log 檔
"" | Out-File $LogFile -Encoding UTF8

Write-Host "開始比對，ID 範圍: $CurrentMin 到 $MaxID" -ForegroundColor Cyan

while ($CurrentMin -le $MaxID) {
    $CurrentMax = $CurrentMin + $BatchSize
    
    Write-Host "正在處理區間: $CurrentMin - $CurrentMax ..." -NoNewline

    # 2. 針對該區間抓取 Hash，注意加上 WHERE 條件
    # 這裡改用 CHECKSUM 或 BINARY_CHECKSUM 速度會比 HASHBYTES 快很多，但碰撞機率極微小地增加
    # 如果極度要求精確，請維持 HASHBYTES
    $BatchQuery = @"
    SELECT ID, BINARY_CHECKSUM(Col1, Col2, Col3) AS RowHash
    FROM $TableName
    WHERE ID >= $CurrentMin AND ID < $CurrentMax
    ORDER BY ID
"@

    try {
        $Data1 = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Db1 -Query $BatchQuery -TrustServerCertificate -CommandTimeout 600
        $Data2 = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Db2 -Query $BatchQuery -TrustServerCertificate -CommandTimeout 600

        # 3. 比對該批次
        if ($Data1 -or $Data2) {
            $Diff = Compare-Object -ReferenceObject $Data1 -DifferenceObject $Data2 -Property ID, RowHash -PassThru
            
            if ($Diff) {
                Write-Host " [發現差異!]" -ForegroundColor Red
                # 4. 立即寫入檔案，不要存在變數裡，釋放記憶體
                $Diff | Select-Object ID, RowHash, SideIndicator | Export-Csv -Path $LogFile -Append -NoTypeInformation
            } else {
                Write-Host " [一致]" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "區間 $CurrentMin - $CurrentMax 發生錯誤: $_"
        # 錯誤處理：可以記錄下來然後 Continue 繼續跑下一批
    }

    # 5. 強制記憶體回收 (Garbage Collection)
    $Data1 = $null
    $Data2 = $null
    $Diff = $null
    [System.GC]::Collect()

    # 移動指標
    $CurrentMin = $CurrentMax
}

Write-Host "比對完成，結果已儲存於 $LogFile"
