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

USE SSISDB;
GO

-- 步驟 1: 找出所有相關的 Execution ID (包含頂層和所有子 Package)
WITH RelevantExecutions AS (
    SELECT
        execution_id
    FROM
        [catalog].[executions]
    WHERE
        execution_id = 10099 -- <<-- [重要] 請將此替換為你的頂層 Package 的 Execution ID
    UNION ALL
    SELECT
        execution_id
    FROM
        [catalog].[executions]
    WHERE
        parent_id = 10099 -- <<-- 取得所有直接的子 Package
        -- 如果你的巢狀層級很深，可能需要使用遞迴 CTE (RECURSIVE CTE)
),
-- 步驟 2: 取得所有相關 Execution 的 Task Start (130) 和 Task End (140) 事件
TaskEvents AS (
    SELECT
        em.operation_id,
        em.message_source_name AS TaskName, -- Task 名稱
        ex.package_name AS PackageName,     -- 正在執行的 Package 名稱
        em.message_time,
        CASE em.message_type
            WHEN 130 THEN 'START'
            WHEN 140 THEN 'END'
            ELSE NULL
        END AS EventType
    FROM
        [catalog].[event_messages] em
    INNER JOIN
        [catalog].[executions] ex ON em.operation_id = ex.execution_id
    WHERE
        em.operation_id IN (SELECT execution_id FROM RelevantExecutions)
        AND em.message_type IN (130, 140) -- 篩選 Task Start 和 Task End 事件
),
-- 步驟 3: 使用 Window Function (LEAD) 將 Task Start 和 Task End 時間配對
TaskDurations AS (
    SELECT
        operation_id,
        PackageName,
        TaskName,
        message_time AS StartTime,
        -- 使用 LEAD 函數取得同一個 Task 的下一個事件時間 (預期為 END)
        LEAD(message_time, 1) OVER (
            PARTITION BY operation_id, TaskName
            ORDER BY message_time
        ) AS EndTime,
        EventType
    FROM
        TaskEvents
)
-- 步驟 4: 輸出最終結果 (只保留 Start 行，並計算持續時間)
SELECT
    td.operation_id AS ExecutionID,
    td.PackageName,
    td.TaskName,
    td.StartTime,
    td.EndTime,
    CAST(DATEDIFF(MILLISECOND, td.StartTime, td.EndTime) / 1000.0 AS DECIMAL(10, 3)) AS Duration_Seconds,
    DATEDIFF(MINUTE, td.StartTime, td.EndTime) AS Duration_Minutes
FROM
    TaskDurations td
WHERE
    td.EventType = 'START'
    AND td.EndTime IS NOT NULL -- 確保 Task 有結束時間
ORDER BY
    td.StartTime;
