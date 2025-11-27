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
    -- T1: 包含執行時間數據
    catalog.executable_statistics AS T1
INNER JOIN
    -- E: 包含執行資訊 (用來篩選主套件)
    catalog.executions AS E 
    ON T1.execution_id = E.execution_id
INNER JOIN
    -- T2: 包含 Task 和 Package 名稱
    catalog.executables AS T2 
    ON T1.executable_id = T2.executable_id AND E.project_id = T2.project_id
WHERE
    -- 1. 篩選您的主套件名稱 (例如: A.dtsx)
    E.package_name = N'A.dtsx' 
    -- 2. (可選) 篩選特定的日期範圍
    -- AND E.start_time >= DATEADD(day, -7, GETDATE())
ORDER BY
    T1.execution_id DESC, 
    T1.start_time;
