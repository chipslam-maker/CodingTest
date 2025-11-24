# 1. 設定要查找的字串 (Table 或 SP 名稱)
$TargetName = "YourTableNameOrSPName"

# 2. 設定 SSIS Project 的路徑
$ProjectPath = "C:\Your\SSIS\Project\Directory"

# 3. 執行搜索
Write-Host "--- Checking SSIS Packages for: $TargetName ---"

# 遞迴查找所有 .dtsx 檔案，並在內容中搜索 $TargetName
Get-ChildItem -Path $ProjectPath -Filter "*.dtsx" -Recurse | 
    Select-String -Pattern $TargetName -SimpleMatch | 
    ForEach-Object {
        # 輸出匹配到的檔案名，並使用 -Unique 確保每個檔案名只顯示一次
        Write-Host "✅ FOUND in Package: $($_.Filename)" -ForegroundColor Green
    }

Write-Host "--- Check Complete ---"
