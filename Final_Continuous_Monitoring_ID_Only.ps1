# ==============================================================================
# Script Name: Final_Continuous_Monitoring_ID_Only.ps1
# Description: Periodically monitors two SQL Server instances. Tracks LAST_ID 
#              Difference and ID Delta since the last run (using JSON persistence). 
# Execution Frequency: Every 5 minutes (300 seconds).
# ==============================================================================

# --- 1. Script-Level Parameters (Set only once) ---

# Set execution frequency to 5 minutes (5 * 60 = 300 seconds)
$SleepSeconds = 300 

# Please replace with your database name for the ID check
$DatabaseName = "YourDatabaseName"

# ⚠️ Ensure the list contains exactly two server instances for comparison
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# --- A. Parameters for LAST_ID Check ---
$IDQuery = @"
SELECT 
    MAX(YourIDColumnName) AS LAST_ID
FROM 
    YourSchemaName.YourTableName;
"@
# Batch size setting for the difference calculation
$BatchSize = 5000

# --- B. Parameters for Persistence ---
# File to store the LAST_ID results from the previous run (JSON format - Overwritten)
$LastIDFile = "C:\Temp\LastID_History.json" 

# --- C. Parameters for Logging ---
# File to store the historical execution report (CSV format - Appends new data)
# Ensure the directory exists (e.g., C:\Logs)
$LogFile = "C:\Logs\Monitoring_Report_History.csv" 


# --- Helper Functions for Persistence ---

# Function to read the LAST_ID from the previous run file
function Get-PreviousLastIDs {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path $Path) {
        try {
            return Get-Content $Path | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning " [WARNING] Failed to read or parse previous ID file: $($_.Exception.Message)"
            return $null
        }
    }
    return $null
}

# Function to save the current LAST_ID for the next run
function Save-CurrentLastIDs {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)]$CurrentResults)
    $DataToSave = $CurrentResults | Select-Object ServerInstance, LAST_ID
    $DataToSave | ConvertTo-Json -Depth 3 | Set-Content $Path -Force
    Write-Host " [INFO] Current LAST_IDs saved to $Path for next comparison." -ForegroundColor DarkYellow
}


# --- 2. Pre-launch Environment Check ---
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "【WARNING】SQL Server PowerShell module (SqlServer) is not installed. Please run first: Install-Module -Name SqlServer"
}
if ($ServerList.Count -ne 2) {
    Write-Error "【ERROR】The server list (\$ServerList) must contain exactly two server instances for comparison."
    exit
}


# ==============================================================================
#                 Main Execution Loop (Runs every 5 minutes)
# ==============================================================================
while ($true) {
    
    $StartTime = Get-Date

    Write-Host "`n=======================================================" -ForegroundColor White
    Write-Host "🟢 Periodic Execution Start: $($StartTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    
    # --- 3. Execution Setup and ID Query ---
    $PreviousIDs = Get-PreviousLastIDs -Path $LastIDFile
    if ($PreviousIDs -eq $null) {
        Write-Warning " [WARNING] No previous ID history found. Delta calculation will be skipped for this run."
    }
    
    # 3a. Execute ID Query and Collect Results
    $AllResults = @() 
    Write-Host "`n--- Running LAST_ID Check Query ---" -ForegroundColor DarkCyan
    foreach ($Server in $ServerList) {
        Write-Host "-> Connecting to $Server for ID check..." -ForegroundColor Yellow
        try {
            $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $IDQuery -ErrorAction Stop
            $LastID = if ($Result.LAST_ID -is [DBNull] -or $Result.LAST_ID -eq $null) { 0 } else { [int]$Result.LAST_ID }
            $AllResults += [PSCustomObject]@{ServerInstance = $Server; LAST_ID = $LastID; Status = "Success"}
            Write-Host " - Retrieved ID: $LastID" -ForegroundColor Green
        } catch {
            Write-Error "Query execution failed on $Server: $(${$_}.Exception.Message)"
            $AllResults += [PSCustomObject]@{ServerInstance = $Server; LAST_ID = 0; Status = "Failed"}
        }
    }

    # 3b. SQL Job History Check Removed: Initializing placeholder variables for merged output structure
    $JobResults = @(
        [PSCustomObject]@{ServerInstance = $ServerList[0]; LastRun = "N/A"; Duration = "N/A"; Status = "Removed"},
        [PSCustomObject]@{ServerInstance = $ServerList[1]; LastRun = "N/A"; Duration = "N/A"; Status = "Removed"}
    )


    # --- 4. Analysis and Merged Output ---

    Write-Host "`n--- Merged Monitoring Report ---" -ForegroundColor DarkCyan
    
    if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
        Write-Warning "【WARNING】Comparison may be inaccurate due to connection/query failure on at least one server."
    } else {
        
        # Delta Calculation Setup
        $PrevIDLookup = @{}; $Increase1 = 0; $Increase2 = 0
        if ($PreviousIDs) {
            $PreviousIDs | ForEach-Object {$PrevIDLookup[$_.ServerInstance] = $_.LAST_ID}
        }
        
        # Data Extraction
        $Server1Name = $AllResults[0].ServerInstance; $ID1 = $AllResults[0].LAST_ID; $JobLastRun1 = $JobResults[0].LastRun; $JobDuration1 = $JobResults[0].Duration
        $Server2Name = $AllResults[1].ServerInstance; $ID2 = $AllResults[1].LAST_ID; $JobLastRun2 = $JobResults[1].LastRun; $JobDuration2 = $JobResults[1].Duration
        
        # Delta Calculation (Increase since last run)
        $Increase1Output = " (No previous data)"
        $PrevID1 = $PrevIDLookup[$Server1Name]
        if ($PrevID1 -ne $null) {
            $Increase1 = $ID1 - $PrevID1
            $Increase1Output = " (Delta: +{0:N0})" -f $Increase1
        }
        $Increase2Output = " (No previous data)"
        $PrevID2 = $PrevIDLookup[$Server2Name]
        if ($PrevID2 -ne $null) {
            $Increase2 = $ID2 - $PrevID2
            $Increase2Output = " (Delta: +{0:N0})" -f $Increase2
        }

        # Calculations (Difference and Batches)
        $Difference = [math]::Abs($ID1 - $ID2)
        $BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)

        # --- Merged Output ---
        # Note: Job related fields will show 'N/A' as they were removed
        $Output1 = "Server 1 ($Server1Name) LAST_ID: $($ID1)$Increase1Output - Last Execute Time: $JobLastRun1 - Duration: $JobDuration1"
        Write-Host $Output1 -ForegroundColor White
        $Output2 = "Server 2 ($Server2Name) LAST_ID: $($ID2)$Increase2Output - Last Execute Time: $JobLastRun2 - Duration: $JobDuration2"
        Write-Host $Output2 -ForegroundColor White
        Write-Host "-------------------------------------------------------" -ForegroundColor DarkCyan

        # Formatted comparison results
        Write-Host ("Absolute Difference: {0:N0}" -f $Difference) -ForegroundColor Red
        Write-Host "Batch Size: $($BatchSize) rows" -ForegroundColor White
        Write-Host "Batches Required: $($BatchCount) times" -ForegroundColor Magenta
    }

    # --- 6. Persistence & Logging ---
    if ($AllResults.Count -eq 2 -and $AllResults[0].Status -eq "Success" -and $AllResults[1].Status -eq "Success") {
        # JSON Overwrite for Delta Tracking
        Save-CurrentLastIDs -Path $LastIDFile -CurrentResults $AllResults
        
        # CSV Append for Historical Logging
        $EndTime = Get-Date
        $LogEntry = [PSCustomObject]@{
            Timestamp = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
            Server1 = $Server1Name
            ID1 = $ID1
            Delta1 = $Increase1 
            Server2 = $Server2Name
            ID2 = $ID2
            Delta2 = $Increase2
            AbsoluteDifference = $Difference
            BatchCount = $BatchCount
        }
        $LogEntry | Export-Csv $LogFile -Append -NoTypeInformation -Force
        Write-Host " [INFO] Report summary appended to log file: $LogFile" -ForegroundColor DarkGreen

    } else {
        Write-Warning " [WARNING] Skipping persistence and logging: ID results are incomplete or failed. Previous data retained."
    }

    # --- 5. Sleep and Next Execution Prompt ---
    $EndTime = Get-Date
    Write-Host "🔴 Periodic Execution End: $($EndTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    Write-Host "Next execution will start in $($SleepSeconds) seconds..." -ForegroundColor Yellow

    Start-Sleep -Seconds $SleepSeconds
}
# ==============================================================================
