# ==============================================================================
# 腳本名稱: ps_checkallstoreprocedure_value.ps1
# 功能: 遍歷 SQL Server 實例上所有 Database 及 Schema，檢查 SP 定義是否包含指定欄位。
# ==============================================================================

# 1. 設置變數
# ------------------------------------------------------------------------------
$SqlServer = "YourServerName"        # <<< 必填：替換為您的 SQL Server 實例名稱 (e.g., SERVER\INSTANCE)
$TargetColumn = "YourColumnName"     # <<< 必填：替換為您要尋找的欄位名稱 (e.g., 'LegacyCustomerID')

# 提示: 為了提高準確性，建議使用包含界定符的模式，例如：
# $TargetColumn = " YourColumnName " 


# 檢查 Invoke-Sqlcmd 是否可用
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Host "錯誤: 找不到 Invoke-Sqlcmd Cmdlet。" -ForegroundColor Red
    Write-Host "請確認已安裝 SQL Server PowerShell 模組。" -ForegroundColor Red
    exit
}

Write-Host "--- 連線至 $SqlServer，檢查欄位：$TargetColumn ---" -ForegroundColor Yellow

# 2. 獲取所有使用者 Database
# ------------------------------------------------------------------------------
# 查詢：獲取所有非系統 Database (ID > 4) 且狀態為 ONLINE (state = 0)
$DBQuery = "SELECT name AS DatabaseName FROM sys.databases WHERE database_id > 4 AND state = 0"

Write-Host "正在從 [master] 資料庫獲取所有 Database 清單..."
try {
    # 執行 DB 查詢 (連線到 master 資料庫)，使用 -TrustServerCertificate 解決 SSL 問題
    $AllDatabases = Invoke-Sqlcmd -ServerInstance $SqlServer -Database "master" -Query $DBQuery -TrustServerCertificate
    
    if (-not $AllDatabases) {
        Write-Host "❌ 找不到任何使用者 Database。" -ForegroundColor Red
        exit
    }
}
catch {
    Write-Host "⚠️ 錯誤: 獲取 Database 清單時發生錯誤: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

Write-Host "✅ 成功取得 $($AllDatabases.Count) 個 Database。開始檢查..." -ForegroundColor Green


# 3. 雙重迴圈：遍歷 Database 和 Schema 執行檢查
# ------------------------------------------------------------------------------
foreach ($DB in $AllDatabases) {
    $CurrentDBName = $DB.DatabaseName
    
    Write-Host "`n======================================================================="
    Write-Host "🌟 正在檢查 Database: [$CurrentDBName]" -ForegroundColor Cyan
    Write-Host "======================================================================="

    # 針對當前 Database，獲取所有 Schema
    $SchemaQuery = "
        SELECT name AS SchemaName 
        FROM sys.schemas 
        WHERE schema_id < 16384 AND name NOT IN ('guest')
    "
    
    try {
        # 執行 Schema 查詢 (連線到當前 Database)
        $AllSchemas = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $CurrentDBName -Query $SchemaQuery -TrustServerCertificate
    }
    catch {
        Write-Host "  ⚠️ 錯誤: 無法訪問或獲取 [$CurrentDBName] 的 Schema: $($_.Exception.Message)" -ForegroundColor Red
        continue # 跳過這個有問題的 DB
    }

    if (-not $AllSchemas) {
        Write-Host "  ❌ [$CurrentDBName] 中找不到任何使用者 Schema。"
        continue
    }

    # 中間層迴圈：遍歷所有 Schema 
    foreach ($Schema in $AllSchemas) {
        $CurrentSchemaName = $Schema.SchemaName
        
        # 構建用於檢查 SP 的 SQL 查詢 (已移除 is_encrypted，並篩選當前 Schema)
        $SqlQuery = @"
SELECT
    OBJECT_SCHEMA_NAME(m.object_id) AS [Schema Name],
    OBJECT_NAME(m.object_id) AS [Stored Procedure Name]
FROM
    sys.sql_modules m
JOIN 
    sys.objects o ON m.object_id = o.object_id
WHERE
    o.type = 'P' 
    AND OBJECT_SCHEMA_NAME(m.object_id) = N'$CurrentSchemaName' 
    AND CAST(m.definition AS NVARCHAR(MAX)) LIKE N'%$TargetColumn%';
"@

        # 執行 SP 檢查 (連線到當前 Database)
        try {
            $Results = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $CurrentDBName -Query $SqlQuery -TrustServerCertificate
            
            if ($Results) {
                Write-Host "`n  ✅ FOUND SPs in [$CurrentDBName].[$CurrentSchemaName]:" -ForegroundColor Green
                $Results | Format-Table -AutoSize
            }
        }
        catch {
            # 只顯示嚴重錯誤，忽略常見的 SP 執行錯誤
            Write-Host "    ⚠️ 執行檢查時發生錯誤 (可能為權限問題): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "Completed check for Database: [$CurrentDBName]" -ForegroundColor Cyan
}

Write-Host "`n--- Check Complete: 所有 Database 和 Schema 檢查完畢 ---"
