CREATE TABLE VehicleInventory (
    -- 基本識別資料
    Id INT IDENTITY(1,1) PRIMARY KEY,
    RegistrationNumber NVARCHAR(20) NOT NULL UNIQUE, -- 車牌號碼 (唯一鍵，不能重複)
    
    -- DVLA API 回傳的車輛規格
    Make NVARCHAR(50),               -- 品牌 (例如: TOYOTA)
    Model NVARCHAR(100),             -- 型號 (某些 API 會提供)
    YearOfManufacture INT,           -- 製造年份
    FuelType NVARCHAR(20),           -- 燃料類型 (Petrol, Diesel, etc.)
    EngineCapacity INT,              -- 引擎容量 (cc)
    
    -- 排放與油耗 (核心指標)
    CO2Emissions_G_KM FLOAT,         -- 官方 CO2 排放量 (g/km)
    CombinedMPG FLOAT,               -- 綜合油耗 (Miles Per Gallon) - 需自行對照或第三方 API 填入
    
    -- 成本與足跡計算 (計算結果儲存)
    AnnualMileage_Miles FLOAT DEFAULT 0,  -- 預計或實際年里程
    CalculatedAnnualCarbon_KG FLOAT,      -- 計算出的年碳排放量 (kg)
    CalculatedFuelCost_GBP FLOAT,         -- 計算出的年燃料成本 (GBP)
    
    -- 自動化管理欄位
    Processed BIT DEFAULT 0,         -- 標記是否已從 API 獲取資料 (0:未處理, 1:已處理)
    LastUpdated DATETIME DEFAULT GETDATE(), -- 最後更新時間
    Notes NVARCHAR(MAX)              -- 備註 (例如: 找不到車牌的錯誤訊息)
);

-- 建立索引以加快查詢速度
CREATE INDEX IX_VehicleInventory_Reg ON VehicleInventory(RegistrationNumber);
CREATE INDEX IX_VehicleInventory_Processed ON VehicleInventory(Processed);


# --- 配置區域 ---
$apiKey = "YOUR_DVLA_API_KEY"
$apiUrl = "https://driver-vehicle-licensing.api.gov.uk/vehicle-enquiry/v1/vehicles"
$connectionString = "Server=YOUR_SERVER;Database=YOUR_DB;Integrated Security=True;"

# --- 定義查詢 Function ---
function Get-VehicleData {
    param ([string]$vrm)
    
    $headers = @{
        "x-api-key" = $apiKey
        "Content-Type" = "application/json"
    }
    
    # 移除車牌空格並轉為 JSON payload
    $body = @{ registrationNumber = $vrm.Replace(" ", "") } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
        return $response
    }
    catch {
        Write-Warning "無法找到車牌: $vrm - $($_.Exception.Message)"
        return $null
    }
}

# --- 主程式：讀取、查詢、寫入 ---

# 1. 從 DB 讀取車牌 (假設資料表叫 VehicleInventory)
$query = "SELECT RegistrationNumber FROM VehicleInventory WHERE Processed = 0"
# 註：此處需根據你的 DB 類型（SQL/MySQL/SQLite）使用對應的 PS Module，例如 SqlServer
$vehicles = Invoke-Sqlcmd -ConnectionString $connectionString -Query $query

foreach ($row in $vehicles) {
    $vrm = $row.RegistrationNumber
    Write-Host "正在查詢車牌: $vrm..."
    
    $data = Get-VehicleData -vrm $vrm
    
    if ($data) {
$vrm = $row.RegistrationNumber
$make = $data.make -replace "'", "''" # 處理品牌名稱中有單引號的情況，如 O'Reilly (雖然車廠少見)
$co2 = $data.co2Emissions
$fuel = $data.fuelType
$year = $data.yearOfManufacture

$updateQuery = @"
UPDATE VehicleInventory 
SET 
    Make = '$make',
    FuelType = '$fuel',
    YearOfManufacture = $year,
    CO2Emissions_G_KM = $(if($co2){$co2}else{"NULL"}),
    Processed = 1,
    LastUpdated = GETDATE()
WHERE RegistrationNumber = '$vrm'
"@


        Invoke-Sqlcmd -ConnectionString $connectionString -Query $updateQuery
        
        Write-Host "✅ 已更新: $vrm ($make, $co2 g/km)" -ForegroundColor Green
    }
    
    # 稍微延遲以符合 API 速率限制
    Start-Sleep -Milliseconds 500
}
