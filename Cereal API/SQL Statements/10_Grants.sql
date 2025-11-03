USE CerealDb;
GO

-- Sørg for at brugeren findes (tilpasset dine navne)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'CerealApiCrudUser')
BEGIN
    CREATE USER CerealApiCrudUser FOR LOGIN CerealApiCrudLogin WITH DEFAULT_SCHEMA = dbo;
END
GO

GRANT CONNECT TO CerealApiCrudUser;
GO

-- Minimum nødvendige rettigheder til auth
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Users TO CerealApiCrudUser;
GO

-- (valgfrit men praktisk for dine andre tests)
IF OBJECT_ID('dbo.Products','U') IS NOT NULL
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Products TO CerealApiCrudUser;
GO

-- (findes i forvejen, men for fuldstændighed)
IF OBJECT_ID('dbo.Cereal','U') IS NOT NULL
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Cereal TO CerealApiCrudUser;
GO
