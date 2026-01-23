# --- 1. 初始化與環境設定 ---
Add-Type -AssemblyName System.Web # 用於 UrlEncode

# 配置參數 (請根據實際環境修改)
$config = @{
    GpsSourceServer = "GpsSourceServerName"
    GpsSourceDB     = "GpsSourceDatabase"
    RecordServer    = "RecordServerName"
    RecordDB        = "RecordDatabase"
    RouteApiUrl     = "http://routeapi/route"
    ConversionFact  = 1609.34
    Timeout         = 30
}

# 用於存放最終對比結果的 Array (之後 Further Logic 的數據源)
$resultsArray = New-Object System.Collections.Generic.List[PSCustomObject]

# --- 2. 從 GPS Source DB 取得座標資料 (批次 100 筆) ---
$gpsQuery = "SELECT TOP 100 id, locjson FROM routetable"
$connStringGps = "Server=$($config.GpsSourceServer);Database=$($config.GpsSourceDB);Integrated Security=True;"

try {
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($gpsQuery, $connStringGps)
    $dtGps = New-Object System.Data.DataTable
    $adapter.Fill($dtGps) | Out-Null
    Write-Host ">>> 已從 GPS Source 取得 $($dtGps.Rows.Count) 筆待處理資料。" -ForegroundColor Cyan

    if ($dtGps.Rows.Count -eq 0) { return }

    # --- 3. 逐筆調用 API 並計算當前最大距離 ---
    foreach ($row in $dtGps.Rows) {
        $id = $row["id"]
        $jsonText = $row["locjson"]
        
        Write-Host "[ID: $id] API 運算中..." -NoNewline

        try {
            # 解析 JSON 並組合 URL
            $data = $jsonText | ConvertFrom-Json
            $locParams = ($data.Value.Value | ForEach-Object { "loc=$([System.Web.HttpUtility]::UrlEncode($_))" }) -join "&"
            $fullUrl = "$($config.RouteApiUrl)?$locParams"

            # 呼叫 API 並等待回應
            $response = Invoke-RestMethod -Uri $fullUrl -Method Get -ErrorAction Stop -TimeoutSec $config.Timeout

            # 提取 Respond 中所有 distance 並找最大值
            $distances = $response.features.properties.distance | ForEach-Object { [double]$_ }
            
            if ($distances) {
                $maxMeters = ($distances | Measure-Object -Maximum).Maximum
                $currentMaxMiles = [Math]::Round($maxMeters / $config.ConversionFact, 2)

                # 存入結果陣列 (暫不包含 Record DB 的資料)
                $resultsArray.Add([PSCustomObject]@{
                    ID             = $id
                    CurrentMaxMile = $currentMaxMiles
                    RecordMaxMile  = $null  # 待填
                    Difference     = $null  # 待算
                    Status         = "Success"
                    ErrorCode      = 200
                })
                Write-Host " 完成 ($currentMaxMiles miles)" -ForegroundColor Green
            }
        }
        catch {
            $errCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "Error" }
            $resultsArray.Add([PSCustomObject]@{
                ID             = $id
                CurrentMaxMile = $null
                RecordMaxMile  = $null
                Difference     = $null
                Status         = "API Error: $($_.Exception.Message)"
                ErrorCode      = $errCode
            })
            Write-Host " 失敗 (Code: $errCode)" -ForegroundColor Red
        }
    }

    # --- 4. 批量從 Record DB 取得已有紀錄進行對比 ---
    $validIds = $resultsArray | Where-Object { $_.Status -eq "Success" } | Select-Object -ExpandProperty ID
    if ($validIds) {
        $idList = ($validIds | ForEach-Object { "'$_'" }) -join ","
        
        # 使用 WITH (NOLOCK) 查詢 Record DB 避免鎖定
        $recordQuery = "SELECT ID, MaxDist AS RecordDist FROM RecordTable WITH (NOLOCK) WHERE ID IN ($idList)"
        $connStringRec = "Server=$($config.RecordServer);Database=$($config.RecordDB);Integrated Security=True;"
        
        $adapterRec = New-Object System.Data.SqlClient.SqlDataAdapter($recordQuery, $connStringRec)
        $dtRecord = New-Object System.Data.DataTable
        $adapterRec.Fill($dtRecord) | Out-Null

        # --- 5. 在記憶體中進行比對邏輯 ---
        foreach ($res in $resultsArray) {
            if ($res.Status -eq "Success") {
                $recordRow = $dtRecord | Where-Object { $_.ID -eq $res.ID }
                if ($recordRow) {
                    $res.RecordMaxMile = [Math]::Round($recordRow.RecordDist, 2)
                    $res.Difference = [Math]::Round($res.CurrentMaxMile - $res.RecordMaxMile, 2)
                } else {
                    $res.Status = "New Record (Not in Record DB)"
                }
            }
        }
    }

}
catch {
    Write-Error "發生全域錯誤: $_"
}
finally {
    if ($connection -and $connection.State -eq "Open") { $connection.Close() }
}

# --- 6. 最終結果彙整 ---
Write-Host "`n=== 批次處理報告 (GPS vs Record) ===" -ForegroundColor Cyan
$resultsArray | Format-Table ID, CurrentMaxMile, RecordMaxMile, Difference, Status, ErrorCode -AutoSize

# 現在 $resultsArray 已經準備好進行你之後的 Further Logic。
