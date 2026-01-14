CREATE TABLE medic (
    id INT IDENTITY(1,1) PRIMARY KEY,   
    mid VARCHAR(20) NOT NULL,           
    mname VARCHAR(100) NOT NULL,       
    mnumber VARCHAR(50) NOT NULL,       
    mDate DATE NOT NULL,                
    eDate DATE NOT NULL,                
    quantity INT NOT NULL,             
    perUnit DECIMAL(10,2) NOT NULL      
);

INSERT INTO medic(mid, mname, mnumber, mDate, eDate, quantity, perUnit) VALUES
('123456', 'cbc', 'D500', '2011-07-01', '2022-04-14', 140, 200),
('34521',  'abc', 'abc', '2020-10-01', '2021-02-16', 6,   250),
('123',    'acd', 'gh78', '2020-10-01', '2020-07-13', 6,   452),
('512',    'p200', '552336', '2020-06-23', '2021-05-20', 150, 25),
('5555',   'N30', '456321', '2020-07-14', '2022-03-24', 603, 243),
('11111',  'xyz', '123456', '2020-06-09', '2021-01-04', 160, 167),
('22222', 'vitaminC', 'VC500', '2023-09-19', '2027-09-18', 200, 150),
('88888', 'Paracetamol', 'P500', '2002-05-19', '2030-08-27', 300, 75);
select*from medic

DELETE FROM medic where id=52;

 select count(mname) from medic where eDate >= getdate();
 select count(mname) from medic where eDate <= getdate();

UPDATE medic SET eDate = '2026-12-01' WHERE id = 1;
UPDATE medic SET eDate = '2027-05-15' WHERE id = 2;
UPDATE medic SET eDate = '2028-01-20' WHERE id = 5;



/* ============================================
   0) قاعدة البيانات المستهدفة
============================================ */
IF DB_ID('pharmacy') IS NOT NULL
    USE pharmacy;
GO

/* ============================================
   1) تجهيز جدول medic للربط والتزامن
============================================ */
-- عمود يربط medic بالصيدلاني (users.id)
IF COL_LENGTH('dbo.medic','PharmacistID') IS NULL
BEGIN
    ALTER TABLE dbo.medic ADD PharmacistID INT NULL;
    ALTER TABLE dbo.medic WITH CHECK
        ADD CONSTRAINT FK_medic_users
        FOREIGN KEY (PharmacistID) REFERENCES dbo.[users](id);
END

-- قيم افتراضية للتواريخ (طالما ما عندنا نظام دفعات)
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.medic') AND name='DF_medic_mDate')
    ALTER TABLE dbo.medic ADD CONSTRAINT DF_medic_mDate DEFAULT (CAST(GETDATE() AS DATE)) FOR mDate;

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.medic') AND name='DF_medic_eDate')
    ALTER TABLE dbo.medic ADD CONSTRAINT DF_medic_eDate DEFAULT (CAST('2099-12-31' AS DATE)) FOR eDate;

-- منع تكرار نفس الدواء لنفس الصيدلاني داخل medic
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='UX_medic_PharmMid' AND object_id=OBJECT_ID('dbo.medic'))
    CREATE UNIQUE INDEX UX_medic_PharmMid ON dbo.medic(PharmacistID, mid);
GO

/* ============================================
   2) إجراء المزامنة (مصحّح باستخدام #src)
============================================ */
IF OBJECT_ID('dbo.sp_SyncMedicFromInventory','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SyncMedicFromInventory;
GO
CREATE PROCEDURE dbo.sp_SyncMedicFromInventory
AS
BEGIN
  SET NOCOUNT ON;

  -- 2.1 تجميع المصدر في جدول مؤقت
  IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

  SELECT
      pm.PharmacistID,
      mid      = CAST(m.MedicineID AS VARCHAR(20)),
      mname    = m.MedName,
      mnumber  = CONCAT('SKU-', m.MedicineID),
      quantity = CAST(pm.QtyAvailable AS INT),
      perUnit  = m.Price
  INTO #src
  FROM dbo.PharmacistMedicines pm
  JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID;

  -- 2.2 تحديث الموجود في medic
  UPDATE d
     SET d.mname   = s.mname,
         d.mnumber = s.mnumber,
         d.quantity= s.quantity,
         d.perUnit = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- 2.3 إدراج السجلات الجديدة
  INSERT INTO dbo.medic (mid, mname, mnumber, mDate, eDate, quantity, perUnit, PharmacistID)
  SELECT s.mid, s.mname, s.mnumber, CAST(GETDATE() AS DATE), CAST('2099-12-31' AS DATE),
         s.quantity, s.perUnit, s.PharmacistID
  FROM #src s
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.medic d
    WHERE d.PharmacistID = s.PharmacistID AND d.mid = s.mid
  );

  -- 2.4 حذف ما لم يعد موجودًا في المخزون
  DELETE d
  FROM dbo.medic d
  WHERE d.PharmacistID IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM #src s
      WHERE s.PharmacistID = d.PharmacistID AND s.mid = d.mid
    );

  DROP TABLE #src;
END
GO

/* ============================================
   3) Triggers لتحديث medic تلقائيًا
============================================ */

-- 3.a) INSERT/UPDATE على PharmacistMedicines => upsert في medic
IF OBJECT_ID('dbo.tr_PM_AIU_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_PM_AIU_medic;
GO
CREATE TRIGGER dbo.tr_PM_AIU_medic
ON dbo.PharmacistMedicines
AFTER INSERT, UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

  SELECT
      i.PharmacistID,
      mid      = CAST(m.MedicineID AS VARCHAR(20)),
      mname    = m.MedName,
      mnumber  = CONCAT('SKU-', m.MedicineID),
      quantity = CAST(i.QtyAvailable AS INT),
      perUnit  = m.Price
  INTO #src
  FROM inserted i
  JOIN dbo.Medicines m ON m.MedicineID = i.MedicineID;

  -- تحديث
  UPDATE d
     SET d.mname   = s.mname,
         d.mnumber = s.mnumber,
         d.quantity= s.quantity,
         d.perUnit = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- إدراج الجديد
  INSERT INTO dbo.medic (mid, mname, mnumber, mDate, eDate, quantity, perUnit, PharmacistID)
  SELECT s.mid, s.mname, s.mnumber, CAST(GETDATE() AS DATE), CAST('2099-12-31' AS DATE),
         s.quantity, s.perUnit, s.PharmacistID
  FROM #src s
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.medic d WHERE d.PharmacistID = s.PharmacistID AND d.mid = s.mid
  );

  DROP TABLE #src;
END
GO

-- 3.b) DELETE من PharmacistMedicines => حذف من medic
IF OBJECT_ID('dbo.tr_PM_D_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_PM_D_medic;
GO
CREATE TRIGGER dbo.tr_PM_D_medic
ON dbo.PharmacistMedicines
AFTER DELETE
AS
BEGIN
  SET NOCOUNT ON;

  DELETE d
  FROM dbo.medic d
  JOIN deleted x
    ON d.PharmacistID = x.PharmacistID
   AND d.mid = CAST(x.MedicineID AS VARCHAR(20));
END
GO

-- 3.c) تغيير اسم/سعر الدواء في Medicines => تحديث medic
IF OBJECT_ID('dbo.tr_Medicines_Update_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_Medicines_Update_medic;
GO
CREATE TRIGGER dbo.tr_Medicines_Update_medic
ON dbo.Medicines
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  IF UPDATE(MedName) OR UPDATE(Price)
  BEGIN
      UPDATE d
         SET d.mname   = m.MedName,
             d.perUnit = m.Price,
             d.mnumber = CONCAT('SKU-', m.MedicineID)
      FROM dbo.medic d
      JOIN inserted m
        ON d.mid = CAST(m.MedicineID AS VARCHAR(20));
  END
END
GO

/* ============================================
   4) View اختياري للعرض الحي (بدون تكرار بيانات)
============================================ */
IF OBJECT_ID('dbo.v_Medic_ByPharmacist','V') IS NOT NULL
    DROP VIEW dbo.v_Medic_ByPharmacist;
GO
CREATE VIEW dbo.v_Medic_ByPharmacist
AS
SELECT
    pm.ID                                AS id,
    CAST(m.MedicineID AS VARCHAR(20))    AS mid,
    m.MedName                            AS mname,
    CONCAT('SKU-', m.MedicineID)         AS mnumber,
    CAST(GETDATE() AS DATE)              AS mDate,
    CAST('2099-12-31' AS DATE)           AS eDate,
    CAST(pm.QtyAvailable AS INT)         AS quantity,
    m.Price                              AS perUnit,
    u.id                                 AS PharmacistID,
    u.username                           AS PharmacistUsername
FROM dbo.PharmacistMedicines pm
JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
JOIN dbo.[users]  u ON u.id = pm.PharmacistID
WHERE u.userRole = 'Pharmacist';
GO

/* ============================================
   5) مزامنة أولية الآن لملء medic من المخزون الحالي
============================================ */
EXEC dbo.sp_SyncMedicFromInventory;
GO

/* ============================================
   6) أمثلة استخدام/تحقق
============================================ */
-- أدوية الصيدلاني kumar من جدول medic (mname = MedName)
SELECT *
FROM dbo.medic
WHERE PharmacistID = (SELECT id FROM dbo.[users] WHERE username='kumar')
ORDER BY mname;

-- نفس الشيء عبر الـ View الحي
SELECT *
FROM dbo.v_Medic_ByPharmacist
WHERE PharmacistUsername = 'kumar'
ORDER BY mname;

-- إحصاءات انتهاء (بتاريخ افتراضي حالياً)
SELECT 
  SUM(CASE WHEN eDate >= CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS NotExpired,
  SUM(CASE WHEN eDate <  CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS Expired
FROM dbo.medic
WHERE PharmacistID = (SELECT id FROM dbo.[users] WHERE username='kumar');



SELECT id, username, userRole
FROM dbo.[users]
WHERE username IN ('kumar','ph_new');


SELECT u.username, COUNT(*) AS ItemsInInventory
FROM dbo.PharmacistMedicines pm
JOIN dbo.[users] u ON u.id = pm.PharmacistID
WHERE u.username IN ('kumar','ph_new')
GROUP BY u.username;


-- أضِف أدوية للصيدلاني الجديد (يتجاهل المكررات إن وجدت)
INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT u.id, m.MedicineID, 200
FROM dbo.[users] u
CROSS APPLY (
   SELECT TOP (30) MedicineID
   FROM dbo.Medicines
   ORDER BY MedicineID
) m
WHERE u.username = 'ph_new'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.PharmacistMedicines pm
      WHERE pm.PharmacistID = u.id AND pm.MedicineID = m.MedicineID
  );

-- شغّل المزامنة لتعبئة جدول medic تلقائيًا
EXEC dbo.sp_SyncMedicFromInventory;


-- من جدول medic
SELECT *
FROM dbo.medic
WHERE PharmacistID = (SELECT id FROM dbo.[users] WHERE username='ph_new')
ORDER BY mname;

-- من الـ View (تأكد أن userRole='Pharmacist')
SELECT *
FROM dbo.v_Medic_ByPharmacist
WHERE PharmacistUsername = 'ph_new'
ORDER BY mname;



SELECT 
    id AS PharmacistID,
    username,
    name AS FullName,
    email,
    mobile
FROM dbo.[users]
WHERE userRole = 'Pharmacist'
ORDER BY username;















USE pharmacy;
GO

DECLARE @RohanID INT = (
    SELECT id FROM dbo.[users]
    WHERE username = 'rohan' AND userRole = 'Pharmacist'
);

IF @RohanID IS NULL
BEGIN
    RAISERROR(N'المستخدم "rohan" غير موجود أو ليس صيدلاني.',16,1);
    RETURN;
END;

-- أضف 70 دواء للصيدلاني rohan (يتجاهل المكررات)
INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT @RohanID, m.MedicineID, 150.00
FROM dbo.Medicines m
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.PharmacistMedicines pm
    WHERE pm.PharmacistID = @RohanID AND pm.MedicineID = m.MedicineID
)
ORDER BY m.MedicineID
OFFSET 0 ROWS FETCH NEXT 70 ROWS ONLY;

-- حدّث جدول medic تلقائيًا بعد الإضافة
EXEC dbo.sp_SyncMedicFromInventory;

-- عرض تحقق سريع
SELECT 
    u.username AS Pharmacist,
    COUNT(pm.MedicineID) AS MedicineCount,
    SUM(pm.QtyAvailable) AS TotalQty
FROM dbo.PharmacistMedicines pm
JOIN dbo.[users] u ON u.id = pm.PharmacistID
WHERE u.username = 'rohan'
GROUP BY u.username;






-- مزامنة فورية بين medic و Medicines
UPDATE mdc
SET mdc.mname = med.MedName
FROM dbo.medic mdc
JOIN dbo.Medicines med
     ON mdc.mid = CAST(med.MedicineID AS VARCHAR(20));









-- SQL Server 2014-compatible

-- 1) Drop old trigger if it exists (دفعة مستقلّة)
IF OBJECT_ID('dbo.tr_Medicines_Update_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_Medicines_Update_medic;
GO

-- 2) Create trigger (لا تكتبي أي شيء قبل CREATE TRIGGER في هذه الدفعة)
CREATE TRIGGER dbo.tr_Medicines_Update_medic
ON dbo.Medicines
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- يُسمح باستخدام IF UPDATE داخل التريغر فقط (وهنا هو المكان الصحيح)
    IF UPDATE(MedName) OR UPDATE(Price)
    BEGIN
        UPDATE d
        SET d.mname   = i.MedName,
            d.perUnit = i.Price,
            d.mnumber = CONCAT('SKU-', i.MedicineID)
        FROM dbo.medic AS d
        JOIN inserted AS i
          ON d.mid = CAST(i.MedicineID AS VARCHAR(20));
    END
END
GO





-- غيّري اسم دواء واحد تجربة
UPDATE dbo.Medicines
SET MedName = 'Paracetamol 500mg - UPDATED'
WHERE MedName = 'Paracetamol 500mg';

-- شوفِ انعكاس الاسم في medic
SELECT d.mid, d.mname
FROM dbo.medic d
JOIN dbo.Medicines m ON d.mid = CAST(m.MedicineID AS VARCHAR(20))
WHERE m.MedName LIKE 'Paracetamol 500mg%';





















SELECT name, parent_class_desc, create_date
FROM sys.triggers
WHERE name = 'tr_Medicines_Update_medic';










UPDATE dbo.Medicines
SET MedName = 'Paracetamol 500mg UPDATED'
WHERE MedName = 'Paracetamol 500mg';



SELECT MedicineID, MedName
FROM dbo.Medicines
WHERE MedName LIKE 'Paracetamol%';


SELECT d.mid, d.mname
FROM dbo.medic d
JOIN dbo.Medicines m 
  ON d.mid = CAST(m.MedicineID AS VARCHAR(20))
WHERE m.MedName LIKE 'Paracetamol 500mg%';



SELECT t.name AS TriggerName, 
       p.name AS TableName, 
       t.is_disabled
FROM sys.triggers t
JOIN sys.objects p ON t.parent_id = p.object_id
WHERE t.name = 'tr_Medicines_Update_medic';



-- تأكدي إن mname في medic يطابق MedName في Medicines حسب الـ MedicineID
UPDATE d
SET d.mname = m.MedName,
    d.perUnit = m.Price,
    d.mnumber = CONCAT('SKU-', m.MedicineID)
FROM dbo.medic d
JOIN dbo.Medicines m
  ON d.mid = CAST(m.MedicineID AS VARCHAR(20));



  UPDATE dbo.Medicines
SET MedName = 'Paracetamol 500mg TEST'
WHERE MedName LIKE 'Paracetamol 500mg%';




;WITH dups AS (
  SELECT
      id,
      PharmacistID,
      mid,
      ROW_NUMBER() OVER (PARTITION BY PharmacistID, mid ORDER BY id) AS rn
  FROM dbo.medic
  WHERE PharmacistID IS NOT NULL
)
DELETE FROM dups WHERE rn > 1;





;WITH dups AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY PharmacistID, mid ORDER BY id) AS rn
  FROM dbo.medic
  WHERE PharmacistID IS NOT NULL
)
DELETE FROM dups WHERE rn > 1;





IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_medic_PharmMid'
      AND object_id = OBJECT_ID('dbo.medic')
)
BEGIN
    -- SQL Server 2014 يدعم فهرس مفلتر
    CREATE UNIQUE INDEX UX_medic_PharmMid
    ON dbo.medic(PharmacistID, mid)
    WHERE PharmacistID IS NOT NULL;
END






/* ============================================
0) اختاري قاعدة البيانات
============================================ */
IF DB_ID('pharmacy') IS NOT NULL
    USE pharmacy;
GO

/* ============================================
1) تجهيز جدول medic (إضافة FK إن لم يكن موجودًا)
============================================ */
IF COL_LENGTH('dbo.medic','PharmacistID') IS NULL
BEGIN
    ALTER TABLE dbo.medic ADD PharmacistID INT NULL;
    ALTER TABLE dbo.medic WITH CHECK
        ADD CONSTRAINT FK_medic_users
        FOREIGN KEY (PharmacistID) REFERENCES dbo.[users](id);
END
-- تواريخ افتراضية (لحين إضافة نظام دفعات إن رغبتِ)
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.medic') AND name='DF_medic_mDate')
    ALTER TABLE dbo.medic ADD CONSTRAINT DF_medic_mDate DEFAULT (CAST(GETDATE() AS DATE)) FOR mDate;
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.medic') AND name='DF_medic_eDate')
    ALTER TABLE dbo.medic ADD CONSTRAINT DF_medic_eDate DEFAULT (CAST('2099-12-31' AS DATE)) FOR eDate;
GO

/* ============================================
2) تنظيف سريع: احذف صفوف medic العامة وغير المرتبطة بالمخزون
============================================ */
-- احذف الصفوف العامة بدون صيدلاني
DELETE FROM dbo.medic WHERE PharmacistID IS NULL;

-- احذف أي صف ليس له مقابل في PharmacistMedicines (صيدلاني + نفس الدواء)
DELETE d
FROM dbo.medic d
LEFT JOIN dbo.PharmacistMedicines pm
       ON pm.PharmacistID = d.PharmacistID
      AND pm.MedicineID   = TRY_CAST(d.mid AS INT)
WHERE pm.PharmacistID IS NULL;

-- وحّد الاسم/السعر/الكود من جدول Medicines حسب الـ MedicineID
UPDATE d
SET d.mname   = m.MedName,
    d.perUnit = m.Price,
    d.mnumber = CONCAT('SKU-', m.MedicineID)
FROM dbo.medic d
JOIN dbo.Medicines m
  ON d.mid = CAST(m.MedicineID AS VARCHAR(20));

-- حاول ربط صفوف لا تطابق بالـ ID عبر الاسم (لو موجودة)
UPDATE d
SET d.mid     = CAST(m.MedicineID AS VARCHAR(20)),
    d.mname   = m.MedName,
    d.perUnit = m.Price,
    d.mnumber = CONCAT('SKU-', m.MedicineID)
FROM dbo.medic d
JOIN dbo.Medicines m
  ON d.mname = m.MedName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Medicines mm
    WHERE d.mid = CAST(mm.MedicineID AS VARCHAR(20))
);

-- احذف التكرارات لنفس الصيدلاني ونفس الدواء (نُبقي أقدم سجل)
;WITH dups AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY PharmacistID, mid ORDER BY id) AS rn
  FROM dbo.medic
)
DELETE FROM dups WHERE rn > 1;
GO

/* ============================================
3) إجراء مزامنة آمن (باستخدام #src)
============================================ */
IF OBJECT_ID('dbo.sp_SyncMedicFromInventory','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SyncMedicFromInventory;
GO
CREATE PROCEDURE dbo.sp_SyncMedicFromInventory
AS
BEGIN
  SET NOCOUNT ON;

  IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

  -- المصدر: مخزون الصيادلة + معلومات الدواء
  SELECT
      pm.PharmacistID,
      mid      = CAST(m.MedicineID AS VARCHAR(20)),
      mname    = m.MedName,
      mnumber  = CONCAT('SKU-', m.MedicineID),
      quantity = CAST(pm.QtyAvailable AS INT),
      perUnit  = m.Price
  INTO #src
  FROM dbo.PharmacistMedicines pm
  JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID;

  -- تحديث الموجود
  UPDATE d
     SET d.mname   = s.mname,
         d.mnumber = s.mnumber,
         d.quantity= s.quantity,
         d.perUnit = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- إدراج الجديد
  INSERT INTO dbo.medic (mid, mname, mnumber, mDate, eDate, quantity, perUnit, PharmacistID)
  SELECT s.mid, s.mname, s.mnumber, CAST(GETDATE() AS DATE), CAST('2099-12-31' AS DATE),
         s.quantity, s.perUnit, s.PharmacistID
  FROM #src s
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.medic d
    WHERE d.PharmacistID = s.PharmacistID AND d.mid = s.mid
  );

  -- حذف ما لم يعد موجودًا في المخزون
  DELETE d
  FROM dbo.medic d
  WHERE NOT EXISTS (
      SELECT 1 FROM #src s
      WHERE s.PharmacistID = d.PharmacistID AND s.mid = d.mid
  );

  DROP TABLE #src;
END
GO

/* ============================================
4) تريغرات مزامنة تلقائية
============================================ */
-- 4.a INSERT/UPDATE على PharmacistMedicines => upsert في medic
IF OBJECT_ID('dbo.tr_PM_AIU_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_PM_AIU_medic;
GO
CREATE TRIGGER dbo.tr_PM_AIU_medic
ON dbo.PharmacistMedicines
AFTER INSERT, UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

  SELECT
      i.PharmacistID,
      mid      = CAST(m.MedicineID AS VARCHAR(20)),
      mname    = m.MedName,
      mnumber  = CONCAT('SKU-', m.MedicineID),
      quantity = CAST(i.QtyAvailable AS INT),
      perUnit  = m.Price
  INTO #src
  FROM inserted i
  JOIN dbo.Medicines m ON m.MedicineID = i.MedicineID;

  -- تحديث
  UPDATE d
     SET d.mname   = s.mname,
         d.mnumber = s.mnumber,
         d.quantity= s.quantity,
         d.perUnit = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- إدراج الجديد
  INSERT INTO dbo.medic (mid, mname, mnumber, mDate, eDate, quantity, perUnit, PharmacistID)
  SELECT s.mid, s.mname, s.mnumber, CAST(GETDATE() AS DATE), CAST('2099-12-31' AS DATE),
         s.quantity, s.perUnit, s.PharmacistID
  FROM #src s
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.medic d WHERE d.PharmacistID = s.PharmacistID AND d.mid = s.mid
  );

  DROP TABLE #src;
END
GO

-- 4.b DELETE من PharmacistMedicines => حذف من medic
IF OBJECT_ID('dbo.tr_PM_D_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_PM_D_medic;
GO
CREATE TRIGGER dbo.tr_PM_D_medic
ON dbo.PharmacistMedicines
AFTER DELETE
AS
BEGIN
  SET NOCOUNT ON;

  DELETE d
  FROM dbo.medic d
  JOIN deleted x
    ON d.PharmacistID = x.PharmacistID
   AND d.mid = CAST(x.MedicineID AS VARCHAR(20));
END
GO

-- 4.c UPDATE لاسم/سعر الدواء في Medicines => تحديث تلقائي في medic
IF OBJECT_ID('dbo.tr_Medicines_Update_medic','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_Medicines_Update_medic;
GO
CREATE TRIGGER dbo.tr_Medicines_Update_medic
ON dbo.Medicines
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  IF (UPDATE(MedName) OR UPDATE(Price))
  BEGIN
      UPDATE d
      SET d.mname   = i.MedName,
          d.perUnit = i.Price,
          d.mnumber = CONCAT('SKU-', i.MedicineID)
      FROM dbo.medic d
      JOIN inserted i
        ON d.mid = CAST(i.MedicineID AS VARCHAR(20));
  END
END
GO

/* ============================================
5) اجعل PharmacistID NOT NULL ثم أنشئ فهرس فريد مفلتر
============================================ */
-- احذف الفهرس لو موجود (حتى نقدر نعدّل العمود)
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.medic') AND name = 'UX_medic_PharmMid'
)
    DROP INDEX UX_medic_PharmMid ON dbo.medic;
GO

-- تأكدي أنه لا يوجد NULL
IF EXISTS (SELECT 1 FROM dbo.medic WHERE PharmacistID IS NULL)
BEGIN
    RAISERROR(N'يوجد صفوف PharmacistID = NULL في medic. احذفيها أو عالجيها أولًا.',16,1);
    RETURN;
END
GO

-- الآن اجعل العمود إلزامي
ALTER TABLE dbo.medic ALTER COLUMN PharmacistID INT NOT NULL;
GO

-- أعيدي إنشاء الفهرس المفلتر لمنع التكرار لكل صيدلاني
CREATE UNIQUE INDEX UX_medic_PharmMid
ON dbo.medic(PharmacistID, mid)
WHERE PharmacistID IS NOT NULL;
GO

/* ============================================
6) مزامنة أولية + فحوص سريعة
============================================ */
EXEC dbo.sp_SyncMedicFromInventory;

-- لا يجب أن توجد صفوف عامة
SELECT COUNT(*) AS NullPharmacistID FROM dbo.medic WHERE PharmacistID IS NULL;

-- لا يجب أن يوجد تكرار لنفس الصيدلاني/الدواء
SELECT PharmacistID, mid, COUNT(*) AS Cnt
FROM dbo.medic
GROUP BY PharmacistID, mid
HAVING COUNT(*) > 1;

-- مثال عرض: أدوية صيدلاني معيّن
-- غيّري 'kumar' إلى أي صيدلاني آخر
SELECT m.*
FROM dbo.medic m
WHERE m.PharmacistID = (SELECT id FROM dbo.[users] WHERE username='kumar')
ORDER BY m.mname;




USE pharmacy;
GO

IF OBJECT_ID('dbo.v_MyInventory','V') IS NOT NULL
    DROP VIEW dbo.v_MyInventory;
GO

CREATE VIEW dbo.v_MyInventory
AS
SELECT
    pm.PharmacistID,
    m.MedicineID,
    m.MedName      AS Medicine,
    m.[Description],
    SUM(pm.QtyAvailable) AS Available
FROM dbo.PharmacistMedicines pm
JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
GROUP BY
    pm.PharmacistID, m.MedicineID, m.MedName, m.[Description];
GO






SELECT * FROM dbo.v_MyInventory;




--- إنشاء فهرس فريد لكل صيدلاني ودواء إذا ما كان موجود
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.medic')
      AND name = 'UX_medic_PharmMid'
)
BEGIN
    CREATE UNIQUE INDEX UX_medic_PharmMid
    ON dbo.medic(PharmacistID, mid);
END
GO








USE pharmacy;
GO

/* =========================================================
   1) ثابت: 70 دواء بالاسم والسعر والوصف (تعريف + تغذية Medicines)
   ========================================================= */
IF OBJECT_ID('tempdb..#seed70') IS NOT NULL DROP TABLE #seed70;
CREATE TABLE #seed70(
    MedName       VARCHAR(250) PRIMARY KEY,
    Price         DECIMAL(10,2) NOT NULL,
    [Description] NVARCHAR(500) NULL
);

INSERT INTO #seed70(MedName, Price, [Description]) VALUES
('Paracetamol 500mg',            0.75,  N'Analgesic/antipyretic'),
('Ibuprofen 200mg',              0.90,  N'NSAID for pain/fever'),
('Diclofenac 50mg',              0.95,  N'NSAID'),
('Aspirin 81mg',                 0.50,  N'Low-dose antiplatelet'),
('Naproxen 250mg',               1.10,  N'NSAID'),
('Amoxicillin 500mg',            2.80,  N'Antibiotic - penicillin'),
('Azithromycin 500mg',           3.20,  N'Antibiotic - macrolide'),
('Ciprofloxacin 500mg',          2.90,  N'Antibiotic - fluoroquinolone'),
('Doxycycline 100mg',            2.60,  N'Antibiotic - tetracycline'),
('Metronidazole 500mg',          1.80,  N'Antibiotic/antiprotozoal'),
('Clarithromycin 500mg',         3.10,  N'Macrolide antibiotic'),
('Co-amoxiclav 625mg',           3.50,  N'Amoxicillin + clavulanate'),
('Cephalexin 500mg',             2.20,  N'Cephalosporin antibiotic'),
('Cefuroxime 500mg',             2.70,  N'Cephalosporin antibiotic'),
('Fluconazole 150mg',            1.75,  N'Antifungal'),
('Clotrimazole 1% cream',        1.20,  N'Topical antifungal'),
('Acyclovir 400mg',              2.10,  N'Antiviral'),
('Loratadine 10mg',              0.85,  N'Antihistamine (non-drowsy)'),
('Cetirizine 10mg',              0.90,  N'Antihistamine'),
('Fexofenadine 120mg',           1.40,  N'Antihistamine'),
('Salbutamol Inhaler',           4.90,  N'Bronchodilator (SABA)'),
('Budesonide Inhaler 200mcg',    7.50,  N'Inhaled corticosteroid'),
('Montelukast 10mg',             1.95,  N'Leukotriene antagonist'),
('Omeprazole 20mg',              1.30,  N'PPI for GERD'),
('Pantoprazole 40mg',            1.40,  N'PPI'),
('Ranitidine 150mg',             0.90,  N'H2 blocker (legacy)'),
('Domperidone 10mg',             0.80,  N'Prokinetic/antiemetic'),
('Metoclopramide 10mg',          0.70,  N'Antiemetic'),
('Loperamide 2mg',               0.65,  N'Antidiarrheal'),
('Oral Rehydration Salts',       0.50,  N'ORS sachet'),
('Ferrous Sulfate 325mg',        0.70,  N'Iron supplement'),
('Folic Acid 5mg',               0.60,  N'Vitamin B9 supplement'),
('Vitamin D3 1000 IU',           0.55,  N'Cholecalciferol'),
('Vitamin B Complex',            0.80,  N'Multivitamin B group'),
('Zinc 25mg',                    0.55,  N'Mineral supplement'),
('Calcium 500mg',                0.65,  N'Mineral supplement'),
('Magnesium 250mg',              0.75,  N'Mineral supplement'),
('Metformin 500mg',              2.20,  N'Antidiabetic - biguanide'),
('Glimepiride 2mg',              1.60,  N'Sulfonylurea antidiabetic'),
('Insulin Glargine 100U',       12.00,  N'Basal insulin'),
('Amlodipine 5mg',               1.95,  N'Calcium channel blocker'),
('Losartan 50mg',                1.85,  N'ARB'),
('Lisinopril 10mg',              1.10,  N'ACE inhibitor'),
('Atenolol 50mg',                1.25,  N'Beta blocker'),
('Hydrochlorothiazide 25mg',     0.80,  N'Thiazide diuretic'),
('Furosemide 40mg',              0.90,  N'Loop diuretic'),
('Atorvastatin 20mg',            2.40,  N'Statin'),
('Simvastatin 20mg',             1.90,  N'Statin'),
('Clopidogrel 75mg',             2.10,  N'Antiplatelet'),
('Warfarin 5mg',                 1.20,  N'Anticoagulant (monitor INR)'),
('Levothyroxine 50mcg',          1.70,  N'Thyroid hormone'),
('Allopurinol 100mg',            1.30,  N'Xanthine oxidase inhibitor'),
('Colchicine 0.5mg',             1.10,  N'Anti-gout'),
('Diclofenac Gel 1%',            1.50,  N'Topical NSAID'),
('Ibuprofen Syrup 100mg/5ml',    0.95,  N'Pediatric analgesic'),
('Paracetamol Syrup 120mg/5ml',  0.80,  N'Pediatric antipyretic'),
('Povidone-Iodine 10% solution', 1.00,  N'Antiseptic'),
('Chlorhexidine 0.12% mouthwash',1.20,  N'Antiseptic mouthwash'),
('Hydrocortisone 1% cream',      1.10,  N'Topical steroid (mild)'),
('Miconazole 2% oral gel',       1.40,  N'Antifungal oral gel'),
('Nitroglycerin 0.5mg SL',       2.00,  N'Antianginal (sublingual)'),
('Isosorbide Mononitrate 20mg',  1.60,  N'Antianginal (long-acting)'),
('Sertraline 50mg',              2.30,  N'SSRI'),
('Diazepam 5mg',                 1.50,  N'Anxiolytic/benzodiazepine'),
('Gabapentin 300mg',             2.60,  N'Neuropathic pain/anticonvulsant'),
('Tramadol 50mg',                1.90,  N'Analgesic (opioid-like)'),
('Melatonin 3mg',                1.10,  N'Sleep aid'),
('Salbutamol Nebules 2.5mg/3ml', 1.80,  N'Nebulized SABA'),
('Insulin Regular 100U',        10.00,  N'Fast-acting insulin');

-- Upsert into Medicines (add missing or update price/description if changed)
MERGE dbo.Medicines AS tgt
USING #seed70 AS src
   ON tgt.MedName = src.MedName
WHEN MATCHED THEN
    UPDATE SET tgt.Price = src.Price, tgt.[Description] = src.[Description]
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MedName, Price, [Description])
    VALUES (src.MedName, src.Price, src.[Description]);

/* جدول يحتفظ بأسماء الأدوية الافتراضية (مرة واحدة) */
IF OBJECT_ID('dbo.DefaultProvisionMeds','U') IS NULL
BEGIN
    CREATE TABLE dbo.DefaultProvisionMeds(
        MedName VARCHAR(250) PRIMARY KEY
    );
END

-- عبّي الجدول (بدون تكرار)
INSERT INTO dbo.DefaultProvisionMeds(MedName)
SELECT s.MedName
FROM #seed70 s
WHERE NOT EXISTS (SELECT 1 FROM dbo.DefaultProvisionMeds d WHERE d.MedName = s.MedName);

DROP TABLE #seed70;
GO

/* =========================================================
   2) إجراء: يجهّز الـ70 دواء للصيدلاني بكميات 10–100
   ========================================================= */
IF OBJECT_ID('dbo.sp_ProvisionDefaultMedsForPharmacist','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProvisionDefaultMedsForPharmacist;
GO
CREATE PROCEDURE dbo.sp_ProvisionDefaultMedsForPharmacist
    @PharmacistID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify pharmacist user
    IF NOT EXISTS (SELECT 1 FROM dbo.[users] WHERE id=@PharmacistID AND userRole='Pharmacist')
    BEGIN
        RAISERROR(N'User not found or not a Pharmacist.',16,1);
        RETURN;
    END

    ;WITH pool AS (
        SELECT m.MedicineID
        FROM dbo.Medicines m
        JOIN dbo.DefaultProvisionMeds d ON d.MedName = m.MedName
    )
    INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
    SELECT  @PharmacistID,
            p.MedicineID,
            CAST((ABS(CHECKSUM(NEWID(), p.MedicineID, @PharmacistID)) % 91) + 10 AS DECIMAL(10,2))
    FROM pool p
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.PharmacistMedicines pm
        WHERE pm.PharmacistID=@PharmacistID AND pm.MedicineID=p.MedicineID
    );

    -- إن كان عندك تريغرات لمزامنة جدول medic فمش لازم تنادي مزامنة يدوياً
    -- EXEC dbo.sp_SyncMedicFromInventory;
END
GO

/* =========================================================
   3) Trigger: أي صيدلاني جديد يأخذ الـ70 دواء تلقائيًا
   ========================================================= */
IF OBJECT_ID('dbo.tr_users_after_insert_provisionDefault','TR') IS NOT NULL
    DROP TRIGGER dbo.tr_users_after_insert_provisionDefault;
GO
CREATE TRIGGER dbo.tr_users_after_insert_provisionDefault
ON dbo.[users]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH newPh AS (
        SELECT id
        FROM inserted
        WHERE userRole='Pharmacist'
    ),
    pool AS (
        SELECT m.MedicineID
        FROM dbo.Medicines m
        JOIN dbo.DefaultProvisionMeds d ON d.MedName = m.MedName
    )
    INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
    SELECT  p.id,
            pool.MedicineID,
            CAST((ABS(CHECKSUM(NEWID(), pool.MedicineID, p.id)) % 91) + 10 AS DECIMAL(10,2))
    FROM newPh p
    CROSS JOIN pool
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.PharmacistMedicines pm
        WHERE pm.PharmacistID=p.id AND pm.MedicineID=pool.MedicineID
    );

    -- اختياري: EXEC dbo.sp_SyncMedicFromInventory;
END
GO




USE pharmacy;
GO

/* 1A) ضيف/ثبّت المواد الفعّالة اللي بتلزم أسماء الأدوية الظاهرة */
MERGE dbo.Ingredients AS t
USING (VALUES
 (N'Acyclovir'),
 (N'Allopurinol'),
 (N'Amoxicillin'),
 (N'Amlodipine'),
 (N'Aspirin'),
 (N'Atenolol'),
 (N'Atorvastatin'),
 (N'Azithromycin'),
 (N'Budesonide'),
 (N'Calcium'),
 (N'Cefalexin'),
 (N'Ceftriaxone'),
 (N'Cetirizine'),
 (N'Chlorhexidine'),
 (N'Ciprofloxacin'),
 (N'Clarithromycin'),
 (N'Clobetasol'),
 (N'Clotrimazole'),
 (N'Colchicine'),
 (N'Diazepam'),
 (N'Diclofenac'),
 (N'Domperidone'),
 (N'Doxycycline'),
 (N'Ferrous Sulfate'),
 (N'Fexofenadine'),
 (N'Fluconazole'),
 (N'Folic Acid'),
 (N'Furosemide'),
 (N'Gabapentin'),
 (N'Glimepiride'),
 (N'Hydrochlorothiazide'),
 (N'Hydrocortisone'),
 (N'Ibuprofen'),
 (N'Insulin Glargine'),
 (N'Insulin Regular'),
 (N'Isosorbide Mononitrate'),
 (N'Levothyroxine'),
 (N'Lisinopril'),
 (N'Loperamide'),
 (N'Loratadine'),
 (N'Losartan'),
 (N'Magnesium'),
 (N'Melatonin'),
 (N'Metformin'),
 (N'Metoclopramide'),
 (N'Metronidazole'),
 (N'Miconazole'),
 (N'Montelukast'),
 (N'Naproxen'),
 (N'Paracetamol'),
 (N'Povidone-Iodine'),
 (N'Ranitidine'),
 (N'Salbutamol'),
 (N'Sertraline'),
 (N'Simvastatin'),
 (N'Tramadol'),
 (N'Vitamin B Complex'),
 (N'Vitamin D3'),
 (N'Warfarin'),
 (N'Zinc')
) AS s(Name)
ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT(Name) VALUES(s.Name);
GO

/* 1B) اربط كل دواء في Medicines بمادته/مكوّنه */
-- ملاحظة: لو عندك أسماء مختلفة قليلاً، عدّلي شروط LIKE.
INSERT INTO dbo.MedicineIngredients(MedicineID, IngredientID)
SELECT m.MedicineID, i.IngredientID
FROM dbo.Medicines m
JOIN dbo.Ingredients i
  ON
     (m.MedName LIKE 'Acyclovir%'           AND i.Name=N'Acyclovir')
  OR (m.MedName LIKE 'Allopurinol%'         AND i.Name=N'Allopurinol')
  OR (m.MedName LIKE 'Amoxicillin%'         AND i.Name=N'Amoxicillin')
  OR (m.MedName LIKE 'Amlodipine%'          AND i.Name=N'Amlodipine')
  OR (m.MedName LIKE 'Aspirin%'             AND i.Name=N'Aspirin')
  OR (m.MedName LIKE 'Atenolol%'            AND i.Name=N'Atenolol')
  OR (m.MedName LIKE 'Atorvastatin%'        AND i.Name=N'Atorvastatin')
  OR (m.MedName LIKE 'Azithromycin%'        AND i.Name=N'Azithromycin')
  OR (m.MedName LIKE 'Budesonide%'          AND i.Name=N'Budesonide')
  OR (m.MedName LIKE 'Calcium%'             AND i.Name=N'Calcium')
  OR (m.MedName LIKE 'Cefalexin%'           AND i.Name=N'Cefalexin')
  OR (m.MedName LIKE 'Ceftriaxone%'         AND i.Name=N'Ceftriaxone')
  OR (m.MedName LIKE 'Cetirizine%'          AND i.Name=N'Cetirizine')
  OR (m.MedName LIKE 'Chlorhexidine%'       AND i.Name=N'Chlorhexidine')
  OR (m.MedName LIKE 'Ciprofloxacin%'       AND i.Name=N'Ciprofloxacin')
  OR (m.MedName LIKE 'Clarithromycin%'      AND i.Name=N'Clarithromycin')
  OR (m.MedName LIKE 'Clobetasol%'          AND i.Name=N'Clobetasol')
  OR (m.MedName LIKE 'Clotrimazole%'        AND i.Name=N'Clotrimazole')
  OR (m.MedName LIKE 'Colchicine%'          AND i.Name=N'Colchicine')
  OR (m.MedName LIKE 'Diazepam%'            AND i.Name=N'Diazepam')
  OR (m.MedName LIKE 'Diclofenac %'         AND i.Name=N'Diclofenac')
  OR (m.MedName LIKE 'Diclofenac%'          AND i.Name=N'Diclofenac')
  OR (m.MedName LIKE 'Domperidone%'         AND i.Name=N'Domperidone')
  OR (m.MedName LIKE 'Doxycycline%'         AND i.Name=N'Doxycycline')
  OR (m.MedName LIKE 'Ferrous Sulfate%'     AND i.Name=N'Ferrous Sulfate')
  OR (m.MedName LIKE 'Fexofenadine%'        AND i.Name=N'Fexofenadine')
  OR (m.MedName LIKE 'Fluconazole%'         AND i.Name=N'Fluconazole')
  OR (m.MedName LIKE 'Folic Acid%'          AND i.Name=N'Folic Acid')
  OR (m.MedName LIKE 'Furosemide%'          AND i.Name=N'Furosemide')
  OR (m.MedName LIKE 'Gabapentin%'          AND i.Name=N'Gabapentin')
  OR (m.MedName LIKE 'Glimepiride%'         AND i.Name=N'Glimepiride')
  OR (m.MedName LIKE 'Hydrochlorothiazide%' AND i.Name=N'Hydrochlorothiazide')
  OR (m.MedName LIKE 'Hydrocortisone%'      AND i.Name=N'Hydrocortisone')
  OR (m.MedName LIKE 'Ibuprofen%'           AND i.Name=N'Ibuprofen')
  OR (m.MedName LIKE 'Insulin Glargine%'    AND i.Name=N'Insulin Glargine')
  OR (m.MedName LIKE 'Insulin Regular%'     AND i.Name=N'Insulin Regular')
  OR (m.MedName LIKE 'Isosorbide Mono%'     AND i.Name=N'Isosorbide Mononitrate')
  OR (m.MedName LIKE 'Levothyroxine%'       AND i.Name=N'Levothyroxine')
  OR (m.MedName LIKE 'Lisinopril%'          AND i.Name=N'Lisinopril')
  OR (m.MedName LIKE 'Loperamide%'          AND i.Name=N'Loperamide')
  OR (m.MedName LIKE 'Loratadine%'          AND i.Name=N'Loratadine')
  OR (m.MedName LIKE 'Losartan%'            AND i.Name=N'Losartan')
  OR (m.MedName LIKE 'Magnesium%'           AND i.Name=N'Magnesium')
  OR (m.MedName LIKE 'Melatonin%'           AND i.Name=N'Melatonin')
  OR (m.MedName LIKE 'Metformin%'           AND i.Name=N'Metformin')
  OR (m.MedName LIKE 'Metoclopramide%'      AND i.Name=N'Metoclopramide')
  OR (m.MedName LIKE 'Metronidazole%'       AND i.Name=N'Metronidazole')
  OR (m.MedName LIKE 'Miconazole%'          AND i.Name=N'Miconazole')
  OR (m.MedName LIKE 'Montelukast%'         AND i.Name=N'Montelukast')
  OR (m.MedName LIKE 'Naproxen%'            AND i.Name=N'Naproxen')
  OR (m.MedName LIKE 'Paracetamol%'         AND i.Name=N'Paracetamol')
  OR (m.MedName LIKE 'Povidone-Iodine%'     AND i.Name=N'Povidone-Iodine')
  OR (m.MedName LIKE 'Ranitidine%'          AND i.Name=N'Ranitidine')
  OR (m.MedName LIKE 'Salbutamol%'          AND i.Name=N'Salbutamol')
  OR (m.MedName LIKE 'Sertraline%'          AND i.Name=N'Sertraline')
  OR (m.MedName LIKE 'Simvastatin%'         AND i.Name=N'Simvastatin')
  OR (m.MedName LIKE 'Tramadol%'            AND i.Name=N'Tramadol')
  OR (m.MedName LIKE 'Vitamin B Complex%'   AND i.Name=N'Vitamin B Complex')
  OR (m.MedName LIKE 'Vitamin D3%'          AND i.Name=N'Vitamin D3')
  OR (m.MedName LIKE 'Warfarin%'            AND i.Name=N'Warfarin')
  OR (m.MedName LIKE 'Zinc%'                AND i.Name=N'Zinc')
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.MedicineIngredients mi
    WHERE mi.MedicineID=m.MedicineID AND mi.IngredientID=i.IngredientID
);
GO






USE pharmacy;
GO

SELECT 
    c.CustomerID,
    c.Username,
    i.IngredientID,
    i.Name AS Ingredient,
    ca.Note
FROM dbo.CustomerAllergies AS ca
JOIN dbo.Customers AS c ON c.CustomerID = ca.CustomerID
JOIN dbo.Ingredients AS i ON i.IngredientID = ca.IngredientID
WHERE c.Username = 'sarah';








USE pharmacy;
GO

IF OBJECT_ID('dbo.sp_CheckPrescriptionSafety','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CheckPrescriptionSafety;
GO

CREATE PROCEDURE dbo.sp_CheckPrescriptionSafety
  @CustomerID INT,
  @MedicineID INT
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH NewMedIng AS (
    SELECT mi.IngredientID
    FROM dbo.MedicineIngredients mi
    WHERE mi.MedicineID = @MedicineID
  ),
  ActiveCustMeds AS (
    SELECT cm.MedicineID
    FROM dbo.CustomerMedicines cm
    WHERE cm.CustomerID = @CustomerID
      AND (cm.StartDate IS NULL OR cm.StartDate <= CAST(GETDATE() AS DATE))
      AND (cm.EndDate   IS NULL OR cm.EndDate   >= CAST(GETDATE() AS DATE))
  ),
  ActiveIng AS (
    SELECT DISTINCT mi.IngredientID
    FROM ActiveCustMeds acm
    JOIN dbo.MedicineIngredients mi ON mi.MedicineID = acm.MedicineID
  )

  -- Allergies (ENGLISH NOTE)
  SELECT 'Allergy' AS IssueType,
         i.Name    AS Item1,
         NULL      AS Item2,
         'Major'   AS Severity,
         N'Patient has an allergy to this ingredient.' AS Note
  FROM dbo.CustomerAllergies ca
  JOIN dbo.Ingredients i ON i.IngredientID = ca.IngredientID
  WHERE ca.CustomerID = @CustomerID
    AND EXISTS (SELECT 1 FROM NewMedIng n WHERE n.IngredientID = ca.IngredientID)

  UNION ALL

  -- Interactions (uses whatever is in IngredientInteractions.Note)
  SELECT 'Interaction' AS IssueType,
         i1.Name AS Item1,
         i2.Name AS Item2,
         ii.Severity,
         ii.Note
  FROM NewMedIng n
  JOIN ActiveIng ai ON 1=1
  JOIN dbo.IngredientInteractions ii
       ON (ii.IngredientAID = n.IngredientID AND ii.IngredientBID = ai.IngredientID)
       OR (ii.IngredientBID = n.IngredientID AND ii.IngredientAID = ai.IngredientID)
  JOIN dbo.Ingredients i1 ON i1.IngredientID = n.IngredientID
  JOIN dbo.Ingredients i2 ON i2.IngredientID = ai.IngredientID;
END
GO




-- Amoxicillin + Allopurinol  (Moderate)
UPDATE dbo.IngredientInteractions
SET Note = N'May increase risk of rash — monitor the patient.'
WHERE Note LIKE N'%الطفح%' OR
      (IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Allopurinol'))
   OR
      (IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Allopurinol'));

-- Amoxicillin + Warfarin (Major)
UPDATE dbo.IngredientInteractions
SET Note = N'Warfarin effect/INR may increase — avoid or monitor INR closely.'
WHERE Note LIKE N'%INR%' OR
      (IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Warfarin'))
   OR
      (IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Warfarin'));

-- Amoxicillin + Vitamin D (Minor, demo)
UPDATE dbo.IngredientInteractions
SET Note = N'No clinically significant interaction expected (demo).'
WHERE Note LIKE N'%مثال تعليمي%' OR
      (IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Vitamin D'))
   OR
      (IngredientBID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin')
   AND IngredientAID = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Vitamin D'));



INSERT INTO dbo.CustomerAllergies (CustomerID, IngredientID)
VALUES (
    (SELECT CustomerID 
     FROM dbo.Customers 
     WHERE Username = 'sarah'),
    (SELECT IngredientID 
     FROM dbo.Ingredients 
     WHERE Name = N'Aspirin')
);

