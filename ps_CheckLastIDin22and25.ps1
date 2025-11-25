# ==============================================================================
# Script Name: Compare-IDs-Continuous.ps1
# Description: Periodically executes a query across two SQL Server instances, 
#              compares LAST_ID, and calculates the batch count.
# Execution Frequency: Every 5 minutes (without relying on Windows Scheduler).
# ==============================================================================

# --- 1. Script-Level Parameters (Set only once) ---

# Set execution frequency to 5 minutes (5 * 60 = 300 seconds)
$SleepSeconds = 300 

# Please replace with your database name
$DatabaseName = "YourDatabaseName"

# ⚠️ Ensure the list contains exactly two server instances for comparison
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# Please replace with your actual query.
# The query must return a single numeric column, named LAST_ID
$Query = @"
SELECT 
    MAX(YourIDColumnName) AS LAST_ID
FROM 
    YourSchemaName.YourTableName;
"@

# Batch size setting
$BatchSize = 5000


# --- 2. Pre-launch Environment Check ---

# Check SQL Server PowerShell Module (SqlServer)
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "【WARNING】SQL Server PowerShell module (SqlServer) is not installed. Please run first: Install-Module -Name SqlServer"
}

# Check if the number of servers is 2
if ($ServerList.Count -ne 2) {
    Write-Error "【ERROR】The server list (\$ServerList) must contain exactly two server instances for comparison."
    # Terminate script
    exit
}


# ==============================================================================
#                 Main Execution Loop (Runs every 5 minutes)
# ==============================================================================
while ($true) {
    
    # Log the start time of the current cycle
    $StartTime = Get-Date

    Write-Host "`n=======================================================" -ForegroundColor White
    Write-Host "🟢 Periodic Execution Start: $($StartTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    
    # --- 3. Execute Query and Collect Results ---
    
    # Reinitialize array at the start of each loop to prevent data accumulation
    $AllResults = @() 

    foreach ($Server in $ServerList) {
        Write-Host "-> Connecting to $Server..." -ForegroundColor Yellow
        
        try {
            $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $Query -ErrorAction Stop
            
            # Extract and convert to integer, ensuring the value is valid
            $LastID = if ($Result.LAST_ID -is [DBNull] -or $Result.LAST_ID -eq $null) { 0 } else { [int]$Result.LAST_ID }
            
            # Add the result object to the $AllResults array
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server
                LAST_ID = $LastID
                Status = "Success"
            }
            Write-Host " - Retrieved ID: $LastID" -ForegroundColor Green

        } catch {
            Write-Error "Query execution failed on $Server: $($_.Exception.Message)"
            # Add failed result, setting ID to 0
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server
                LAST_ID = 0 
                Status = "Failed"
            }
        }
    }


    # --- 4. Data Analysis and Comparison ---

    if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
        Write-Warning "【WARNING】Comparison may be inaccurate due to connection/query failure on at least one server."
    } else {
        
        # Extract information
        $Server1Name = $AllResults[0].ServerInstance
        $ID1 = $AllResults[0].LAST_ID

        $Server2Name = $AllResults[1].ServerInstance
        $ID2 = $AllResults[1].LAST_ID

        # Calculate absolute difference
        $Difference = [math]::Abs($ID1 - $ID2)

        # Calculate required batch count (using Ceiling)
        $BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)

        # --- Output Final Results ---
        Write-Host "`n--- Comparison Result Report ---" -ForegroundColor DarkCyan
        Write-Host "Server 1 ($Server1Name) LAST_ID: $($ID1)" -ForegroundColor White
        Write-Host "Server 2 ($Server2Name) LAST_ID: $($ID2)" -ForegroundColor White
        Write-Host "-------------------------------------------------------" -ForegroundColor DarkCyan

        # Formatted output for difference
        Write-Host ("Absolute Difference: {0:N0}" -f $Difference) -ForegroundColor Red
        Write-Host "Batch Size: $($BatchSize) rows" -ForegroundColor White
        Write-Host "Batches Required: $($BatchCount) times" -ForegroundColor Magenta
    }

    # --- 5. Sleep and Next Execution Prompt ---

    $EndTime = Get-Date
    Write-Host "🔴 Periodic Execution End: $($EndTime)" -ForegroundColor White
    Write-Host "Next execution will start in $($SleepSeconds) seconds..." -ForegroundColor Yellow

    # Pause for the specified number of seconds
    Start-Sleep -Seconds $SleepSeconds
}
# ==============================================================================
