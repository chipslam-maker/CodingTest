# ==============================================================================
# Script Name: Final_Continuous_Monitoring.ps1
# Description: Periodically executes two queries across two SQL Server instances:
#              1. Compares LAST_ID and calculates the batch count.
#              2. Checks the last run time and duration of a specified SQL Agent Job.
# Execution Frequency: Every 5 minutes (without relying on Windows Scheduler).
# ==============================================================================

# --- 1. Script-Level Parameters (Set only once) ---

# Set execution frequency to 5 minutes (5 * 60 = 300 seconds)
$SleepSeconds = 300 

# Please replace with your database name for the ID check
$DatabaseName = "YourDatabaseName"

# ⚠️ Ensure the list contains exactly two server instances for comparison
$ServerList = @("ServerA\SQLInstance", "ServerB\DefaultInstance") 

# --- A. Parameters for LAST_ID Check ---
# The query must return a single numeric column, named LAST_ID
$IDQuery = @"
SELECT 
    MAX(YourIDColumnName) AS LAST_ID
FROM 
    YourSchemaName.YourTableName;
"@
# Batch size setting for the difference calculation
$BatchSize = 5000

# --- B. Parameters for SQL Job Check ---
# Please replace with the exact name of the SQL Agent Job you want to check
$JobName = "Your SQL Agent Job Name"
$JobQuery = @"
SELECT TOP 1
    j.name AS JobName,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS LastRunDateTime,
    h.run_duration AS RunDurationRaw -- Stored as HHMMSS integer
FROM 
    msdb.dbo.sysjobs j
INNER JOIN 
    msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE 
    j.enabled = 1 
    AND h.step_id = 0 -- Overall job result
    AND j.name = '$JobName' 
ORDER BY 
    h.instance_id DESC;
"@


# --- 2. Pre-launch Environment Check ---

# Check SQL Server PowerShell Module (SqlServer)
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "【WARNING】SQL Server PowerShell module (SqlServer) is not installed. Please run first: Install-Module -Name SqlServer"
}

# Check if the number of servers is 2
if ($ServerList.Count -ne 2) {
    Write-Error "【ERROR】The server list (\$ServerList) must contain exactly two server instances for comparison."
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
    
    # --- 3a. Execute ID Query and Collect Results ---
    
    # Reinitialize array at the start of each loop
    $AllResults = @() 

    Write-Host "`n--- Running LAST_ID Check Query ---" -ForegroundColor DarkCyan
    foreach ($Server in $ServerList) {
        Write-Host "-> Connecting to $Server for ID check..." -ForegroundColor Yellow
        
        try {
            $Result = Invoke-Sqlcmd -ServerInstance $Server -Database $DatabaseName -Query $IDQuery -ErrorAction Stop
            $LastID = if ($Result.LAST_ID -is [DBNull] -or $Result.LAST_ID -eq $null) { 0 } else { [int]$Result.LAST_ID }
            
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server
                LAST_ID = $LastID
                Status = "Success"
            }
            Write-Host " - Retrieved ID: $LastID" -ForegroundColor Green
        } catch {
            Write-Error "Query execution failed on $Server: $(${$_}.Exception.Message)"
            $AllResults += [PSCustomObject]@{
                ServerInstance = $Server; LAST_ID = 0; Status = "Failed"
            }
        }
    }


    # --- 3b. Execute Query for SQL Job History and Process Duration ---
    
    Write-Host "`n--- Checking SQL Agent Job History ---" -ForegroundColor DarkCyan
    $JobResults = @()

    foreach ($Server in $ServerList) {
        Write-Host "-> Checking job '$JobName' on $Server..." -ForegroundColor Yellow
        
        try {
            $Result = Invoke-Sqlcmd -ServerInstance $Server -Database "msdb" -Query $JobQuery -ErrorAction Stop
            
            if (-not $Result) {
                $DurationFormatted = "N/A"; $LastRunFormatted = "N/A"
                Write-Warning " - No history found for job '$JobName' on $Server."
            } else {
                # Process RunDurationRaw (integer HHMMSS) into readable format
                $RunDurationRaw = $Result.RunDurationRaw.ToString("000000")
                $Hours = [int]($RunDurationRaw.Substring(0, 2))
                $Minutes = [int]($RunDurationRaw.Substring(2, 2))
                $Seconds = [int]($RunDurationRaw.Substring(4, 2))
                
                $DurationFormatted = "{0:D2}h {1:D2}m {2:D2}s" -f $Hours, $Minutes, $Seconds
                $LastRunFormatted = $Result.LastRunDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                
                Write-Host " - Last Run: $LastRunFormatted, Duration: $DurationFormatted" -ForegroundColor Green
            }

            $JobResults += [PSCustomObject]@{
                ServerInstance = $Server; JobName = $JobName; LastRun = $LastRunFormatted; Duration = $DurationFormatted; Status = "Success"
            }
        } catch {
            Write-Error "Failed to check job history on $Server: $(${$_}.Exception.Message)"
            $JobResults += [PSCustomObject]@{
                ServerInstance = $Server; JobName = $JobName; LastRun = "Error"; Duration = "Error"; Status = "Failed"
            }
        }
    }


    # --- 4. Analysis and Merged Output ---

    Write-Host "`n--- Merged Monitoring Report ---" -ForegroundColor DarkCyan
    
    # Check for success on both servers
    if ($AllResults[0].Status -ne "Success" -or $AllResults[1].Status -ne "Success") {
        Write-Warning "【WARNING】Comparison may be inaccurate due to connection/query failure on at least one server."
    } else {
        
        # Data Extraction
        $Server1Name = $AllResults[0].ServerInstance
        $ID1 = $AllResults[0].LAST_ID
        $JobLastRun1 = $JobResults[0].LastRun
        $JobDuration1 = $JobResults[0].Duration
        
        $Server2Name = $AllResults[1].ServerInstance
        $ID2 = $AllResults[1].LAST_ID
        $JobLastRun2 = $JobResults[1].LastRun
        $JobDuration2 = $JobResults[1].Duration
        
        # Calculations
        $Difference = [math]::Abs($ID1 - $ID2)
        $BatchCount = [System.Math]::Ceiling($Difference / $BatchSize)

        # --- Merged Output ---
        
        $Output1 = "Server 1 ($Server1Name) LAST_ID: $($ID1) - Last Execute Time: $JobLastRun1 - Duration: $JobDuration1"
        Write-Host $Output1 -ForegroundColor White
        
        $Output2 = "Server 2 ($Server2Name) LAST_ID: $($ID2) - Last Execute Time: $JobLastRun2 - Duration: $JobDuration2"
        Write-Host $Output2 -ForegroundColor White
        
        Write-Host "-------------------------------------------------------" -ForegroundColor DarkCyan

        # Formatted comparison results
        Write-Host ("Absolute Difference: {0:N0}" -f $Difference) -ForegroundColor Red
        Write-Host "Batch Size: $($BatchSize) rows" -ForegroundColor White
        Write-Host "Batches Required: $($BatchCount) times" -ForegroundColor Magenta
    }

    # --- 5. Sleep and Next Execution Prompt ---

    $EndTime = Get-Date
    Write-Host "🔴 Periodic Execution End: $($EndTime)" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor White
    Write-Host "Next execution will start in $($SleepSeconds) seconds..." -ForegroundColor Yellow

    # Pause for the specified number of seconds
    Start-Sleep -Seconds $SleepSeconds
}
# ==============================================================================
