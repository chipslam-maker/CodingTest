USE SSISDB;
GO

SELECT
    T1.execution_id,
    E.folder_name,
    E.project_name,
    E.package_name AS Main_Package_Name, -- 主套件 A.dtsx
    T1.package_name AS Executed_Package_Name, -- 執行中的套件 (A, B, C...)
    T1.executable_name AS Task_Name,
    T1.executable_path,
    T1.start_time,
    T1.end_time,
    T1.execution_duration AS Duration_ms, -- 執行時間 (毫秒)
    CONVERT(DECIMAL(10, 2), T1.execution_duration / 1000.0) AS Duration_Seconds, -- 執行時間 (秒)
    T1.execution_path
FROM
    catalog.executable_statistics AS T1
INNER JOIN
    catalog.executions AS E ON T1.execution_id = E.execution_id
WHERE
    -- 1. 篩選您的主套件名稱 (例如: A.dtsx)
    E.package_name = N'A.dtsx' 
    -- 2. (可選) 篩選特定的日期範圍
    -- AND E.start_time >= DATEADD(day, -7, GETDATE())
    -- 3. (可選) 只看執行成功的
    -- AND E.[status] = 7 
ORDER BY
    T1.execution_id DESC, 
    T1.start_time;
