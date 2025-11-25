# ==============================================================================
# 腳本名稱: Compare-LastID.ps1
# 描述: 跨兩個 SQL Server 實例執行查詢，取得 LAST_ID，並計算兩者差值。
# 依賴項: 需安裝 SqlServer PowerShell 模組 (Invoke-Sqlcmd)。
# ==============================================================================

# --- 1. 參數設定 (請修改這裡) ---

# 請替換成您的資料庫名稱
$DatabaseName = "YourDatabaseName"

# ⚠️ 必須確保清單中只有兩個要比較的伺服器實例
# 格式範例：("SERVERNAME\INSTANCE1", "SERVERNAME2")
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# 請替換成您的實際查詢。
# 查詢必須返回一個單一的數值欄位，並將結果欄位命名為 LAST_ID
$Query = @"
SELECT 
    MAX(YourIDColumnName) AS LAST_ID
FROM 
    YourSchemaName.YourTableName;
"@


# --- 2. 環境檢查與初始化 ---

# 檢查 SQL Server PowerShell 模組 (SqlServer)
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "【警告】SQL Server PowerShell 模組 (SqlServer) 未安裝。請先執行：Install-Module -Name SqlServer"
}

# 檢查伺服器數量是否為 2
if ($ServerList.Count -ne 2) {
    Write-Error "【錯誤】伺服器清單 (\$ServerList) 必須包含且只能包含兩個伺服器實例才能進行比較。"
    exit
}

# 初始化陣列來收集所有伺服器的結果
$AllResults = @() 


# --- 3. 執行查詢並收集結果 (資料收集) ---

Write-Host "`n--- 開始執行跨伺服器查詢 ---" -ForegroundColor DarkCyan

foreach ($Server in $ServerList) {
    Write-Host "-> 正在連線到 $Server..." -ForegroundColor Yellow
    
    try {
        # 執行查詢，並設定 -ErrorAction Stop 以便 Try/Catch 捕獲錯誤
        $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $Query -ErrorAction Stop
        
        # 提取並轉換為整數 (int)，如果提取失敗則視為 0
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

# --- 4. 計算並顯示差值 (數據分析) ---

Write-Host "`n--- 數據分析與比較 ---" -ForegroundColor DarkCyan

# 檢查是否有任何失敗的結果
if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
    Write-Warning "【警告】由於至少一個伺服器連線/查詢失敗，比較結果可能不準確。"
}

# 提取兩個伺服器的資訊
$Server1Name = $AllResults[0].ServerInstance
$ID1 = $AllResults[0].LAST_ID

$Server2Name = $AllResults[1].ServerInstance
$ID2 = $AllResults[1].LAST_ID

# 計算兩者之間的絕對差值
$Difference = [math]::Abs($ID1 - $ID2)

# 🌟 新增步驟：計算所需批次數量 🌟
$BatchSize = 5000
$BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)


# --- 輸出最終結果 ---
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "🎯 ID 比較報告" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "伺服器 1 ($Server1Name) LAST_ID: $($ID1)" -ForegroundColor White
Write-Host "伺服器 2 ($Server2Name) LAST_ID: $($ID2)" -ForegroundColor White
Write-Host "-------------------------------------------------------" -ForegroundColor DarkCyan

# 格式化輸出差值
Write-Host ("兩者之間的絕對差值 (Difference): {0:N0}" -f $Difference) -ForegroundColor Red

# 輸出批次計算結果
Write-Host "批次大小 (Batch Size): $($BatchSize) 行" -ForegroundColor White
Write-Host "需要的批次數量 (Batches Required): $($BatchCount) 次 (使用無條件進位)" -ForegroundColor Magenta

Write-Host "=======================================================" -ForegroundColor Cyan

# 輸出詳細的結果物件 (供管線或其他腳本調用)
# 您可能也想將 BatchCount 加入輸出物件中
[PSCustomObject]@{
    Server1 = $Server1Name
    ID1 = $ID1
    Server2 = $Server2Name
    ID2 = $ID2
    Difference = $Difference
    BatchCount = $BatchCount
}
