# ================= 設定區 =================

# 定義來源資料庫 (Server A)
$Source = @{
    ServerInstance = "ServerA_IP_or_Name"
    Database       = "SourceDB"
    TableName      = "Table_Old_Name"
    # 定義要比對的欄位 (兩邊欄位內容必須一致，但名稱可以不同，這裡寫 SQL 語法)
    # 例如: BINARY_CHECKSUM(ColA, ColB, ColC)
    HashExpression = "BINARY_CHECKSUM(Col1, Col2, Col3)" 
    KeyColumn      = "ID"
}

# 定義目標資料庫 (Server B)
$Target = @{
    ServerInstance = "ServerB_IP_or_Name"
    Database       = "TargetDB"
    TableName      = "Table_New_Name"
    # 如果目標表的欄位名稱不同，請在這裡修改對應的欄位
    HashExpression = "BINARY_CHECKSUM(Col1, Col2, Col3)" 
    KeyColumn      = "ID"
}

$BatchSize = 200000      # 每批處理 20 萬筆
$LogFile   = "C:\temp\DiffResult_CrossServer.csv"
$MaxRetries = 3          # 遇到連線錯誤時重試次數

# ==========================================

# 輔助函式：執行查詢並帶有重試機制
function Get-BatchData {
    param ($Config, $MinID, $MaxID)
    
    $Query = @"
        SELECT $($Config.KeyColumn) AS ID, $($Config.HashExpression) AS RowHash
        FROM $($Config.TableName)
        WHERE $($Config.KeyColumn) >= $MinID AND $($Config.KeyColumn) < $MaxID
        ORDER BY $($Config.KeyColumn)
"@
    
    $RetryCount = 0
    while ($RetryCount -lt $MaxRetries) {
        try {
            # 如果需要帳號密碼，請在 Invoke-Sqlcmd 加上 -Username -Password
            return Invoke-Sqlcmd -ServerInstance $Config.ServerInstance -Database $Config.Database -Query $Query -TrustServerCertificate -ConnectionTimeout 60
        }
        catch {
            $RetryCount++
            Write-Warning "連線至 $($Config.ServerInstance) 失敗，正在重試 ($RetryCount/$MaxRetries)... 錯誤: $_"
            Start-Sleep -Seconds 2
        }
    }
    throw "無法連線至 $($Config.ServerInstance)，已達最大重試次數。"
}

# 初始化 Log
"ID,RowHash,Source,Type" | Out-File $LogFile -Encoding UTF8

Write-Host "=== 開始跨伺服器比對 ===" -ForegroundColor Cyan

# 1. 取得 ID 範圍 (這裡假設以 Source 端為基準，你也可以兩邊都查取最大範圍)
try {
    Write-Host "正在取得 ID 範圍..."
    $RangeQuery = "SELECT MIN($($Source.KeyColumn)) as MinID, MAX($($Source.KeyColumn)) as MaxID FROM $($Source.TableName)"
    $Range = Invoke-Sqlcmd -ServerInstance $Source.ServerInstance -Database $Source.Database -Query $RangeQuery -TrustServerCertificate
    
    $CurrentMin = $Range.MinID
    $MaxID = $Range.MaxID
    Write-Host "ID 範圍: $CurrentMin 到 $MaxID" -ForegroundColor Green
}
catch {
    Write-Error "無法取得初始範圍: $_"
    exit
}

# 2. 分批迴圈
while ($CurrentMin -le $MaxID) {
    $CurrentMax = $CurrentMin + $BatchSize
    Write-Host "正在處理區間: $CurrentMin - $CurrentMax ..." -NoNewline

    try {
        # 平行抓取兩邊資料 (循序執行，但因為分批所以不會卡太久)
        $DataSrc = Get-BatchData -Config $Source -MinID $CurrentMin -MaxID $CurrentMax
        $DataTgt = Get-BatchData -Config $Target -MinID $CurrentMin -MaxID $CurrentMax

        # 比對
        if ($DataSrc -or $DataTgt) {
            # 使用 Compare-Object
            $Diff = Compare-Object -ReferenceObject $DataSrc -DifferenceObject $DataTgt -Property ID, RowHash -PassThru

            if ($Diff) {
                Write-Host " [差異]" -ForegroundColor Red
                
                # 轉換並寫入 CSV
                foreach ($row in $Diff) {
                    $SourceStr = if ($row.SideIndicator -eq "<=") { $Source.ServerInstance } else { $Target.ServerInstance }
                    $TypeStr = if ($row.SideIndicator -eq "<=") { "SourceOnly_Or_Diff" } else { "TargetOnly_Or_Diff" }
                    "$($row.ID),$($row.RowHash),$SourceStr,$TypeStr" | Out-File $LogFile -Append -Encoding UTF8
                }
            } else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        } else {
             Write-Host " [無資料]" -ForegroundColor Gray
        }
    }
    catch {
        Write-Error "`n嚴重錯誤於區間 $CurrentMin - $CurrentMax: $_"
        # 視情況決定是否 break，這裡選擇繼續跑下一批
    }

    # 記憶體清理
    $DataSrc = $null
    $DataTgt = $null
    $Diff = $null
    [System.GC]::Collect()

    $CurrentMin = $CurrentMax
}

Write-Host "`n比對完成！詳細報告請查看: $LogFile" -ForegroundColor Cyan
