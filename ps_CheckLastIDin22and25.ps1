# ==============================================================================
# 腳本名稱: Compare-IDs-Continuous.ps1
# 描述: 跨兩個 SQL Server 實例週期性執行查詢，比較 LAST_ID 並計算批次數量。
# 執行頻率: 每 5 分鐘一次 (不依賴 Windows 工作排程器)。
# ==============================================================================

# --- 1. 腳本級別參數設定 (只需要設定一次) ---

# 設定執行頻率為 5 分鐘 (5 * 60 = 300 秒)
$SleepSeconds = 300 

# 請替換成您的資料庫名稱
$DatabaseName = "YourDatabaseName"

# ⚠️ 必須確保清單中只有兩個要比較的伺服器實例
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# 請替換成您的實際查詢。
# 查詢必須返回一個單一的數值欄位，並將結果欄位命名為 LAST_ID
$Query = @"
SELECT 
    MAX(YourIDColumnName) AS LAST_ID
FROM 
    YourSchemaName.YourTableName;
"@

# 批次大小設定
$BatchSize = 5000


# --- 2. 啟動前環境檢查 ---

# 檢查 SQL Server PowerShell 模組 (SqlServer)
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "【警告】SQL Server PowerShell 模組 (SqlServer) 未安裝。請先執行：Install-Module -Name SqlServer"
}

# 檢查伺服器數量是否為 2
if ($ServerList.Count -ne 2) {
    Write-Error "【錯誤】伺服器清單 (\$ServerList) 必須包含且只能包含兩個伺服器實例才能進行比較。"
    # 終止腳本
    exit
}


# ==============================================================================
#                 主運行迴圈 (每 5 分鐘執行一次)
# ==============================================================================
while ($true) {
    
    # 紀錄本次執行的開始時間
    $StartTime = Get-Date

    Write-Host "`n=======================================================" -ForegroundColor White
    Write-Host "🟢 週期性執行開始: $($StartTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    
    # --- 3. 執行查詢並收集結果 ---
    
    # 每次迴圈開始時，重新初始化陣列，防止資料累積
    $AllResults = @() 

    foreach ($Server in $ServerList) {
        Write-Host "-> 正在連線到 $Server..." -ForegroundColor Yellow
        
        try {
            $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $Query -ErrorAction Stop
            
            # 提取並轉換為整數，確保數值有效
            $LastID = if ($Result.LAST_ID -is [DBNull] -or $Result.LAST_ID -eq $null) { 0 } else { [int]$Result.LAST_ID }
            
            # 將結果物件添加到 $AllResults 陣列中
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server
                LAST_ID = $LastID
                Status = "Success"
            }
            Write-Host " - 取得 ID：$LastID" -ForegroundColor Green

        } catch {
            Write-Error "在伺服器 $Server 上執行查詢失敗: $($_.Exception.Message)"
            # 將失敗的結果加入，ID 設為 0
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server
                LAST_ID = 0 
                Status = "Failed"
            }
        }
    }


    # --- 4. 計算並顯示差值與批次數量 ---

    if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
        Write-Warning "【警告】由於至少一個伺服器連線/查詢失敗，無法準確比較。"
    } else {
        
        # 提取資訊
        $Server1Name = $AllResults[0].ServerInstance
        $ID1 = $AllResults[0].LAST_ID

        $Server2Name = $AllResults[1].ServerInstance
        $ID2 = $AllResults[1].LAST_ID

        # 計算絕對差值
        $Difference = [math]::Abs($ID1 - $ID2)

        # 計算所需批次數量 (使用無條件進位)
        $BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)

        # --- 輸出最終結果 ---
        Write-Host "`n--- 比較結果報告 ---" -ForegroundColor DarkCyan
        Write-Host "伺服器 1 ($Server1Name) LAST_ID: $($ID1)" -ForegroundColor White
        Write-Host "伺服器 2 ($Server2Name) LAST_ID: $($ID2)" -ForegroundColor White
        Write-Host "-------------------------------------------------------" -ForegroundColor DarkCyan

        # 格式化輸出差值
        Write-Host ("兩者之間的絕對差值 (Difference): {0:N0}" -f $Difference) -ForegroundColor Red
        Write-Host "批次大小 (Batch Size): $($BatchSize) 行" -ForegroundColor White
        Write-Host "需要的批次數量 (Batches Required): $($BatchCount) 次" -ForegroundColor Magenta
    }

    # --- 5. 暫停與下次執行提示 ---

    $EndTime = Get-Date
    Write-Host "🔴 週期性執行結束: $($EndTime)" -ForegroundColor White
    Write-Host "下次執行將在 $($SleepSeconds) 秒後開始..." -ForegroundColor Yellow

    # 暫停指定的秒數
    Start-Sleep -Seconds $SleepSeconds
}
# ==============================================================================
