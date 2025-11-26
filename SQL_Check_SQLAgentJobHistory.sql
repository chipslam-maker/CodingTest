-- 取得 SQL Agent Job History 中，特定 Job 的每個 Step 的執行時間

USE msdb;
GO

SELECT
    j.name AS JobName,
    h.step_id AS StepID,
    h.step_name AS StepName,
    -- 格式化執行日期和時間
    CAST(CAST(h.run_date AS NVARCHAR(8)) + ' ' +
         STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS NVARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
         AS DATETIME) AS StartTime,
    -- 計算執行持續時間 (以秒為單位)
    -- duration 格式是 HHMMSS
    CAST(h.run_duration/10000 AS VARCHAR(2)) + 'h ' +
    CAST((h.run_duration/100) % 100 AS VARCHAR(2)) + 'm ' +
    CAST(h.run_duration % 100 AS VARCHAR(2)) + 's' AS Duration_HHMMSS,
    -- 轉換為總秒數 (以方便計算或分析)
    h.run_duration/10000 * 3600 +
    (h.run_duration/100) % 100 * 60 +
    h.run_duration % 100 AS Duration_Seconds,
    CASE h.run_status
        WHEN 0 THEN '失敗 (Failed)'
        WHEN 1 THEN '成功 (Succeeded)'
        WHEN 2 THEN '重試 (Retry)'
        WHEN 3 THEN '已取消 (Canceled)'
        WHEN 4 THEN '進行中 (In Progress)'
        ELSE '未知'
    END AS RunStatusDescription,
    h.message AS ExecutionMessage
FROM
    msdb.dbo.sysjobhistory h
INNER JOIN
    msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE
    j.name = 'DW HH TranDtDB SA Real-Time Data ETL'  -- **<<-- 請在這裡替換成你想要查詢的 Job 名稱**
    AND h.step_id <> 0 -- 排除 Step ID 0 (這是 Job 整體的摘要行)
    -- 你可以根據需要添加日期篩選，例如:
    -- AND h.run_date = CONVERT(NVARCHAR(8), GETDATE(), 112) -- 今天執行的記錄
ORDER BY
    StartTime DESC, h.step_id;
