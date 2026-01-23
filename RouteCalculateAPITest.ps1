# --- 設定區 ---
$serverName = "YourServerName"
$databaseName = "YourDatabaseName"
$query = "SELECT id, locjson FROM routetable"
$baseUrl = "http://routeapi/route"

# --- 1. 從 SQL Server 取得資料 ---
$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True;"
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
$dataset = New-Object System.Data.DataSet

try {
    $connection.Open()
    $adapter.Fill($dataset)
    $connection.Close()

    $rows = $dataset.Tables[0].Rows

    foreach ($row in $rows) {
        $id = $row["id"]
        $jsonText = $row["locjson"]

        Write-Host "--- Processing ID: $id ---" -ForegroundColor Yellow

        if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
            # --- 2. 解析 JSON 並生成 URL ---
            # 假設 JSON 格式正確，使用 ConvertFrom-Json
            $data = $jsonText | ConvertFrom-Json
            
            # 提取所有 Value 裡面的座標並串聯
            $locParams = ($data.Value.Value | ForEach-Object { "loc=$([System.Web.HttpUtility]::UrlEncode($_))" }) -join "&"
            $fullUrl = "$baseUrl?$locParams"

            Write-Host "Request URL: $fullUrl" -ForegroundColor Gray

            # --- 3. 發送 HTTP Request 並分析 ---
            try {
                $response = Invoke-RestMethod -Uri $fullUrl -Method Get
                
                # 在這裡處理你的 Response
                Write-Host "Response received for ID $id" -ForegroundColor Green
                # $response | ... 你的分析邏輯
            }
            catch {
                Write-Warning "HTTP Request failed for ID $id: $_"
            }
        }
    }
}
catch {
    Write-Error "SQL Connection Error: $_"
}
finally {
    if ($connection.State -eq "Open") { $connection.Close() }
}
