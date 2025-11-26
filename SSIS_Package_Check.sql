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


-- 步驟 2: 使用 execution_id 查詢所有子 Package 的執行時間
USE SSISDB;
GO

DECLARE @TargetExecutionId BIGINT = 12345; -- **<<-- 請替換成你在步驟 1 找到的 ID**

SELECT
    t1.package_name AS PackageName,
    t1.executable_name AS ExecutableTaskName, -- 執行這個 Package 的 SSIS Task 名稱 (例如: Execute Package Task)
    t1.start_time AS StartTime,
    t1.end_time AS EndTime,
    -- 計算持續時間 (以秒為單位)
    DATEDIFF(SECOND, t1.start_time, t1.end_time) AS Duration_Seconds,
    t1.status AS ExecutionStatus
FROM
    catalog.executables t1
WHERE
    t1.execution_id = @TargetExecutionId
    -- 篩選出你感興趣的子 Package (Package Name 會是子 Package 的名稱)
    AND t1.package_name <> N'MasterPackageName.dtsx' 
    -- 狀態: 4=成功(Success), 6=失敗(Failure)
ORDER BY
    t1.start_time;
