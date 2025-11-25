# 請替換成您要執行的實際 SQL 查詢
# 範例：查詢某張表的總行數
$Query = @"
SELECT 
    'ServerTime' = GETDATE(),
    COUNT(*) AS TotalRecords
FROM 
    YourSchemaName.YourTableName 
WHERE 
    YourColumn = 'SomeValue';
"@

# 請替換成您的資料庫名稱
$DatabaseName = "YourDatabaseName"

# 請替換成您的 SQL 伺服器實例名稱清單
# 格式範例：("SERVERNAME\INSTANCE1", "SERVERNAME2", "localhost")
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# --- 檢查 SQL Server PowerShell 模組 ---
# 確保已安裝 SQL Server 模組 (SqlServer) 才能使用 Invoke-Sqlcmd
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "SQL Server PowerShell 模組 (SqlServer) 未安裝。請先安裝此模組：Install-Module -Name SqlServer"
    # 如果您無法安裝，可以改用 .NET Framework 的 SqlConnection/SqlCommand 物件，但 Invoke-Sqlcmd 更簡單。
}

# --- 執行查詢迴圈 ---

$AllResults = foreach ($Server in $ServerList) {
    Write-Host "--- 正在連線到 $Server 上的資料庫 [$DatabaseName]..." -ForegroundColor Yellow
    
    try {
        # 使用 Invoke-Sqlcmd 執行查詢
        # -ServerInstance：伺服器名稱
        # -Database：資料庫名稱
        # -Query：要執行的 SQL 語句
        $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $Query -ErrorAction Stop
        
        # 將伺服器名稱添加到結果物件中，方便追蹤
        $Result | Select-Object @{Name='ServerInstance'; Expression={$Server}}, *
        
    } catch {
        # 處理連線失敗或查詢執行錯誤
        Write-Error "在伺服器 $Server 上執行查詢失敗: $($_.Exception.Message)"
        # 建立一個失敗物件，以保持輸出的結構一致性
        [PSCustomObject]@{
            ServerInstance = $Server
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

# --- 顯示所有結果 ---
$AllResults | Format-Table -AutoSize
