# ==============================================================================
# Script Name: Final_Continuous_Monitoring_CSV_Delta.ps1
# Description: Periodically monitors two SQL Server instances. Tracks LAST_ID 
#              Difference and ID Delta since the last run by reading the last entry 
#              from the history CSV log file.
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

# --- B. Parameters for Logging (Persistence) ---
# File to store the historical execution report (CSV format - Appends new data)
# This file is now also used to retrieve the previous ID for delta calculation.
# Ensure the directory exists (e.g., C:\Logs)
$LogFile = "C:\Logs\Monitoring_Report_History.csv" 

# --- Helper Functions for Persistence ---

# 🌟 NEW Function: Read the LAST_ID from the last entry of the CSV log file
function Get-PreviousLastIDsFromLog {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path $Path) {
        try {
            # Read the entire CSV file, select the last object, and return it
            # Skips the first line if it's the header, ensuring we get the last data row.
            $LogContent = Import-Csv $Path
            
            # Check if log content is empty (except for header)
            if ($LogContent.Count -eq 0) {
                Write-Warning " [WARNING] Log file found, but contains no previous data."
                return $null
            }
            
            # Return the last successfully logged entry
            return $LogContent | Select-Object -Last 1
        } catch {
            Write-Warning " [WARNING] Failed to read or parse log file: $($_.Exception.Message)"
            return $null
        }
    }
    return $null
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
    
    # 🌟 NEW: Read the last log entry for delta calculation
    $PreviousLogEntry = Get-PreviousLastIDsFromLog -Path $LogFile
    if ($PreviousLogEntry -eq $null) {
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
    
    # 3b. Job Placeholder (for merged output format compatibility)
    $JobResults = @(
        [PSCustomObject]@{ServerInstance = $ServerList[0]; LastRun = "N/A"; Duration = "N/A"; Status = "Removed"},
        [PSCustomObject]@{ServerInstance = $ServerList[1]; LastRun = "N/A"; Duration = "N/A"; Status = "Removed"}
    )


    # --- 4. Analysis and Merged Output ---

    Write-Host "`n--- Merged Monitoring Report ---" -ForegroundColor DarkCyan
    
    if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
        Write-Warning "【WARNING】Comparison may be inaccurate due to connection/query failure on at least one server."
    } else {
        
        # 🌟 Delta Calculation Setup 🌟
        $Increase1 = 0; $Increase2 = 0
        
        # Data Extraction
        $Server1Name = $AllResults[0].ServerInstance; $ID1 = $AllResults[0].LAST_ID; $JobLastRun1 = $JobResults[0].LastRun; $JobDuration1 = $JobResults[0].Duration
        $Server2Name = $AllResults[1].ServerInstance; $ID2 = $AllResults[1].LAST_ID; $JobLastRun2 = $JobResults[1].LastRun; $JobDuration2 = $JobResults[1].Duration
        
        # Delta Calculation (Increase since last run)
        $Increase1Output = " (No previous data)"
        $Increase2Output = " (No previous data)"
        
        if ($PreviousLogEntry) {
            # Map the previous ID fields from the log to the current server instances
            # NOTE: We must ensure Server1/Server2 in the log match $ServerList[0] and $ServerList[1]
            
            # Server 1 Delta
            $PrevID1 = if ($PreviousLogEntry.Server1 -eq $Server1Name) { [long]$PreviousLogEntry.ID1 } else { [long]$PreviousLogEntry.ID2 }
            if ($PrevID1 -ne $null) {
                $Increase1 = $ID1 - $PrevID1
                $Increase1Output = " (Delta: +{0:N0})" -f $Increase1
            }

            # Server 2 Delta
            $PrevID2 = if ($PreviousLogEntry.Server2 -eq $Server2Name) { [long]$PreviousLogEntry.ID2 } else { [long]$PreviousLogEntry.ID1 }
            if ($PrevID2 -ne $null) {
                $Increase2 = $ID2 - $PrevID2
                $Increase2Output = " (Delta: +{0:N0})" -f $Increase2
            }
        }

        # Calculations (Difference and Batches)
        $Difference = [math]::Abs($ID1 - $ID2)
        $BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)

        # --- Merged Output ---
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

    # --- 6. Logging the current cycle's results (CSV - Append) ---
    if ($AllResults.Count -eq 2 -and $AllResults[0].Status -eq "Success" -and $AllResults[1].Status -eq "Success") {
        
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
        # Use Export-Csv with -Append to write the new record to the end of the file
        $LogEntry | Export-Csv $LogFile -Append -NoTypeInformation -Force
        Write-Host " [INFO] Report summary appended to log file: $LogFile" -ForegroundColor DarkGreen

    } else {
        Write-Warning " [WARNING] Skipping logging: ID results are incomplete or failed."
    }

    # --- 5. Sleep and Next Execution Prompt ---
    $EndTime = Get-Date
    Write-Host "🔴 Periodic Execution End: $($EndTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    Write-Host "Next execution will start in $($SleepSeconds) seconds..." -ForegroundColor Yellow

    Start-Sleep -Seconds $SleepSeconds
}
# ==============================================================================
