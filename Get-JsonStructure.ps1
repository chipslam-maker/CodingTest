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
