-- SQL Statements/Create User Table.sql

/* 
   Opretter dbo.Users hvis den ikke findes.
   Indeholder login-brugere med unik Username, hashed adgangskode, rolle og oprettelsestid i UTC.
   Idempotent: Kører sikkert flere gange uden at fejle.
*/
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='Users' AND schema_id=SCHEMA_ID('dbo'))
BEGIN
  CREATE TABLE dbo.Users (
      Id           INT IDENTITY(1,1) PRIMARY KEY, -- Auto-increment PK for stabile referencer
      Username     NVARCHAR(64)  NOT NULL UNIQUE, -- Unikt login-navn (unik constraint opretter automatisk index)
      PasswordHash NVARCHAR(200) NOT NULL, -- Gemmer hash'et password (fx PBKDF2-encoded string)
      Role         NVARCHAR(32)  NOT NULL DEFAULT 'user', -- Simpelt rollefelt med standard 'user'
      CreatedAt    DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME() -- Oprettelsestid i UTC
  );
END
