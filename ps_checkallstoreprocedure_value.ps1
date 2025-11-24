# 1. 設定連線資訊
$SqlServer = "YourServerName"        # <--- 請替換這裡
$SqlDatabase = "YourDatabaseName"    # <--- 請替換這裡

# 2. 設定要查找的欄位名稱 (Column Name)
$TargetColumn = "YourColumnName"     # <--- 請替換這裡

Write-Host "--- 連線至 $SqlServer 資料庫 $SqlDatabase，檢查欄位：$TargetColumn ---"

# 3. 定義 SQL 查詢：取得所有使用者 Schema 的名稱
$SchemaQuery = @"
SELECT 
    name AS SchemaName
FROM 
    sys.schemas 
WHERE 
    schema_id < 16384 
    AND name NOT IN ('guest');
"@

Write-Host "Retrieving Schemas..."
try {
    # **** 關鍵修正：加入 -TrustServerCertificate 參數 ****
    $AllSchemas = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $SqlDatabase -Query $SchemaQuery -TrustServerCertificate 
    
    if (-not $AllSchemas) {
        Write-Host "❌ No user schemas found." -ForegroundColor Red
        exit
    }
}
catch {
    Write-Host "⚠️ Error retrieving schemas: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

Write-Host "✅ 成功取得 $($AllSchemas.Count) 個 Schema。開始逐一檢查..." -ForegroundColor Green

# 4. 遍歷每個 Schema 並執行 SP 檢查
foreach ($Schema in $AllSchemas) {
    $CurrentSchemaName = $Schema.SchemaName
    
    # 構建用於檢查 SP 的 SQL 查詢
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
    AND m.is_encrypted = 0 
    AND CAST(m.definition AS NVARCHAR(MAX)) LIKE N'%$TargetColumn%';
"@

    # 執行查詢，同樣加入 -TrustServerCertificate
    try {
        $Results = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $SqlDatabase -Query $SqlQuery -TrustServerCertificate
        
        if ($Results) {
            Write-Host "`n🌟 FOUND in Schema: [$CurrentSchemaName] 🌟" -ForegroundColor Yellow
            $Results | Format-Table -AutoSize
        }
    }
    catch {
        Write-Host "  ⚠️ Error executing SQL command for [$CurrentSchemaName]: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n--- Check Complete: All Schemas Checked ---"
