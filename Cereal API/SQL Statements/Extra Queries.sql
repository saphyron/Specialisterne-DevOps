-- SQL Statements/Queries.sql

/* =====================================================================
   Queries.sql – hjælpeforespørgsler og admin-scripts til CerealDb
   ---------------------------------------------------------------------
   ✔ Kør ALTID mod den rigtige database (se USE ... nedenfor).
   ✔ Nogle statements er destruktive (DELETE, DROP CONSTRAINT/COLUMN).
   ✔ Overvej at køre kritiske ændringer i en TRANSACTION i prod.
   ===================================================================== */

/* === Vælg database (fjern kommentering hvis nødvendigt) ===
USE [CerealDb];
GO
*/

SET NOCOUNT ON;

/* =====================================================================
   A) Hurtigt kig / oprydning i Cereal-data
   ---------------------------------------------------------------------
   - Første SELECT: se nuværende status.
   - DELETE: sletter alle rækker med producentkode 'y' (kollektion kan
             være case-insensitiv afhængigt af DB-collation).
   - Anden SELECT: verifikationskig efter sletning.
   ⚠ ADVARSEL: DELETE er permanent – kør kun hvis du er sikker.
   ===================================================================== */
SELECT * FROM dbo.Cereal;

-- ⚠ Destruktivt: sletter alle rækker med mfr='y'
DELETE FROM dbo.Cereal WHERE mfr = 'y';

SELECT * FROM dbo.Cereal;


/* =====================================================================
   B) Genopbyg Id/PK på dbo.Cereal
   ---------------------------------------------------------------------
   Denne sektion dropper den nuværende primærnøgle (PK_Cereal_Id) og
   Id-kolonnen, tilføjer en ny IDENTITY-kolonne, og opretter ny PK på Id.

   ⚠ ADVARSLER:
   - Fejler hvis PK_Cereal_Id ikke findes (overvej IF EXISTS-guard).
   - Fejler hvis andre tabeller har FOREIGN KEY mod Cereal.Id.
     (Drop/disable FKs først, eller migrér i korrekt rækkefølge.)
   - DROP COLUMN Id fjerner også indeks/tilladelser knyttet til kolonnen.

   TIP (prod): Pak ALTER-udsagn i TRANSACTION:
     BEGIN TRY; BEGIN TRAN;
       ... ALTER ...
     COMMIT; END TRY
     BEGIN CATCH; IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
   ===================================================================== */
ALTER TABLE dbo.Cereal DROP CONSTRAINT PK_Cereal_Id;  -- ⚠ dropper eksisterende PK
ALTER TABLE dbo.Cereal DROP COLUMN Id;                -- ⚠ fjerner Id-kolonnen helt

-- Tilføj ny IDENTITY-kolonne; eksisterende rækker får fortløbende værdier
ALTER TABLE dbo.Cereal ADD Id INT IDENTITY(1,1) NOT NULL;

-- Opret ny PK på Id (clustered som standard)
ALTER TABLE dbo.Cereal ADD CONSTRAINT PK_Cereal_Id PRIMARY KEY (Id);

-- (Valgfrit) Hvis du senere har brugt IDENTITY_INSERT eller bulk, kan du reseede:
-- DBCC CHECKIDENT ('dbo.Cereal', RESEED);  -- sæt til Max(Id) hvis nødvendigt




/* =====================================================================
   C) Sikkerhed – overblik over brugere/roller/rettigheder i den AKTUELLE DB
   ---------------------------------------------------------------------
   1) Liste over database-brugere (ekskl. systemkonti)
   2) Rollemedlemskaber (hvilke roller hver bruger er i)
   3) Eksplicitte tilladelser (GRANT/DENY) pr. objekt/kolonne
   Brug disse til fejlsøgning, når API’et rammer 401/403/permission issues.
   ===================================================================== */

-- 1) Brugere i databasen
SELECT
  dp.name                   AS user_name,
  dp.type_desc              AS user_type,              -- SQL_USER, WINDOWS_USER, EXTERNAL_USER, WINDOWS_GROUP
  dp.authentication_type_desc,
  dp.default_schema_name,
  dp.create_date,
  dp.modify_date
FROM sys.database_principals dp
WHERE dp.type IN ('S','U','E','G')                     -- S=SQL, U=Windows, E=External, G=Windows group
  AND dp.name NOT IN ('guest','sys','INFORMATION_SCHEMA')
ORDER BY dp.name;

-- 2) Rollemedlemskaber (hvilke DB-roller hver bruger er i)
SELECT
  m.name  AS user_name,
  r.name  AS role_name
FROM sys.database_role_members drm
JOIN sys.database_principals r ON r.principal_id  = drm.role_principal_id
JOIN sys.database_principals m ON m.principal_id  = drm.member_principal_id
ORDER BY m.name, r.name;

-- 3) Eksplicitte tilladelser (GRANT/DENY) i databasen
SELECT
  grantee.name              AS user_name,
  dp.permission_name,
  dp.state_desc             AS permission_state,       -- GRANT / DENY / GRANT_WITH_GRANT_OPTION
  dp.class_desc,                                      -- DATABASE / SCHEMA / OBJECT / COLUMN
  OBJECT_SCHEMA_NAME(dp.major_id) AS schema_name,
  OBJECT_NAME(dp.major_id)       AS object_name,
  c.name                   AS column_name
FROM sys.database_permissions dp
JOIN sys.database_principals grantee ON grantee.principal_id = dp.grantee_principal_id
LEFT JOIN sys.columns c ON c.object_id = dp.major_id AND c.column_id = dp.minor_id
WHERE grantee.type IN ('S','U','E','G')
ORDER BY user_name, dp.class_desc, schema_name, object_name, dp.permission_name;
