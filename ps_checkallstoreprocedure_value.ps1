# ==============================================================================
# 腳本名稱: ps_checkallstoreprocedure_value.ps1
# 功能: 檢查 SQL Server 實例上的所有 Database/Schema 中的 SP 定義 
#       AND 檢查 SQL Agent Jobs 中的執行指令，以尋找指定的欄位名稱。
# 語言: 輸出為中文
# ==============================================================================

# 1. 設置變數
# ------------------------------------------------------------------------------
$SqlServer = "YourServerName"        # <<< 必填：替換為您的 SQL Server 實例名稱 (e.g., SERVER\INSTANCE)
$TargetColumn = "YourColumnName"     # <<< 必填：替換為您要尋找的欄位名稱 (e.g., 'LegacyCustomerID')

# 提示: 為了提高準確性，您可以考慮在 TargetColumn 兩邊加上空格或界定符。
# 例如，如果欄位名是 'Email'，但想避免匹配 'EmailAddress'，可以嘗試 $TargetColumn = " Email "

# 檢查 Invoke-Sqlcmd 是否可用
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Host "錯誤: 找不到 Invoke-Sqlcmd Cmdlet。" -ForegroundColor Red
    Write-Host "請確認已安裝 SQL Server PowerShell 模組。" -ForegroundColor Red
    exit
}

Write-Host "--- 連線至 $SqlServer，檢查欄位：$TargetColumn ---" -ForegroundColor Yellow


# 2. 檢查 SQL Server Agent Jobs (在 msdb 資料庫中)
# ------------------------------------------------------------------------------
Write-Host "`n======================================================================="
Write-Host "🕵️ 步驟 1: 開始檢查 SQL Server Agent Jobs (msdb)..." -ForegroundColor Magenta
Write-Host "======================================================================="

# 查詢：在 msdb 資料庫中，檢查所有 Job Step 的 'command' 欄位
$JobCheckQuery = @"
SELECT 
    j.name AS JobName,
    s.step_id AS StepID,
    s.step_name AS StepName
FROM 
    msdb.dbo.sysjobs j
JOIN 
    msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
WHERE
    s.command LIKE N'%$TargetColumn%';
"@

try {
    $JobResults = Invoke-Sqlcmd -ServerInstance $SqlServer -Database "msdb" -Query $JobCheckQuery -TrustServerCertificate
    
    if ($JobResults) {
        Write-Host "  ✅ FOUND: 在以下 SQL Agent Jobs 中找到了 '$TargetColumn'：" -ForegroundColor Green
        $JobResults | Format-Table -AutoSize
    }
    else {
        Write-Host "  . NOT Found: 在任何 SQL Agent Job Step 中未發現 '$TargetColumn'。"
    }
}
catch {
    Write-Host "  ⚠️ 錯誤: 執行 Job 檢查時發生錯誤 (請確認有權限訪問 msdb): $($_.Exception.Message)" -ForegroundColor Red
}


# 3. 獲取所有使用者 Database 清單
# ------------------------------------------------------------------------------
# 查詢：獲取所有非系統 Database (ID > 4) 且狀態為 ONLINE (state = 0)
$DBQuery = "SELECT name AS DatabaseName FROM sys.databases WHERE database_id > 4 AND state = 0"

Write-Host "`n======================================================================="
Write-Host "📝 步驟 2: 獲取所有 Database 清單並開始檢查 SP 定義..." -ForegroundColor Yellow
Write-Host "======================================================================="

try {
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

Write-Host "✅ 成功取得 $($AllDatabases.Count) 個 Database。開始逐一檢查..." -ForegroundColor Green


# 4. 雙重迴圈：遍歷 Database 和 Schema 執行 SP 檢查
# ------------------------------------------------------------------------------
foreach ($DB in $AllDatabases) {
    $CurrentDBName = $DB.DatabaseName
    
    Write-Host "`n--- 正在檢查 Database: [$CurrentDBName] ---" -ForegroundColor Cyan

    # 針對當前 Database，獲取所有 Schema
    $SchemaQuery = "
        SELECT name AS SchemaName 
        FROM sys.schemas 
        WHERE schema_id < 16384 AND name NOT IN ('guest')
    "
    
    try {
        $AllSchemas = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $CurrentDBName -Query $SchemaQuery -TrustServerCertificate
    }
    catch {
        Write-Host "  ⚠️ 錯誤: 無法訪問或獲取 [$CurrentDBName] 的 Schema: $($_.Exception.Message)" -ForegroundColor Red
        continue 
    }

    # 中間層迴圈：遍歷所有 Schema 
    foreach ($Schema in $AllSchemas) {
        $CurrentSchemaName = $Schema.SchemaName
        
        # 構建用於檢查 SP 的 SQL 查詢 (篩選當前 Schema，並移除 is_encrypted)
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

        # 執行 SP 檢查
        try {
            $Results = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $CurrentDBName -Query $SqlQuery -TrustServerCertificate
            
            if ($Results) {
                Write-Host "`n  🎉 FOUND SP in [$CurrentDBName].[$CurrentSchemaName]:" -ForegroundColor Green
                $Results | Format-Table -AutoSize
            }
        }
        catch {
            Write-Host "    ⚠️ 執行檢查時發生錯誤: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "--- [$CurrentDBName] 檢查完成 ---" -ForegroundColor Cyan
}

Write-Host "`n======================================================================="
Write-Host "--- CHECK COMPLETE: 所有 Database 和 Job Agent 檢查完畢 ---" -ForegroundColor Yellow
Write-Host "======================================================================="
