INSERT INTO [dbo].[stg_PAFLOAD]
           ([Postcode], [PostTown], [DependantLocality], ...)
SELECT
    ISNULL(T1.Postcode, ''),
    ISNULL(T1.PostTown, ''),
    ISNULL(T1.DependantLocality, ''),
    -- ... 其他 ISNULL 轉換 ...
FROM OPENROWSET(
    BULK 'C:\ChipsFolder\PAF_Revamp\SourceCSV\CSV PAF.csv',
    FORMATFILE='C:\ChipsFolder\PAF_Revamp\SourceCSV\BCPConfigFile\PAF_Import.xml'
) AS T1
ORDER BY T1.Postcode ASC; -- <--- 在這裡加入 ORDER BY
