/* ##################################################################################### */
/* ##################################################################################### */
/* ##################################################################################### */
-- 步驟 1: 在 SSISDB 中找到最近一次執行記錄的 ID
USE SSISDB;
GO

SELECT TOP 1
    execution_id,
    folder_name AS ProjectFolder,
    project_name,
    package_name,
    start_time
FROM
    catalog.executions
WHERE
    package_name = N'MasterPackageName.dtsx' -- **<<-- 請替換成你主 Package 的名稱**
    -- 建議加上專案名稱過濾，讓結果更精確
    -- AND project_name = N'YourProjectName' 
ORDER BY
    start_time DESC;
/* ##################################################################################### */
/* ##################################################################################### */
/* ##################################################################################### */
USE SSISDB;
GO

-- 1. 找到 主 Package 的最新 Execution ID (假設名稱是 '主TASK.dtsx')
DECLARE @TopExecutionId BIGINT;
SELECT TOP 1 @TopExecutionId = execution_id
FROM [catalog].[executions]
WHERE package_name LIKE '主TASK.dtsx%' -- 調整為你的實際 Package 文件名
ORDER BY start_time DESC;

-- 2. 取得該 Execution ID 下所有 Task (包括主和子 Package 內的 Task) 的 Start/End 事件
WITH TaskEvents AS (
    SELECT
        em.operation_id,
        em.message_source_name AS TaskName, -- Task 名稱
        ex.package_name AS PackageName,     -- 主 Package 名稱 ('主TASK.dtsx')
        em.message_time,
        CASE em.message_type
            WHEN 130 THEN 'START' -- Task Start
            WHEN 140 THEN 'END'   -- Task End
            ELSE NULL
        END AS EventType
    FROM
        [catalog].[event_messages] em
    INNER JOIN
        [catalog].[executions] ex ON em.operation_id = ex.execution_id
    WHERE
        em.operation_id = @TopExecutionId
        AND em.message_type IN (130, 140)
),
-- 3. 使用 LEAD 將 Task Start 和 Task End 時間配對
TaskDurations AS (
    SELECT
        operation_id,
        PackageName,
        TaskName,
        message_time AS StartTime,
        -- 使用 LEAD 函數取得同一個 Task 名稱的下一個事件時間
        LEAD(message_time, 1) OVER (
            PARTITION BY operation_id, TaskName
            ORDER BY message_time
        ) AS EndTime,
        EventType
    FROM
        TaskEvents
)
-- 4. 輸出最終結果
SELECT
    td.operation_id AS ExecutionID,
    td.PackageName AS MasterPackage,
    -- 由於子 Package 的 Task 也在這裡，TaskName 可能是來自 主TASK 或 SUB TASK
    td.TaskName,
    td.StartTime,
    td.EndTime,
    CAST(DATEDIFF(MILLISECOND, td.StartTime, td.EndTime) / 1000.0 AS DECIMAL(10, 3)) AS Duration_Seconds
FROM
    TaskDurations td
WHERE
    td.EventType = 'START'
    AND td.EndTime IS NOT NULL
ORDER BY
    td.StartTime;


SELECT
    t.LogMessage,
    -- 1. 使用 PATINDEX 找到 "Elapsed time: " 之後的位置
    PATINDEX('%Elapsed time: [0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]%', t.LogMessage) AS StartPosition,
    -- 2. 由於時間長度固定為 12 個字元 (HH:MM:SS.mmm)
    SUBSTRING(
        t.LogMessage,
        -- 計算提取的開始位置：PATINDEX 找到第一個數字的位置
        PATINDEX('%[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]%', t.LogMessage),
        -- 時間長度固定為 12
        12
    ) AS ExtractedTime
FROM
    (VALUES
        (1, 'XXXX Elapsed time: 00:00:23.019'),
        (2, 'YYYY Elapsed time: 01:15:45.999'),
        (3, 'No time here.')
    ) AS t (ID, LogMessage)
WHERE
    t.LogMessage LIKE '%Elapsed time: [0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]%';
