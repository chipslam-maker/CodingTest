# 1. 設定 URL
$url = "http://ServerA/route/cal?lag=34.22,lat=0.21&lag=35.22,lat=0.23"

# 模擬真實瀏覽器並明確要求 JSON
Invoke-WebRequest -Uri $url `
                  -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" `
                  -Headers @{"Accept"="application/json"} `
                  -UseBasicParsing

# 2. 設定資料夾路徑與檔名
$dirPath = "C:\TEMP"
$dateStr = Get-Date -Format "yyyyMMdd"
$fileName = "discal_$($dateStr).json"
$targetPath = Join-Path -ChildPath $fileName -Path $dirPath

# 3. 檢查資料夾是否存在，不存在則建立
if (-not (Test-Path $dirPath)) {
    New-Item -Path $dirPath -ItemType Directory | Out-Null
}

try {
    # 4. 發送請求並取得內容
    Write-Host "正在請求資料..." -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing

    # 5. 將內容寫入指定的 C:\TEMP 檔案
    # 使用 -Force 確保如果當天重複執行會直接覆蓋舊檔
    $response.Content | Out-File -FilePath $targetPath -Encoding utf8 -Force
    Write-Host "成功！JSON 已存至: $targetPath" -ForegroundColor Green

    # 6. 解讀 JSON
    $jsonObj = Get-Content -Path $targetPath | ConvertFrom-Json
    
    # 範例：顯示解讀後的物件結構
    Write-Host "--- 解讀結果 ---" -ForegroundColor Yellow
    $jsonObj
}
catch {
    Write-Error "發生錯誤： $($_.Exception.Message)"
}
