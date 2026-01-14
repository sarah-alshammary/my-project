create database pharmacy

create table users(
id int identity(1,1) primary key,
userRole varchar(50) not null,
name varchar(250) not null,
dob varchar(250)not null,
mobile bigint not null,
email varchar(250)not null,
username varchar(250) unique not null,
pass varchar(250)not null,
)
INSERT INTO users(userRole, name, dob, mobile, email, username, pass)VALUES 
('Pharmacist', 'kumar', 'Thursday, October 1, 2020', 123456, 'btechdays.care@gmail.com', 'kumar', 'kumar'),
('Administrator', 'BTech Days', 'Thursday, July 18, 1991', 5655652323, 'btechdays.care@gmail.com', 'btechdays', 'btechdays'),
('Pharmacist', 'Rohan', 'Wednesday, June 14, 1995', 1234567890, 'rohan@gmail.com', 'rohan', 'rohan'),
('Administrator', 'gaurav', 'Thursday, July 13, 1995', 123456, 'gaurav@gmail.com', 'gaurav', 'gaurav');



select*from users 




-- Customers table
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    Username   VARCHAR(250) UNIQUE NOT NULL,
    Email      VARCHAR(250) NOT NULL,
    Mobile     BIGINT NOT NULL,
    Password   VARCHAR(250) NOT NULL
);




-- Medicines table
CREATE TABLE Medicines (
    MedicineID INT IDENTITY(1,1) PRIMARY KEY,
    MedName    VARCHAR(250) UNIQUE NOT NULL,
    Price      DECIMAL(10,2) NOT NULL,
    [Description] NVARCHAR(500) NULL
);

-- Relation table between Customers and Medicines
CREATE TABLE CustomerMedicines (
    CustomerMedicineID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID  INT NOT NULL,
    MedicineID  INT NOT NULL,
    TimesPerDay TINYINT NOT NULL,
    UnitsPerDose DECIMAL(10,2) NOT NULL,
    StartDate   DATE NULL,
    EndDate     DATE NULL,
    Notes       NVARCHAR(300) NULL,
    CONSTRAINT FK_CustomerMedicines_Customers FOREIGN KEY (CustomerID)
        REFERENCES Customers(CustomerID),
    CONSTRAINT FK_CustomerMedicines_Medicines FOREIGN KEY (MedicineID)
        REFERENCES Medicines(MedicineID)
);


-- Add customers
INSERT INTO Customers (Username, Email, Mobile, Password)
VALUES ('yaqeen', 'yaqeen@mail.com', 777777777, 'xxxx'),
       ('sarah',  'sarah@mail.com',  888888888, 'yyyy');

-- Add medicines
INSERT INTO Medicines (MedName, Price, [Description])
VALUES ('Paracetamol 500mg', 1.20, N'Pain reliever and fever reducer'),
       ('Amoxicillin 500mg', 2.80, N'Antibiotic'),
       ('Vitamin D 1000 IU', 3.50, N'Dietary supplement');

INSERT INTO CustomerMedicines (CustomerID, MedicineID, TimesPerDay, UnitsPerDose, StartDate)
SELECT c.CustomerID, m.MedicineID, 3, 1, GETDATE()
FROM Customers c
JOIN Medicines m ON m.MedName = 'Paracetamol 500mg'
WHERE c.Username = 'yaqeen';

SELECT 
    m.MedicineID,
    m.MedName,
    cm.TimesPerDay,
    cm.UnitsPerDose,
    m.Price,
    m.[Description]
FROM CustomerMedicines cm
JOIN Medicines m ON m.MedicineID = cm.MedicineID
WHERE cm.CustomerID = (
    SELECT CustomerID FROM Customers WHERE Username = 'yaqeen'
);
SELECT * FROM Customers;
SELECT * FROM Medicines;
SELECT * FROM CustomerMedicines;

-- Add a column for how many days the treatment lasts
ALTER TABLE CustomerMedicines
ADD DurationDays INT NULL;

-- Fill existing rows with a default value (7 days)
UPDATE CustomerMedicines
SET DurationDays = 7
WHERE DurationDays IS NULL;

-- Make DurationDays required (NOT NULL) and set a default for new rows
ALTER TABLE CustomerMedicines
ADD CONSTRAINT DF_CustomerMedicines_DurationDays DEFAULT(7) FOR DurationDays;

ALTER TABLE CustomerMedicines
ALTER COLUMN DurationDays INT NOT NULL;

-- Make sure StartDate has a value (if it was NULL before)
UPDATE CustomerMedicines
SET StartDate = CAST(GETDATE() AS DATE)
WHERE StartDate IS NULL;

-- Set default StartDate = today's date for new inserts
ALTER TABLE CustomerMedicines
ADD CONSTRAINT DF_CustomerMedicines_StartDate DEFAULT(CAST(GETDATE() AS DATE)) FOR StartDate;

-- Drop old EndDate column if it exists
ALTER TABLE CustomerMedicines DROP COLUMN EndDate;

-- Add a computed EndDate (calculated automatically)
ALTER TABLE CustomerMedicines
ADD EndDate AS (
    CASE 
        WHEN StartDate IS NULL OR DurationDays IS NULL THEN NULL
        ELSE DATEADD(DAY, DurationDays - 1, StartDate)
    END
) PERSISTED;

-- Check result
SELECT * FROM CustomerMedicines;
ALTER TABLE CustomerMedicines
DROP COLUMN Notes;

INSERT INTO CustomerMedicines (CustomerID, MedicineID, TimesPerDay, UnitsPerDose, StartDate, DurationDays)
SELECT c.CustomerID, m.MedicineID, 3, 1, GETDATE(), 7
FROM Customers c
JOIN Medicines m ON m.MedName IN ('Paracetamol 500mg', 'Vitamin D 1000 IU')
WHERE c.Username = 'yaqeen';

INSERT INTO CustomerMedicines (CustomerID, MedicineID, TimesPerDay, UnitsPerDose, StartDate, DurationDays)
SELECT c.CustomerID, m.MedicineID, 2, 1, GETDATE(), 5
FROM Customers c
JOIN Medicines m ON m.MedName = 'Amoxicillin 500mg'
WHERE c.Username = 'sarah';

INSERT INTO CustomerMedicines (CustomerID, MedicineID, TimesPerDay, UnitsPerDose, StartDate, DurationDays)
SELECT c.CustomerID, m.MedicineID, 1, 0.5, GETDATE(), 10
FROM Customers c
JOIN Medicines m ON m.MedName = 'Paracetamol 500mg'
WHERE c.Username = 'lojain';

SELECT 
    c.Username,
    m.MedName,
    cm.TimesPerDay,
    cm.UnitsPerDose,
    cm.StartDate,
    cm.DurationDays,
    cm.EndDate
FROM CustomerMedicines cm
JOIN Customers c ON cm.CustomerID = c.CustomerID
JOIN Medicines m ON cm.MedicineID = m.MedicineID
ORDER BY c.Username;

CREATE TABLE Pharmacists
(
    PharmacistID INT IDENTITY(1,1) PRIMARY KEY,
    Username     VARCHAR(250) UNIQUE NOT NULL,
    Email        VARCHAR(250) UNIQUE NOT NULL,
    Password     VARCHAR(250) NOT NULL
);


ALTER TABLE Customers
ADD PharmacistID INT NULL;

ALTER TABLE Customers
ADD CONSTRAINT FK_Customers_Pharmacists
    FOREIGN KEY (PharmacistID) REFERENCES Pharmacists(PharmacistID);
INSERT INTO Pharmacists (Username, Email, Password)
VALUES ('ph1', 'ph1@mail.com', 'p1'),
       ('ph2', 'ph2@mail.com', 'p2');

-- عيّني كل مريض لصيدلاني
UPDATE Customers SET PharmacistID = 1 WHERE Username = 'yaqeen';
UPDATE Customers SET PharmacistID = 1 WHERE Username = 'sarah';
UPDATE Customers SET PharmacistID = 2 WHERE Username = 'lojain';

-- (اختياري) منع عدم التعيين:
-- بإمكانك لاحقًا جعل PharmacistID NOT NULL إذا بتضمني تعيين الجميع
-- ALTER TABLE Customers ALTER COLUMN PharmacistID INT NOT NULL;


-- جدول مخزون الصيادلة
CREATE TABLE PharmacistMedicines
(
    ID            INT IDENTITY(1,1) PRIMARY KEY,
    PharmacistID  INT NOT NULL,
    MedicineID    INT NOT NULL,
    QtyAvailable  DECIMAL(10,2) NOT NULL,  -- خليه عشري لو عندك أنصاف حبات/شراب

    CONSTRAINT FK_PM_Pharmacists FOREIGN KEY (PharmacistID) REFERENCES Pharmacists(PharmacistID),
    CONSTRAINT FK_PM_Medicines    FOREIGN KEY (MedicineID)   REFERENCES Medicines(MedicineID),

    -- منع تكرار نفس الدواء لنفس الصيدلاني
    CONSTRAINT UX_PM UNIQUE(PharmacistID, MedicineID)
);

-- ph1 عنده 3 أدوية
INSERT INTO PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT 1, MedicineID, 50 FROM Medicines WHERE MedName IN ('Paracetamol 500mg', 'Amoxicillin 500mg', 'Vitamin D 1000 IU');

-- ph2 عنده نوعين فقط
INSERT INTO PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT 2, MedicineID, 30 FROM Medicines WHERE MedName IN ('Paracetamol 500mg', 'Vitamin D 1000 IU');


-- Pharmacists
IF OBJECT_ID('dbo.Pharmacists','U') IS NULL
BEGIN
  CREATE TABLE dbo.Pharmacists
  (
      PharmacistID INT IDENTITY(1,1) PRIMARY KEY,
      Username     VARCHAR(250) UNIQUE NOT NULL,
      Email        VARCHAR(250) UNIQUE NOT NULL,
      [Password]   VARCHAR(250) NOT NULL
  );
END
GO

-- Customers (موجود عندك؛ نضيف العمود لو مش موجود)
IF COL_LENGTH('dbo.Customers','PharmacistID') IS NULL
BEGIN
  ALTER TABLE dbo.Customers ADD PharmacistID INT NULL;
  ALTER TABLE dbo.Customers ADD CONSTRAINT FK_Customers_Pharmacists
    FOREIGN KEY (PharmacistID) REFERENCES dbo.Pharmacists(PharmacistID);
END
GO

-- بيانات تجريبية للصيادلة (عدّلي لو عندك بيانات)
IF NOT EXISTS (SELECT 1 FROM dbo.Pharmacists)
BEGIN
  INSERT INTO dbo.Pharmacists(Username,Email,[Password])
  VALUES ('ph1','ph1@mail.com','p1'),('ph2','ph2@mail.com','p2');
END
GO

-- تعيين كل مريض لصيدلاني (عدّلي حسب ما بدك)
UPDATE dbo.Customers SET PharmacistID = 1 WHERE Username IN ('yaqeen','sarah');
UPDATE dbo.Customers SET PharmacistID = 2 WHERE Username = 'lojain';
GO

IF OBJECT_ID('dbo.PharmacistMedicines','U') IS NULL
BEGIN
  CREATE TABLE dbo.PharmacistMedicines
  (
      ID            INT IDENTITY(1,1) PRIMARY KEY,
      PharmacistID  INT NOT NULL,
      MedicineID    INT NOT NULL,
      QtyAvailable  DECIMAL(10,2) NOT NULL,
      CONSTRAINT FK_PM_Pharmacists FOREIGN KEY (PharmacistID) REFERENCES dbo.Pharmacists(PharmacistID),
      CONSTRAINT FK_PM_Medicines    FOREIGN KEY (MedicineID)   REFERENCES dbo.Medicines(MedicineID),
      CONSTRAINT UX_PM UNIQUE(PharmacistID, MedicineID)
  );
END
GO

-- تعبئة مخزون مبدئي (مثال)
IF NOT EXISTS (SELECT 1 FROM dbo.PharmacistMedicines WHERE PharmacistID=1)
BEGIN
  INSERT INTO dbo.PharmacistMedicines(PharmacistID,MedicineID,QtyAvailable)
  SELECT 1, MedicineID, 50 FROM dbo.Medicines WHERE MedName IN ('Paracetamol 500mg','Amoxicillin 500mg','Vitamin D 1000 IU');
END
IF NOT EXISTS (SELECT 1 FROM dbo.PharmacistMedicines WHERE PharmacistID=2)
BEGIN
  INSERT INTO dbo.PharmacistMedicines(PharmacistID,MedicineID,QtyAvailable)
  SELECT 2, MedicineID, 30 FROM dbo.Medicines WHERE MedName IN ('Paracetamol 500mg','Vitamin D 1000 IU');
END
GO


-- أضيفي العمود لو مش موجود
IF COL_LENGTH('dbo.CustomerMedicines','PrescribedByPharmacistID') IS NULL
BEGIN
  ALTER TABLE dbo.CustomerMedicines
  ADD PrescribedByPharmacistID INT NULL;
END
GO

-- تعبئة من صيدلاني المريض
UPDATE cm
SET cm.PrescribedByPharmacistID = c.PharmacistID
FROM dbo.CustomerMedicines cm
JOIN dbo.Customers c ON c.CustomerID = cm.CustomerID
WHERE cm.PrescribedByPharmacistID IS NULL;
GO

-- تأكدي ما ظل NULL (لو ظلّ: لازم تعيّني PharmacistID للمرضى أولاً)
SELECT COUNT(*) AS NullCount
FROM dbo.CustomerMedicines
WHERE PrescribedByPharmacistID IS NULL;
GO

-- جعلها NOT NULL + مفتاح أجنبي
ALTER TABLE dbo.CustomerMedicines
ALTER COLUMN PrescribedByPharmacistID INT NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_CM_Pharmacists')
BEGIN
  ALTER TABLE dbo.CustomerMedicines
  ADD CONSTRAINT FK_CM_Pharmacists
    FOREIGN KEY (PrescribedByPharmacistID) REFERENCES dbo.Pharmacists(PharmacistID);
END
GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Customers_Pharmacist')
  CREATE INDEX IX_Customers_Pharmacist ON dbo.Customers(PharmacistID);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_PM_Pharmacist')
  CREATE INDEX IX_PM_Pharmacist ON dbo.PharmacistMedicines(PharmacistID);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_CM_Customer')
  CREATE INDEX IX_CM_Customer ON dbo.CustomerMedicines(CustomerID);
GO



-- احذفي السطر السابق اللي فيه CREATE OR ALTER
-- وخذي هذا الكود:

IF OBJECT_ID('dbo.sp_GetPharmacistCustomers', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPharmacistCustomers;
GO

CREATE PROCEDURE dbo.sp_GetPharmacistCustomers
    @PharmacistID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CustomerID, Username, Email, Mobile
    FROM dbo.Customers
    WHERE PharmacistID = @PharmacistID
    ORDER BY Username;
END
GO

IF OBJECT_ID('dbo.sp_PrescribeMedicine','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_PrescribeMedicine;
GO

CREATE PROCEDURE dbo.sp_PrescribeMedicine
    @PharmacistID  INT,
    @CustomerID    INT,
    @MedicineID    INT,
    @TimesPerDay   TINYINT,
    @UnitsPerDose  DECIMAL(10,2),
    @DurationDays  INT,
    @StartDate     DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartDate IS NULL 
        SET @StartDate = CAST(GETDATE() AS DATE);

    -- المريض لازم يكون تابعًا للصيدلاني
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Customers 
        WHERE CustomerID = @CustomerID AND PharmacistID = @PharmacistID
    )
    BEGIN
        RAISERROR(N'هذا المريض ليس تابعًا لهذا الصيدلاني.', 16, 1);
        RETURN;
    END

    DECLARE @ToDeduct DECIMAL(18,2);
    SET @ToDeduct = CAST(@TimesPerDay AS DECIMAL(18,2)) * @UnitsPerDose * @DurationDays;

    BEGIN TRY
        BEGIN TRAN;

        -- خصم من مخزون الصيدلاني (ويتحقق من الكفاية)
        UPDATE dbo.PharmacistMedicines
           SET QtyAvailable = QtyAvailable - @ToDeduct
         WHERE PharmacistID = @PharmacistID
           AND MedicineID    = @MedicineID
           AND QtyAvailable >= @ToDeduct;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR(N'الدواء غير متوفر أو الكمية غير كافية لدى هذا الصيدلاني.', 16, 1);
            ROLLBACK TRAN;
            RETURN;
        END

        -- حفظ الوصفة (CustomerMedicines = جدول الوصفات)
        INSERT INTO dbo.CustomerMedicines
            (CustomerID, MedicineID, TimesPerDay, UnitsPerDose, StartDate, DurationDays, PrescribedByPharmacistID)
        VALUES
            (@CustomerID, @MedicineID, @TimesPerDay, @UnitsPerDose, @StartDate, @DurationDays, @PharmacistID);

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END
GO



IF OBJECT_ID('dbo.sp_GetPharmacistCustomers','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPharmacistCustomers;
GO

CREATE PROCEDURE dbo.sp_GetPharmacistCustomers
    @PharmacistID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CustomerID, Username, Email, Mobile
    FROM dbo.Customers
    WHERE PharmacistID = @PharmacistID
    ORDER BY Username;
END
GO

IF OBJECT_ID('dbo.sp_GetPharmacistInventory','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPharmacistInventory;
GO

CREATE PROCEDURE dbo.sp_GetPharmacistInventory
    @PharmacistID INT,
    @q NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pm.ID AS InventoryID,
            m.MedicineID,
            m.MedName,
            m.[Description],
            m.Price,
            pm.QtyAvailable
    FROM dbo.PharmacistMedicines pm
    JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
    WHERE pm.PharmacistID = @PharmacistID
      AND (@q IS NULL OR m.MedName LIKE '%' + @q + '%')
    ORDER BY m.MedName;
END
GO




IF OBJECT_ID('dbo.sp_GetCustomerPrescriptions','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetCustomerPrescriptions;
GO

CREATE PROCEDURE dbo.sp_GetCustomerPrescriptions
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  cm.CustomerMedicineID,
            m.MedName,
            cm.TimesPerDay,
            cm.UnitsPerDose,
            cm.StartDate,
            cm.DurationDays,
            cm.EndDate,
            p.Username AS PrescribedBy
    FROM dbo.CustomerMedicines cm
    JOIN dbo.Medicines    m ON m.MedicineID = cm.MedicineID
    JOIN dbo.Pharmacists  p ON p.PharmacistID = cm.PrescribedByPharmacistID
    WHERE cm.CustomerID = @CustomerID
    ORDER BY cm.StartDate DESC, cm.CustomerMedicineID DESC;
END
GO


IF OBJECT_ID('dbo.Ingredients','U') IS NULL
BEGIN
  CREATE TABLE dbo.Ingredients(
    IngredientID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(200) UNIQUE NOT NULL
  );
END
GO

IF OBJECT_ID('dbo.MedicineIngredients','U') IS NULL
BEGIN
  CREATE TABLE dbo.MedicineIngredients(
    MedicineID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Medicines(MedicineID),
    IngredientID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
    CONSTRAINT PK_MedicineIngredients PRIMARY KEY (MedicineID, IngredientID)
  );
END
GO


IF OBJECT_ID('dbo.IngredientInteractions','U') IS NULL
BEGIN
  CREATE TABLE dbo.IngredientInteractions(
    InteractionID INT IDENTITY(1,1) PRIMARY KEY,
    IngredientAID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
    IngredientBID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
    Severity VARCHAR(20) NOT NULL,      -- Minor / Moderate / Major
    Note NVARCHAR(500) NULL,
    CONSTRAINT UX_Interaction UNIQUE(IngredientAID, IngredientBID)
  );
END
GO



IF OBJECT_ID('dbo.CustomerAllergies','U') IS NULL
BEGIN
  CREATE TABLE dbo.CustomerAllergies(
    CustomerID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Customers(CustomerID),
    IngredientID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
    Note NVARCHAR(300) NULL,
    CONSTRAINT PK_CustomerAllergies PRIMARY KEY (CustomerID, IngredientID)
  );
END
GO


MERGE dbo.Ingredients AS t
USING (VALUES (N'Paracetamol'),(N'Amoxicillin'),(N'Vitamin D'),(N'Warfarin'),(N'Allopurinol')) AS s(Name)
ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT(Name) VALUES(s.Name);
GO

-- اربطي الأدوية الحالية بالمادة المناسبة حسب الاسم
INSERT INTO dbo.MedicineIngredients(MedicineID, IngredientID)
SELECT m.MedicineID, i.IngredientID
FROM dbo.Medicines m
JOIN dbo.Ingredients i ON
     (m.MedName LIKE 'Paracetamol%' AND i.Name=N'Paracetamol')
  OR (m.MedName LIKE 'Amoxicillin%' AND i.Name=N'Amoxicillin')
  OR (m.MedName LIKE 'Vitamin D%'   AND i.Name=N'Vitamin D')
WHERE NOT EXISTS (
  SELECT 1 FROM dbo.MedicineIngredients mi
  WHERE mi.MedicineID=m.MedicineID AND mi.IngredientID=i.IngredientID
);
GO


DECLARE @Amox INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin');
DECLARE @VitD INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Vitamin D');
DECLARE @Warf INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Warfarin');
DECLARE @Allo INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Allopurinol');

-- أمثلة:
IF @Amox IS NOT NULL AND @Allo IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@Allo)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@Allo,'Moderate',N'قد يزيد الطفح الجلدي—راقِب المريض');

IF @Amox IS NOT NULL AND @Warf IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@Warf)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@Warf,'Major',N'يزيد INR مع الوارفارين—تجنب أو راقب INR عن قرب');

IF @Amox IS NOT NULL AND @VitD IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@VitD)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@VitD,'Minor',N'لا يُتوقع تأثير مهم—مثال تعليمي');
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
  -- حساسيّات
  SELECT 'Allergy' AS IssueType,
         i.Name    AS Item1,
         NULL      AS Item2,
         'Major'   AS Severity,
         N'حساسية لدى المريض لهذه المادة' AS Note
  FROM dbo.CustomerAllergies ca
  JOIN dbo.Ingredients i ON i.IngredientID = ca.IngredientID
  WHERE ca.CustomerID = @CustomerID
    AND EXISTS (SELECT 1 FROM NewMedIng n WHERE n.IngredientID = ca.IngredientID)

  UNION ALL
  -- تداخلات
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


-- مثال تعبئة سريعة للصيدلاني 1
INSERT INTO PharmacistMedicines(PharmacistID,MedicineID,QtyAvailable)
SELECT 1, MedicineID, 50 FROM Medicines
WHERE NOT EXISTS(
  SELECT 1 FROM PharmacistMedicines pm 
  WHERE pm.PharmacistID=1 AND pm.MedicineID=Medicines.MedicineID
);




SELECT COUNT(*) AS MedicinesCount FROM Medicines;
SELECT TOP 10 * FROM Medicines;

SELECT COUNT(*) AS RowsForPh1 FROM PharmacistMedicines WHERE PharmacistID = 1;
SELECT TOP 50 * 
FROM PharmacistMedicines pm
JOIN Medicines m ON m.MedicineID = pm.MedicineID
WHERE pm.PharmacistID = 1
ORDER BY m.MedName;


INSERT INTO PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT 1, m.MedicineID, 50
FROM Medicines m
WHERE NOT EXISTS (
  SELECT 1 FROM PharmacistMedicines pm 
  WHERE pm.PharmacistID = 1 AND pm.MedicineID = m.MedicineID
);


UPDATE PharmacistMedicines
SET QtyAvailable = QtyAvailable + 50
WHERE PharmacistID = 1;



INSERT INTO PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT 2, m.MedicineID, 30
FROM Medicines m
WHERE NOT EXISTS (
  SELECT 1 FROM PharmacistMedicines pm 
  WHERE pm.PharmacistID = 2 AND pm.MedicineID = m.MedicineID
);

SELECT p.Username, m.MedName, pm.QtyAvailable
FROM PharmacistMedicines pm
JOIN Pharmacists p ON p.PharmacistID = pm.PharmacistID
JOIN Medicines   m ON m.MedicineID = pm.MedicineID
ORDER BY p.Username, m.MedName;





-- احذف القيد القديم (لو موجود)
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Customers_Pharmacists')
BEGIN
    ALTER TABLE dbo.Customers DROP CONSTRAINT FK_Customers_Pharmacists;
END
GO

-- اجعلي Customers.PharmacistID يشير إلى users.id
ALTER TABLE dbo.Customers
WITH CHECK ADD CONSTRAINT FK_Customers_Users
FOREIGN KEY (PharmacistID) REFERENCES dbo.users(id);
GO


-- احذف القيد القديم (لو موجود)
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CM_Pharmacists')
BEGIN
    ALTER TABLE dbo.CustomerMedicines DROP CONSTRAINT FK_CM_Pharmacists;
END
GO

-- اربط على users.id
ALTER TABLE dbo.CustomerMedicines
WITH CHECK ADD CONSTRAINT FK_CM_Users
FOREIGN KEY (PrescribedByPharmacistID) REFERENCES dbo.users(id);
GO



-- لو في قيد قديم بإسم FK_PM_Pharmacists احذفيه
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PM_Pharmacists')
BEGIN
    ALTER TABLE dbo.PharmacistMedicines DROP CONSTRAINT FK_PM_Pharmacists;
END
GO

-- اربط على users.id
ALTER TABLE dbo.PharmacistMedicines
WITH CHECK ADD CONSTRAINT FK_PM_Users
FOREIGN KEY (PharmacistID) REFERENCES dbo.users(id);
GO

IF OBJECT_ID('dbo.sp_GetPharmacistCustomers','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPharmacistCustomers;
GO
CREATE PROCEDURE dbo.sp_GetPharmacistCustomers
    @PharmacistID INT
AS
BEGIN
    SET NOCOUNT ON;
    -- PharmacistID هو users.id للصيدلاني
    SELECT CustomerID, Username, Email, Mobile
    FROM dbo.Customers
    WHERE PharmacistID = @PharmacistID
    ORDER BY Username;
END
GO


IF OBJECT_ID('dbo.sp_GetPharmacistInventory','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetPharmacistInventory;
GO
CREATE PROCEDURE dbo.sp_GetPharmacistInventory
    @PharmacistID INT,
    @q NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT pm.ID AS InventoryID,
           m.MedicineID,
           m.MedName,
           m.[Description],
           m.Price,
           pm.QtyAvailable
    FROM dbo.PharmacistMedicines pm
    JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
    WHERE pm.PharmacistID = @PharmacistID
      AND (@q IS NULL OR m.MedName LIKE '%' + @q + '%')
    ORDER BY m.MedName;
END
GO


IF OBJECT_ID('dbo.sp_GetCustomerPrescriptions','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetCustomerPrescriptions;
GO
CREATE PROCEDURE dbo.sp_GetCustomerPrescriptions
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  cm.CustomerMedicineID,
            m.MedName,
            cm.TimesPerDay,
            cm.UnitsPerDose,
            cm.StartDate,
            cm.DurationDays,
            cm.EndDate,
            u.username AS PrescribedBy
    FROM dbo.CustomerMedicines cm
    JOIN dbo.Medicines m ON m.MedicineID = cm.MedicineID
    JOIN dbo.users u ON u.id = cm.PrescribedByPharmacistID
    WHERE cm.CustomerID = @CustomerID
    ORDER BY cm.StartDate DESC, cm.CustomerMedicineID DESC;
END
GO


-- شوفي ID تبعه
SELECT id, username FROM dbo.users WHERE userRole='Pharmacist';

-- عبّي لكل دواء كمية للصيدلاني المطلوب (مثلاً id=1)
INSERT INTO PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT 1, m.MedicineID, 50
FROM Medicines m
WHERE NOT EXISTS (
  SELECT 1 FROM PharmacistMedicines pm 
  WHERE pm.PharmacistID = 1 AND pm.MedicineID = m.MedicineID
);


SELECT u.id AS PharmacistID,
       u.username AS Pharmacist,
       COUNT(c.CustomerID) AS PatientsCount
FROM dbo.users u
LEFT JOIN dbo.Customers c ON c.PharmacistID = u.id
WHERE u.userRole='Pharmacist'
GROUP BY u.id, u.username
ORDER BY PatientsCount DESC, u.username;

select * from Customers


SELECT u.id AS PharmacistID,
       u.username AS Pharmacist,
       COUNT(c.CustomerID) AS PatientsCount
FROM dbo.users u
LEFT JOIN dbo.Customers c ON c.PharmacistID = u.id
WHERE u.userRole='Pharmacist'
GROUP BY u.id, u.username
ORDER BY PatientsCount DESC, u.username;





/* === 0) Safety: use the right DB === */
IF DB_ID('pharmacy') IS NOT NULL
    USE pharmacy;
GO

/* === 1) Add a pool of medicines if missing (keeps your originals) === */
;WITH meds(name, price, descr) AS (
    SELECT 'Ibuprofen 200mg',        1.10, N'NSAID for pain/fever' UNION ALL
    SELECT 'Cetirizine 10mg',        0.90, N'Antihistamine'        UNION ALL
    SELECT 'Aspirin 81mg',           0.50, N'Low-dose antiplatelet' UNION ALL
    SELECT 'Metformin 500mg',        2.20, N'Antidiabetic'         UNION ALL
    SELECT 'Amlodipine 5mg',         1.95, N'Calcium channel blocker' UNION ALL
    SELECT 'Atorvastatin 20mg',      2.40, N'Statin'               UNION ALL
    SELECT 'Losartan 50mg',          1.85, N'ARB'                  UNION ALL
    SELECT 'Omeprazole 20mg',        1.30, N'PPI'                  UNION ALL
    SELECT 'Azithromycin 500mg',     3.20, N'Antibiotic'           UNION ALL
    SELECT 'Doxycycline 100mg',      2.60, N'Antibiotic'           UNION ALL
    SELECT 'Hydrochlorothiazide 25mg',0.80, N'Thiazide diuretic'   UNION ALL
    SELECT 'Levothyroxine 50mcg',    1.70, N'Thyroid hormone'      UNION ALL
    SELECT 'Salbutamol Inhaler',     4.90, N'Bronchodilator'       UNION ALL
    SELECT 'Insulin Glargine 100U', 12.00, N'Basal insulin'        UNION ALL
    SELECT 'Clopidogrel 75mg',       2.10, N'Antiplatelet'         UNION ALL
    SELECT 'Loratadine 10mg',        0.85, N'Antihistamine'        UNION ALL
    SELECT 'Fluconazole 150mg',      1.75, N'Antifungal'           UNION ALL
    SELECT 'Ciprofloxacin 500mg',    2.90, N'Antibiotic'           UNION ALL
    SELECT 'Ferrous Sulfate 325mg',  0.70, N'Iron supplement'      UNION ALL
    SELECT 'Folic Acid 5mg',         0.60, N'Vitamin B9'           UNION ALL
    SELECT 'Calcium 500mg',          0.65, N'Mineral supplement'   UNION ALL
    SELECT 'Magnesium 250mg',        0.75, N'Mineral supplement'   UNION ALL
    SELECT 'Zinc 25mg',              0.55, N'Mineral supplement'   UNION ALL
    SELECT 'Vitamin C 500mg',        0.50, N'Ascorbic acid'        UNION ALL
    SELECT 'Lisinopril 10mg',        1.10, N'ACE inhibitor'        UNION ALL
    SELECT 'Pantoprazole 40mg',      1.40, N'PPI'                  UNION ALL
    SELECT 'Montelukast 10mg',       1.95, N'Leukotriene antagonist' UNION ALL
    SELECT 'Atenolol 50mg',          1.25, N'Beta blocker'         UNION ALL
    SELECT 'Ranitidine 150mg',       0.90, N'H2 blocker (legacy)'  UNION ALL
    SELECT 'Diclofenac 50mg',        0.95, N'NSAID'
)
INSERT INTO dbo.Medicines(MedName, Price, [Description])
SELECT m.name, m.price, m.descr
FROM meds m
WHERE NOT EXISTS (SELECT 1 FROM dbo.Medicines x WHERE x.MedName = m.name);
GO

/* ==== From here we keep one batch (no GO) so variables stay alive ==== */

/* === 2) Resolve IDs & create ph_new if needed === */
DECLARE @KumarID INT = (SELECT id FROM dbo.[users] WHERE username='kumar' AND userRole='Pharmacist');
IF @KumarID IS NULL
BEGIN
    RAISERROR('Pharmacist user "kumar" not found as users.username.',16,1);
    RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.[users] WHERE username='ph_new')
BEGIN
    INSERT INTO dbo.[users](userRole, [name], dob, mobile, email, username, [pass])
    VALUES ('Pharmacist', 'Ph New', 'Monday, Jan 1, 1990', 7770001111, 'ph_new@mail.com', 'ph_new', 'ph_new');
END;
DECLARE @NewPharmID INT = (SELECT id FROM dbo.[users] WHERE username='ph_new');

/* === 3) Add 20 medicines to kumar’s inventory (skip existing) === */
;WITH pool AS (
    SELECT MedicineID FROM dbo.Medicines
),
pick AS (
    SELECT TOP (20) p.MedicineID
    FROM pool p
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.PharmacistMedicines pm
        WHERE pm.PharmacistID = @KumarID AND pm.MedicineID = p.MedicineID
    )
    ORDER BY p.MedicineID
)
INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT @KumarID, MedicineID, 200.00
FROM pick
ORDER BY MedicineID;

/* === 4) Add 30 medicines to new pharmacist’s inventory (skip existing) === */
;WITH pool2 AS (
    SELECT MedicineID FROM dbo.Medicines
),
pick2 AS (
    SELECT TOP (30) p.MedicineID
    FROM pool2 p
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.PharmacistMedicines pm
        WHERE pm.PharmacistID = @NewPharmID AND pm.MedicineID = p.MedicineID
    )
    ORDER BY p.MedicineID
)
INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
SELECT @NewPharmID, MedicineID, 200.00
FROM pick2
ORDER BY MedicineID;

/* === 5) Ensure/assign customers: lojain -> ph_new, create baha'a -> ph_new === */
DECLARE @LojainID INT = (SELECT CustomerID FROM dbo.Customers WHERE Username = 'lojain');
IF @LojainID IS NULL
BEGIN
    INSERT INTO dbo.Customers(Username, Email, Mobile, [Password], PharmacistID)
    VALUES ('lojain', 'lojain@mail.com', 999000111, 'pwd', @NewPharmID);
    SET @LojainID = SCOPE_IDENTITY();
END
ELSE
BEGIN
    UPDATE dbo.Customers SET PharmacistID = @NewPharmID WHERE CustomerID = @LojainID;
END;

DECLARE @BahaaID INT = (SELECT CustomerID FROM dbo.Customers WHERE Username = N'baha''a');
IF @BahaaID IS NULL
BEGIN
    INSERT INTO dbo.Customers(Username, Email, Mobile, [Password], PharmacistID)
    VALUES (N'baha''a', 'bahaa@mail.com', 999000222, 'pwd', @NewPharmID);
    SET @BahaaID = SCOPE_IDENTITY();
END
ELSE
BEGIN
    UPDATE dbo.Customers SET PharmacistID = @NewPharmID WHERE CustomerID = @BahaaID;
END;

/* === 6) Prescribe 5 meds to lojain & 7 to baha'a from ph_new inventory === */
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

/* ---- For lojain (5) ---- */
IF OBJECT_ID('tempdb..#todo1') IS NOT NULL DROP TABLE #todo1;

;WITH inv AS (
    SELECT pm.MedicineID
    FROM dbo.PharmacistMedicines pm
    WHERE pm.PharmacistID = @NewPharmID AND pm.QtyAvailable >= 14 -- 2x1x7
),
already AS (
    SELECT DISTINCT cm.MedicineID
    FROM dbo.CustomerMedicines cm
    WHERE cm.CustomerID = @LojainID
),
todo AS (
    SELECT TOP (5) i.MedicineID
    FROM inv i
    WHERE NOT EXISTS (SELECT 1 FROM already a WHERE a.MedicineID = i.MedicineID)
    ORDER BY i.MedicineID
)
SELECT MedicineID INTO #todo1 FROM todo;

DECLARE @i INT = 1, @n INT, @mid INT;
SELECT @n = COUNT(*) FROM #todo1;

WHILE @i <= @n
BEGIN
    SELECT @mid = MedicineID
    FROM (
        SELECT MedicineID, ROW_NUMBER() OVER (ORDER BY MedicineID) AS rn
        FROM #todo1
    ) x
    WHERE rn = @i;

    EXEC dbo.sp_PrescribeMedicine
        @PharmacistID = @NewPharmID,
        @CustomerID   = @LojainID,
        @MedicineID   = @mid,
        @TimesPerDay  = 2,
        @UnitsPerDose = 1,
        @DurationDays = 7,
        @StartDate    = @Today;

    SET @i += 1;
END

/* ---- For baha'a (7) ---- */
IF OBJECT_ID('tempdb..#todo2') IS NOT NULL DROP TABLE #todo2;

;WITH inv2 AS (
    SELECT pm.MedicineID
    FROM dbo.PharmacistMedicines pm
    WHERE pm.PharmacistID = @NewPharmID AND pm.QtyAvailable >= 21 -- 3x1x7
),
already2 AS (
    SELECT DISTINCT cm.MedicineID
    FROM dbo.CustomerMedicines cm
    WHERE cm.CustomerID = @BahaaID
),
todo2 AS (
    SELECT TOP (7) i.MedicineID
    FROM inv2 i
    WHERE NOT EXISTS (SELECT 1 FROM already2 a WHERE a.MedicineID = i.MedicineID)
    ORDER BY i.MedicineID
)
SELECT MedicineID INTO #todo2 FROM todo2;

DECLARE @j INT = 1, @m INT;
SELECT @m = COUNT(*) FROM #todo2;

WHILE @j <= @m
BEGIN
    SELECT @mid = MedicineID
    FROM (
        SELECT MedicineID, ROW_NUMBER() OVER (ORDER BY MedicineID) AS rn
        FROM #todo2
    ) x
    WHERE rn = @j;

    EXEC dbo.sp_PrescribeMedicine
        @PharmacistID = @NewPharmID,
        @CustomerID   = @BahaaID,
        @MedicineID   = @mid,
        @TimesPerDay  = 3,
        @UnitsPerDose = 1,
        @DurationDays = 7,
        @StartDate    = @Today;

    SET @j += 1;
END

/* === 7) Quick results === */
PRINT '---- IDs ----';
SELECT KumarID=@KumarID, NewPharmacistID=@NewPharmID, LojainID=@LojainID, BahaaID=@BahaaID;

PRINT '---- Kumar inventory (top 20 shown) ----';
SELECT TOP 20 m.MedName, pm.QtyAvailable
FROM dbo.PharmacistMedicines pm
JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
WHERE pm.PharmacistID = @KumarID
ORDER BY m.MedName;

PRINT '---- ph_new inventory (top 30 shown) ----';
SELECT TOP 30 m.MedName, pm.QtyAvailable
FROM dbo.PharmacistMedicines pm
JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID
WHERE pm.PharmacistID = @NewPharmID
ORDER BY m.MedName;

PRINT '---- Prescriptions for lojain ----';
EXEC dbo.sp_GetCustomerPrescriptions @CustomerID = @LojainID;

PRINT '---- Prescriptions for baha''a ----';
EXEC dbo.sp_GetCustomerPrescriptions @CustomerID = @BahaaID;
