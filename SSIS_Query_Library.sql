USE SSISDB;
GO

SELECT
    T1.execution_id,
    E.folder_name,
    E.project_name,
    E.package_name AS Main_Package_Name, -- 主套件 A.dtsx
    T2.package_name AS Executed_Package_Name, -- 執行中的套件 (A, B, C...)
    T2.executable_name AS Task_Name, -- Task 名稱
    T1.execution_path,
    T1.start_time,
    T1.end_time,
    T1.execution_duration AS Duration_ms, -- 執行時間 (毫秒)
    CONVERT(DECIMAL(10, 2), T1.execution_duration / 1000.0) AS Duration_Seconds -- 執行時間 (秒)
FROM
    catalog.executable_statistics AS T1
INNER JOIN
    catalog.executions AS E 
    ON T1.execution_id = E.execution_id
INNER JOIN
    catalog.executables AS T2 
    ON T1.executable_id = T2.executable_id 
WHERE
    -- 1. 篩選您的主套件名稱 (例如: A.dtsx)
    E.package_name = N'A.dtsx' 
    -- 2. 只包含在這次執行批次中實際被執行的 Task
    -- 否則 T2 會包含所有專案中的 Task 定義，導致結果過多或重複
    AND T2.package_name = E.package_name OR T2.package_name IN (
        SELECT 
            referenced_package_name 
        FROM 
            catalog.package_operation_messages 
        WHERE 
            operation_id = E.execution_id 
            AND message_type = 12003 -- 這是代表子套件執行的訊息類型
    )
ORDER BY
    T1.execution_id DESC, 
    T1.start_time;
