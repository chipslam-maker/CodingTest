# 1. 設定請求資訊
$url = "http://ServerA/route/cal?lag=34.22,lat=0.21&lag=35.22,lat=0.23"

# 2. 設定儲存路徑與檔名 (discal_yyyymmdd.json)
$dirPath = "C:\TEMP"
$dateStr = Get-Date -Format "yyyyMMdd"
$fileName = "discal_$($dateStr).json"
$targetPath = Join-Path -Path $dirPath -ChildPath $fileName

# 3. 確保 C:\TEMP 資料夾存在
if (-not (Test-Path $dirPath)) {
    New-Item -Path $dirPath -ItemType Directory | Out-Null
    Write-Host "已建立資料夾: $dirPath" -ForegroundColor Gray
}

# 4. 準備標頭資訊 (模擬瀏覽器)
$headers = @{
    "Accept" = "application/json"
}
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

try {
    Write-Host "正在發送請求至 ServerA..." -ForegroundColor Cyan
    
    # 5. 發送請求
    $response = Invoke-WebRequest -Uri $url `
                                  -Method Get `
                                  -Headers $headers `
                                  -UserAgent $userAgent `
                                  -UseBasicParsing

    # 6. 將結果寫入檔案
    $response.Content | Out-File -FilePath $targetPath -Encoding utf8 -Force
    Write-Host "成功！JSON 已儲存至: $targetPath" -ForegroundColor Green

    # 7. 解讀 JSON 內容供後續使用
    $jsonObj = $response.Content | ConvertFrom-Json
    
    # 範例：列出解讀後的資料 (可根據你的 JSON 結構調整)
    Write-Host "--- 檔案內容摘要 ---" -ForegroundColor Yellow
    $jsonObj | Format-Table # 或是直接用 $jsonObj

    # 使用 [-1] 取得陣列中的最後一個元素
    $lastItem = $jsonObj[-1]
    
    $distance = $lastItem.properties.distance
    $time = $lastItem.properties.time
    
    Write-Host "最後一筆距離: $distance" -ForegroundColor Cyan
    Write-Host "最後一筆時間: $time" -ForegroundColor Cyan
   
}
catch {
    Write-Host "請求失敗！" -ForegroundColor Red
    Write-Error $_.Exception.Message
}
