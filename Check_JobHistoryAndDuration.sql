# 1. Define variables
$ServerName = "YourServerName"               # <-- Replace with your SQL Server Instance Name (e.g., SQLINST01)
$DatabaseName = "msdb"
$JobName = "DW HH TranDtDB SA Real-Time Data ETL"   # <-- Replace with your actual Job Name
$OutputPath = "C:\Temp\JobHistory_Analysis.csv" # <-- Replace with your desired output path

# 2. Define the SQL Query
# Note: Ensure the job name in the WHERE clause is exactly correct.
$SqlQuery = @"
SELECT
    j.name AS JobName,
    h.step_id AS StepID,
    h.step_name AS StepName,
    -- Format run_date and run_time into a proper DATETIME field (StartTime)
    CAST(CAST(h.run_date AS NVARCHAR(8)) + ' ' +
         STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS NVARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
         AS DATETIME) AS StartTime,
    -- Calculate duration in total seconds (Duration_Seconds)
    h.run_duration/10000 * 3600 +
    (h.run_duration/100) % 100 * 60 +
    h.run_duration % 100 AS Duration_Seconds,
    -- Map status codes to English descriptions
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS RunStatusDescription
FROM
    msdb.dbo.sysjobhistory h
INNER JOIN
    msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE
    j.name = '$JobName'
    AND h.step_id <> 0 -- Exclude the job summary step (Step ID 0)
ORDER BY
    StartTime DESC;
"@

# 3. Execute the query and export results to CSV
# Invoke-Sqlcmd uses Windows Authentication by default.
Invoke-Sqlcmd -ServerInstance $ServerName `
              -Database $DatabaseName `
              -Query $SqlQuery |
    Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "Job History data has been successfully exported to: $OutputPath"
