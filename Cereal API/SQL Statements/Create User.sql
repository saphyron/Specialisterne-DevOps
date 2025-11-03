-- SQL Statements/Create User.sql

/* 
   Opret/konfigurer login, database, tabel, db-bruger og rettigheder til Cereal API.
   Idempotent: Alle sektioner kan køres flere gange uden fejl (IF EXISTS/IF NOT EXISTS).
   BEMÆRK: Adgangskoden her er KUN et dev-eksempel. Brug en sekret-håndteret løsning i prod.
*/
USE master;
GO

/* ------------------------------------------------------------------
   0) Server-login (SQL authentication)
   - Opretter et SQL Server login (server-niveau).
   - Sætter password policy til ON og slår udløb fra i dev.
   - Default database peger på CerealDb (oprettes i trin 1).
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'CerealApiCrudUser')
BEGIN
  CREATE LOGIN [CerealApiCrudUser]
  WITH PASSWORD = 'S3cure!Pass',      -- TODO: Skift i prod / hent fra secrets-vault
       CHECK_POLICY = ON,             -- Brug OS/password policy
       CHECK_EXPIRATION = OFF,        -- Ingen udløb (praktisk i dev)
       DEFAULT_DATABASE = [CerealDb]; -- Sættes her; DB oprettes i næste trin
END
ELSE
BEGIN
  -- Opdatér egenskaber hvis login allerede findes (så vi holder den på sporet)
  ALTER LOGIN [CerealApiCrudUser]
    WITH CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [CerealDb];
END
GO

/* ------------------------------------------------------------------
   1) Database
   - Opretter databasen, hvis den ikke findes.
   ------------------------------------------------------------------ */
IF DB_ID(N'CerealDb') IS NULL
BEGIN
  CREATE DATABASE [CerealDb];
END
GO

/* ------------------------------------------------------------------
   2) Skema + tabel (bootstrap)
   - Opretter dbo.Cereal med sammensat PK (name,mfr,type), hvis tabellen mangler.
   - Denne struktur matcher en tidlig version; senere migration kan tilføje IDENTITY Id
     og unik constraint på (name,mfr,type) (se din Create Table-script).
   - rating gemmes som NVARCHAR (tekstlig kildeværdi).
   ------------------------------------------------------------------ */
USE [CerealDb];
GO

IF OBJECT_ID(N'dbo.Cereal','U') IS NULL
BEGIN
  CREATE TABLE dbo.Cereal
  (
    name     NVARCHAR(100) NOT NULL, -- Cereal-navn
    mfr      NVARCHAR(10)  NOT NULL, -- Producentkode/short
    type     NVARCHAR(10)  NOT NULL, -- Typekode/short
    calories INT     NULL,
    protein  INT     NULL,
    fat      INT     NULL,
    sodium   INT     NULL,
    fiber    FLOAT   NULL,
    carbo    FLOAT   NULL,
    sugars   INT     NULL,
    potass   INT     NULL,
    vitamins INT     NULL,
    shelf    INT     NULL,
    weight   FLOAT   NULL,
    cups     FLOAT   NULL,
    rating   NVARCHAR(50) NULL,  -- VIGTIGT: STRING i DB (matches kildedata)
    CONSTRAINT PK_Cereal PRIMARY KEY (name, mfr, type) -- Samlet nøgle (bootstrap)
  );
END
GO

/* ------------------------------------------------------------------
   3) DB-bruger mappes til login
   - Opretter database-brugeren i CerealDb og binder den til server-login’et.
   - Default schema sættes til dbo.
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'CerealApiCrudUser')
BEGIN
  CREATE USER [CerealApiCrudUser] FOR LOGIN [CerealApiCrudUser]
    WITH DEFAULT_SCHEMA = dbo;
END
GO

/* ------------------------------------------------------------------
   4) Rettigheder
   - Minimerede rettigheder: SELECT/INSERT/UPDATE/DELETE på dbo.Cereal.
   - Dækker også SqlBulkCopy (kræver INSERT).
   ------------------------------------------------------------------ */
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Cereal TO [CerealApiCrudUser];
GO
