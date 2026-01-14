/* =======================================================================
   PHARMACY — CLEAN BASELINE (SQL Server 2014+)
   - Idempotent, deduplicated, English comments, consistent FKs to users
   - Run the whole script. Batches (GO) are used where required.
   ======================================================================= */

IF DB_ID('pharmacy') IS NULL
    CREATE DATABASE pharmacy;
GO
USE pharmacy;
GO

/* =========================
   1) Core tables
   ========================= */

-- 1.1 Users
IF OBJECT_ID('dbo.users','U') IS NOT NULL
    DROP TABLE dbo.users;
GO
CREATE TABLE dbo.users(
    id        INT IDENTITY(1,1) PRIMARY KEY,
    userRole  VARCHAR(50)  NOT NULL,         -- e.g., 'Pharmacist', 'Administrator'
    name      VARCHAR(250) NOT NULL,
    dob       VARCHAR(250) NOT NULL,         -- keep as provided (string)
    mobile    BIGINT       NOT NULL,
    email     VARCHAR(250) NOT NULL,
    username  VARCHAR(250) NOT NULL UNIQUE,
    [pass]    VARCHAR(250) NOT NULL
);

-- Seed minimal users (safe upsert by username)
MERGE dbo.users AS t
USING (VALUES
 ('Pharmacist','kumar','Thursday, October 1, 2020',123456,'btechdays.care@gmail.com','kumar','kumar'),
 ('Administrator','BTech Days','Thursday, July 18, 1991',5655652323,'btechdays.care@gmail.com','btechdays','btechdays'),
 ('Pharmacist','Rohan','Wednesday, June 14, 1995',1234567890,'rohan@gmail.com','rohan','rohan'),
 ('Administrator','gaurav','Thursday, July 13, 1995',123456,'gaurav@gmail.com','gaurav','gaurav')
) AS s(userRole,name,dob,mobile,email,username,[pass])
ON t.username = s.username
WHEN NOT MATCHED THEN
  INSERT(userRole,name,dob,mobile,email,username,[pass])
  VALUES(s.userRole,s.name,s.dob,s.mobile,s.email,s.username,s.[pass]);

/* Customers */
IF OBJECT_ID('dbo.Customers','U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers (
        CustomerID   INT IDENTITY(1,1) PRIMARY KEY,
        Username     VARCHAR(250) UNIQUE NOT NULL,
        Email        VARCHAR(250) NOT NULL,
        Mobile       BIGINT NOT NULL,
        [Password]   VARCHAR(250) NOT NULL,
        PharmacistID INT NULL       -- FK to users(id)
    );
END

-- FK: Customers.PharmacistID -> users.id
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_Customers_Users')
BEGIN
    ALTER TABLE dbo.Customers WITH CHECK
      ADD CONSTRAINT FK_Customers_Users
      FOREIGN KEY(PharmacistID) REFERENCES dbo.users(id);
END

-- Seed customers (won't duplicate)
MERGE dbo.Customers AS t
USING (VALUES
 ('yaqeen','yaqeen@mail.com',777777777,'xxxx',NULL),
 ('sarah' ,'sarah@mail.com' ,888888888,'yyyy',NULL)
) AS s(Username,Email,Mobile,[Password],PharmacistID)
ON t.Username = s.Username
WHEN NOT MATCHED THEN
  INSERT(Username,Email,Mobile,[Password],PharmacistID)
  VALUES(s.Username,s.Email,s.Mobile,s.[Password],s.PharmacistID);

/* Medicines */
IF OBJECT_ID('dbo.Medicines','U') IS NULL
BEGIN
    CREATE TABLE dbo.Medicines (
        MedicineID   INT IDENTITY(1,1) PRIMARY KEY,
        MedName      VARCHAR(250) NOT NULL UNIQUE,
        Price        DECIMAL(10,2) NOT NULL,
        [Description] NVARCHAR(500) NULL
    );
END

-- Seed a few core medicines (idempotent)
MERGE dbo.Medicines AS t
USING (VALUES
 ('Paracetamol 500mg', 0.75, N'Analgesic/antipyretic'),
 ('Amoxicillin 500mg', 2.80, N'Antibiotic'),
 ('Vitamin D 1000 IU', 3.50, N'Dietary supplement')
) AS s(MedName,Price,[Description])
ON t.MedName = s.MedName
WHEN NOT MATCHED THEN
  INSERT(MedName,Price,[Description]) VALUES(s.MedName,s.Price,s.[Description]);

/* CustomerMedicines (prescriptions) */
IF OBJECT_ID('dbo.CustomerMedicines','U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomerMedicines (
        CustomerMedicineID INT IDENTITY(1,1) PRIMARY KEY,
        CustomerID         INT NOT NULL,
        MedicineID         INT NOT NULL,
        TimesPerDay        TINYINT NOT NULL,
        UnitsPerDose       DECIMAL(10,2) NOT NULL,
        StartDate          DATE NOT NULL CONSTRAINT DF_CM_StartDate DEFAULT (CAST(GETDATE() AS DATE)),
        DurationDays       INT  NOT NULL CONSTRAINT DF_CM_DurationDays DEFAULT (7),
        EndDate AS (CASE WHEN StartDate IS NULL OR DurationDays IS NULL
                         THEN NULL
                         ELSE DATEADD(DAY, DurationDays - 1, StartDate) END) PERSISTED,
        PrescribedByPharmacistID INT NOT NULL  -- FK to users(id)
    );

    ALTER TABLE dbo.CustomerMedicines WITH CHECK
      ADD CONSTRAINT FK_CM_Customers FOREIGN KEY(CustomerID) REFERENCES dbo.Customers(CustomerID);

    ALTER TABLE dbo.CustomerMedicines WITH CHECK
      ADD CONSTRAINT FK_CM_Medicines FOREIGN KEY(MedicineID) REFERENCES dbo.Medicines(MedicineID);

    ALTER TABLE dbo.CustomerMedicines WITH CHECK
      ADD CONSTRAINT FK_CM_Users FOREIGN KEY(PrescribedByPharmacistID) REFERENCES dbo.users(id);
END

/* PharmacistMedicines (inventory per pharmacist) */
IF OBJECT_ID('dbo.PharmacistMedicines','U') IS NULL
BEGIN
    CREATE TABLE dbo.PharmacistMedicines (
        ID           INT IDENTITY(1,1) PRIMARY KEY,
        PharmacistID INT NOT NULL,     -- users.id
        MedicineID   INT NOT NULL,
        QtyAvailable DECIMAL(10,2) NOT NULL,
        CONSTRAINT FK_PM_Users    FOREIGN KEY(PharmacistID) REFERENCES dbo.users(id),
        CONSTRAINT FK_PM_Meds     FOREIGN KEY(MedicineID)   REFERENCES dbo.Medicines(MedicineID),
        CONSTRAINT UX_PM UNIQUE(PharmacistID, MedicineID)   -- one row per pharm+med
    );
END

/* Helpful indexes */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Customers_Pharmacist' AND object_id=OBJECT_ID('dbo.Customers'))
    CREATE INDEX IX_Customers_Pharmacist ON dbo.Customers(PharmacistID);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_PM_Pharmacist' AND object_id=OBJECT_ID('dbo.PharmacistMedicines'))
    CREATE INDEX IX_PM_Pharmacist ON dbo.PharmacistMedicines(PharmacistID);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_CM_Customer' AND object_id=OBJECT_ID('dbo.CustomerMedicines'))
    CREATE INDEX IX_CM_Customer ON dbo.CustomerMedicines(CustomerID);


/* =========================
   2) Clinical data model
   ========================= */

-- Ingredients (active substances)
IF OBJECT_ID('dbo.Ingredients','U') IS NULL
BEGIN
    CREATE TABLE dbo.Ingredients(
        IngredientID INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(200) UNIQUE NOT NULL
    );
END

-- Medicine-to-Ingredient mapping (many-to-many)
IF OBJECT_ID('dbo.MedicineIngredients','U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicineIngredients(
        MedicineID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Medicines(MedicineID),
        IngredientID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
        CONSTRAINT PK_MedicineIngredients PRIMARY KEY (MedicineID, IngredientID)
    );
END

-- Ingredient interactions
IF OBJECT_ID('dbo.IngredientInteractions','U') IS NULL
BEGIN
    CREATE TABLE dbo.IngredientInteractions(
        InteractionID INT IDENTITY(1,1) PRIMARY KEY,
        IngredientAID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
        IngredientBID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
        Severity      VARCHAR(20) NOT NULL, -- Minor / Moderate / Major
        Note          NVARCHAR(500) NULL,
        CONSTRAINT UX_Interaction UNIQUE(IngredientAID, IngredientBID)
    );
END

-- Customer allergies
IF OBJECT_ID('dbo.CustomerAllergies','U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomerAllergies(
        CustomerID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Customers(CustomerID),
        IngredientID INT NOT NULL FOREIGN KEY REFERENCES dbo.Ingredients(IngredientID),
        Note         NVARCHAR(300) NULL,
        CONSTRAINT PK_CustomerAllergies PRIMARY KEY (CustomerID, IngredientID)
    );
END

-- Seed a minimal set of ingredients (idempotent)
MERGE dbo.Ingredients AS t
USING (VALUES
 (N'Paracetamol'),
 (N'Amoxicillin'),
 (N'Vitamin D'),
 (N'Warfarin'),
 (N'Allopurinol')
) AS s(Name)
ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT(Name) VALUES(s.Name);

-- Map current seeded medicines to ingredients (skip existing)
INSERT INTO dbo.MedicineIngredients(MedicineID, IngredientID)
SELECT m.MedicineID, i.IngredientID
FROM dbo.Medicines m
JOIN dbo.Ingredients i ON
     (m.MedName LIKE 'Paracetamol%'  AND i.Name=N'Paracetamol')
  OR (m.MedName LIKE 'Amoxicillin%'  AND i.Name=N'Amoxicillin')
  OR (m.MedName LIKE 'Vitamin D%'    AND i.Name=N'Vitamin D')
WHERE NOT EXISTS (
  SELECT 1 FROM dbo.MedicineIngredients mi
  WHERE mi.MedicineID=m.MedicineID AND mi.IngredientID=i.IngredientID
);

-- Seed a few interactions (idempotent)
DECLARE @Amox INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Amoxicillin');
DECLARE @VitD INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Vitamin D');
DECLARE @Warf INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Warfarin');
DECLARE @Allo INT = (SELECT IngredientID FROM dbo.Ingredients WHERE Name=N'Allopurinol');

IF @Amox IS NOT NULL AND @Allo IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@Allo)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@Allo,'Moderate',N'May increase risk of rash — monitor the patient.');
IF @Amox IS NOT NULL AND @Warf IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@Warf)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@Warf,'Major',N'Warfarin effect/INR may increase — avoid or monitor INR closely.');
IF @Amox IS NOT NULL AND @VitD IS NOT NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.IngredientInteractions WHERE IngredientAID=@Amox AND IngredientBID=@VitD)
        INSERT INTO dbo.IngredientInteractions(IngredientAID,IngredientBID,Severity,Note)
        VALUES(@Amox,@VitD,'Minor',N'No clinically significant interaction expected (demo).');


/* =========================
   3) Operational table "medic"
   - Mirrors PharmacistMedicines + Medicines
   ========================= */

IF OBJECT_ID('dbo.medic','U') IS NULL
BEGIN
    CREATE TABLE dbo.medic (
        id        INT IDENTITY(1,1) PRIMARY KEY,
        mid       VARCHAR(20)   NOT NULL,     -- string MedicineID
        mname     VARCHAR(100)  NOT NULL,     -- medicine name (denormalized)
        mnumber   VARCHAR(50)   NOT NULL,     -- SKU-<MedicineID>
        mDate     DATE NOT NULL  CONSTRAINT DF_medic_mDate DEFAULT (CAST(GETDATE() AS DATE)),
        eDate     DATE NOT NULL  CONSTRAINT DF_medic_eDate DEFAULT (CAST('2099-12-31' AS DATE)),
        quantity  INT  NOT NULL,
        perUnit   DECIMAL(10,2) NOT NULL,
        PharmacistID INT NOT NULL             -- FK to users(id)
    );

    ALTER TABLE dbo.medic WITH CHECK
      ADD CONSTRAINT FK_medic_users FOREIGN KEY(PharmacistID) REFERENCES dbo.users(id);

    -- Unique per pharmacist + medicine
    CREATE UNIQUE INDEX UX_medic_PharmMid ON dbo.medic(PharmacistID, mid);
END


/* =========================
   4) Stored procedures
   ========================= */

-- 4.1 Get customers for a pharmacist
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

-- 4.2 Get pharmacist inventory (+ optional name filter)
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

-- 4.3 Get customer prescriptions
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
    ORDER BY cm.StartDate DESC, cm.CustomerMedicineID DESC;
END
GO

-- 4.4 Prescribe medicine (with inventory deduction and ownership checks)
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

    -- Customer must belong to the pharmacist
    IF NOT EXISTS (
        SELECT 1 FROM dbo.Customers 
        WHERE CustomerID = @CustomerID AND PharmacistID = @PharmacistID
    )
    BEGIN
        RAISERROR(N'This customer is not assigned to the pharmacist.', 16, 1);
        RETURN;
    END

    DECLARE @ToDeduct DECIMAL(18,2);
    SET @ToDeduct = CAST(@TimesPerDay AS DECIMAL(18,2)) * @UnitsPerDose * @DurationDays;

    BEGIN TRY
        BEGIN TRAN;

        -- Deduct inventory (fail if insufficient)
        UPDATE dbo.PharmacistMedicines
           SET QtyAvailable = QtyAvailable - @ToDeduct
         WHERE PharmacistID = @PharmacistID
           AND MedicineID    = @MedicineID
           AND QtyAvailable >= @ToDeduct;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR(N'Drug not available or insufficient quantity for this pharmacist.', 16, 1);
            ROLLBACK TRAN;
            RETURN;
        END

        -- Save prescription
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
    END CATCH
END
GO

-- 4.5 Safety check: allergies + interactions (current active meds)
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


/* =========================
   5) medic synchronization
   ========================= */

-- 5.1 Sync proc (PharmacistMedicines -> medic)
IF OBJECT_ID('dbo.sp_SyncMedicFromInventory','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SyncMedicFromInventory;
GO
CREATE PROCEDURE dbo.sp_SyncMedicFromInventory
AS
BEGIN
  SET NOCOUNT ON;

  IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;

  -- Build source set from live inventory
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

  -- Update existing rows
  UPDATE d
     SET d.mname    = s.mname,
         d.mnumber  = s.mnumber,
         d.quantity = s.quantity,
         d.perUnit  = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- Insert missing rows
  INSERT INTO dbo.medic (mid, mname, mnumber, mDate, eDate, quantity, perUnit, PharmacistID)
  SELECT s.mid, s.mname, s.mnumber, CAST(GETDATE() AS DATE), CAST('2099-12-31' AS DATE),
         s.quantity, s.perUnit, s.PharmacistID
  FROM #src s
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.medic d
    WHERE d.PharmacistID = s.PharmacistID AND d.mid = s.mid
  );

  -- Delete rows no longer present in inventory
  DELETE d
  FROM dbo.medic d
  WHERE NOT EXISTS (
      SELECT 1 FROM #src s
      WHERE s.PharmacistID = d.PharmacistID AND s.mid = d.mid
  );

  DROP TABLE #src;
END
GO

-- 5.2 Triggers to keep medic in sync
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

  -- Update existing
  UPDATE d
     SET d.mname    = s.mname,
         d.mnumber  = s.mnumber,
         d.quantity = s.quantity,
         d.perUnit  = s.perUnit
  FROM dbo.medic d
  JOIN #src s
    ON s.PharmacistID = d.PharmacistID
   AND s.mid = d.mid;

  -- Insert new
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


/* =========================
   6) Views (optional)
   ========================= */

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
    pm.QtyAvailable AS Available
FROM dbo.PharmacistMedicines pm
JOIN dbo.Medicines m ON m.MedicineID = pm.MedicineID;
GO


/* =========================
   7) Default 70-medicine pack + auto-provision
   ========================= */

-- 7.1 Seed 70 medicine definitions (names/prices/descriptions)
IF OBJECT_ID('tempdb..#seed70') IS NOT NULL DROP TABLE #seed70;
CREATE TABLE #seed70(
    MedName       VARCHAR(250) PRIMARY KEY,
    Price         DECIMAL(10,2) NOT NULL,
    [Description] NVARCHAR(500) NULL
);

INSERT INTO #seed70(MedName, Price, [Description]) VALUES
('Paracetamol 500mg',0.75,N'Analgesic/antipyretic'),
('Ibuprofen 200mg',0.90,N'NSAID for pain/fever'),
('Diclofenac 50mg',0.95,N'NSAID'),
('Aspirin 81mg',0.50,N'Low-dose antiplatelet'),
('Naproxen 250mg',1.10,N'NSAID'),
('Amoxicillin 500mg',2.80,N'Antibiotic - penicillin'),
('Azithromycin 500mg',3.20,N'Antibiotic - macrolide'),
('Ciprofloxacin 500mg',2.90,N'Antibiotic - fluoroquinolone'),
('Doxycycline 100mg',2.60,N'Antibiotic - tetracycline'),
('Metronidazole 500mg',1.80,N'Antibiotic/antiprotozoal'),
('Clarithromycin 500mg',3.10,N'Macrolide antibiotic'),
('Co-amoxiclav 625mg',3.50,N'Amoxicillin + clavulanate'),
('Cephalexin 500mg',2.20,N'Cephalosporin antibiotic'),
('Cefuroxime 500mg',2.70,N'Cephalosporin antibiotic'),
('Fluconazole 150mg',1.75,N'Antifungal'),
('Clotrimazole 1% cream',1.20,N'Topical antifungal'),
('Acyclovir 400mg',2.10,N'Antiviral'),
('Loratadine 10mg',0.85,N'Antihistamine (non-drowsy)'),
('Cetirizine 10mg',0.90,N'Antihistamine'),
('Fexofenadine 120mg',1.40,N'Antihistamine'),
('Salbutamol Inhaler',4.90,N'Bronchodilator (SABA)'),
('Budesonide Inhaler 200mcg',7.50,N'Inhaled corticosteroid'),
('Montelukast 10mg',1.95,N'Leukotriene antagonist'),
('Omeprazole 20mg',1.30,N'PPI for GERD'),
('Pantoprazole 40mg',1.40,N'PPI'),
('Ranitidine 150mg',0.90,N'H2 blocker (legacy)'),
('Domperidone 10mg',0.80,N'Prokinetic/antiemetic'),
('Metoclopramide 10mg',0.70,N'Antiemetic'),
('Loperamide 2mg',0.65,N'Antidiarrheal'),
('Oral Rehydration Salts',0.50,N'ORS sachet'),
('Ferrous Sulfate 325mg',0.70,N'Iron supplement'),
('Folic Acid 5mg',0.60,N'Vitamin B9 supplement'),
('Vitamin D3 1000 IU',0.55,N'Cholecalciferol'),
('Vitamin B Complex',0.80,N'Multivitamin B group'),
('Zinc 25mg',0.55,N'Mineral supplement'),
('Calcium 500mg',0.65,N'Mineral supplement'),
('Magnesium 250mg',0.75,N'Mineral supplement'),
('Metformin 500mg',2.20,N'Antidiabetic - biguanide'),
('Glimepiride 2mg',1.60,N'Sulfonylurea antidiabetic'),
('Insulin Glargine 100U',12.00,N'Basal insulin'),
('Amlodipine 5mg',1.95,N'Calcium channel blocker'),
('Losartan 50mg',1.85,N'ARB'),
('Lisinopril 10mg',1.10,N'ACE inhibitor'),
('Atenolol 50mg',1.25,N'Beta blocker'),
('Hydrochlorothiazide 25mg',0.80,N'Thiazide diuretic'),
('Furosemide 40mg',0.90,N'Loop diuretic'),
('Atorvastatin 20mg',2.40,N'Statin'),
('Simvastatin 20mg',1.90,N'Statin'),
('Clopidogrel 75mg',2.10,N'Antiplatelet'),
('Warfarin 5mg',1.20,N'Anticoagulant (monitor INR)'),
('Levothyroxine 50mcg',1.70,N'Thyroid hormone'),
('Allopurinol 100mg',1.30,N'Xanthine oxidase inhibitor'),
('Colchicine 0.5mg',1.10,N'Anti-gout'),
('Diclofenac Gel 1%',1.50,N'Topical NSAID'),
('Ibuprofen Syrup 100mg/5ml',0.95,N'Pediatric analgesic'),
('Paracetamol Syrup 120mg/5ml',0.80,N'Pediatric antipyretic'),
('Povidone-Iodine 10% solution',1.00,N'Antiseptic'),
('Chlorhexidine 0.12% mouthwash',1.20,N'Antiseptic mouthwash'),
('Hydrocortisone 1% cream',1.10,N'Topical steroid (mild)'),
('Miconazole 2% oral gel',1.40,N'Antifungal oral gel'),
('Nitroglycerin 0.5mg SL',2.00,N'Antianginal (sublingual)'),
('Isosorbide Mononitrate 20mg',1.60,N'Antianginal (long-acting)'),
('Sertraline 50mg',2.30,N'SSRI'),
('Diazepam 5mg',1.50,N'Anxiolytic/benzodiazepine'),
('Gabapentin 300mg',2.60,N'Neuropathic pain/anticonvulsant'),
('Tramadol 50mg',1.90,N'Analgesic (opioid-like)'),
('Melatonin 3mg',1.10,N'Sleep aid'),
('Salbutamol Nebules 2.5mg/3ml',1.80,N'Nebulized SABA'),
('Insulin Regular 100U',10.00,N'Fast-acting insulin');

-- Upsert into Medicines
MERGE dbo.Medicines AS tgt
USING #seed70 AS src
   ON tgt.MedName = src.MedName
WHEN MATCHED THEN
    UPDATE SET tgt.Price = src.Price, tgt.[Description] = src.[Description]
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MedName, Price, [Description])
    VALUES (src.MedName, src.Price, src.[Description]);
DROP TABLE #seed70;

-- DefaultProvisionMeds list (stable reference set)
IF OBJECT_ID('dbo.DefaultProvisionMeds','U') IS NULL
BEGIN
    CREATE TABLE dbo.DefaultProvisionMeds(
        MedName VARCHAR(250) PRIMARY KEY
    );
END
INSERT INTO dbo.DefaultProvisionMeds(MedName)
SELECT m.MedName
FROM dbo.Medicines m
WHERE NOT EXISTS (SELECT 1 FROM dbo.DefaultProvisionMeds d WHERE d.MedName = m.MedName);

-- 7.2 Provision procedure: give the 70-pack to a pharmacist (random qty 10–100)
IF OBJECT_ID('dbo.sp_ProvisionDefaultMedsForPharmacist','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProvisionDefaultMedsForPharmacist;
GO
CREATE PROCEDURE dbo.sp_ProvisionDefaultMedsForPharmacist
    @PharmacistID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE id=@PharmacistID AND userRole='Pharmacist')
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
END
GO

-- 7.3 Trigger: auto-provision the 70-pack for newly inserted pharmacists
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
END
GO


/* =========================
   8) Minimal sample linking
   ========================= */

-- Assign seed customers to an existing pharmacist (kumar if present)
DECLARE @KumarID INT = (SELECT id FROM dbo.users WHERE username='kumar' AND userRole='Pharmacist');
IF @KumarID IS NOT NULL
BEGIN
    UPDATE c SET PharmacistID = @KumarID FROM dbo.Customers AS c WHERE Username IN ('yaqeen','sarah') AND (PharmacistID IS NULL OR PharmacistID<>@KumarID);
END

-- Ensure kumar has at least Paracetamol in inventory
IF @KumarID IS NOT NULL
BEGIN
    INSERT INTO dbo.PharmacistMedicines(PharmacistID, MedicineID, QtyAvailable)
    SELECT @KumarID, m.MedicineID, 100.00
    FROM dbo.Medicines m
    WHERE m.MedName IN ('Paracetamol 500mg','Amoxicillin 500mg','Vitamin D 1000 IU')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.PharmacistMedicines pm
          WHERE pm.PharmacistID=@KumarID AND pm.MedicineID=m.MedicineID
      );
END

-- Initial sync to medic (safe to re-run)
EXEC dbo.sp_SyncMedicFromInventory;


/* =========================
   9) Quick sanity checks
   ========================= */

-- Pharmacists and assigned patients count
SELECT u.id AS PharmacistID,
       u.username AS Pharmacist,
       COUNT(c.CustomerID) AS PatientsCount
FROM dbo.users u
LEFT JOIN dbo.Customers c ON c.PharmacistID = u.id
WHERE u.userRole='Pharmacist'
GROUP BY u.id, u.username
ORDER BY PatientsCount DESC, u.username;

-- Inventory rows mirrored into medic
SELECT COUNT(*) AS InventoryRows FROM dbo.PharmacistMedicines;
SELECT COUNT(*) AS MedicRows FROM dbo.medic;

-- Example: show kumar inventory from view
IF @KumarID IS NOT NULL
BEGIN
    SELECT * FROM dbo.v_MyInventory WHERE PharmacistID = @KumarID ORDER BY Medicine;
END
