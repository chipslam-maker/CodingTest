function Get-JsonStructure {
    param (
        $Object,
        $Depth = 0
    )

    $indent = "  " * $Depth
    
    if ($Object -is [System.Collections.IDictionary] -or $Object -is [PSCustomObject]) {
        # 取得所有屬性名稱
        $properties = $Object | Get-Member -MemberType NoteProperty, Property | Select-Object -ExpandProperty Name
        foreach ($prop in $properties) {
            Write-Host "$indent|-- $prop" -ForegroundColor Cyan
            # 遞迴進入下一層
            Get-JsonStructure -Object $Object.$prop -Depth ($Depth + 1)
        }
    }
    elseif ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        Write-Host "$indent(Array/List contains $($Object.Count) items)" -ForegroundColor Yellow
        # 只取第一個元素來分析結構，避免重複印出相同格式
        if ($Object.Count -gt 0) {
            Get-JsonStructure -Object $Object[0] -Depth ($Depth + 1)
        }
    }
}

# 使用範例：
# $response = Invoke-RestMethod ...
Get-JsonStructure -Object $response

# 1. 確保 $response 是已經 ConvertFrom-Json 的物件
# 2. 展開 features 陣列，並深入 properties 取得 distance
$allDistances = $response.features | ForEach-Object {
    $_.properties.distance
}

# 3. 過濾掉可能的空值，並轉為數字 (Double)
$numericDistances = $allDistances | Where-Object { $_ -ne $null } | ForEach-Object { [double]$_ }

# 輸出結果看看
Write-Host "總共抓到 $($numericDistances.Count) 個 distance 值"
$maxDist = ($numericDistances | Measure-Object -Maximum).Maximum
Write-Host "最大距離為: $maxDist" -ForegroundColor Cyan
