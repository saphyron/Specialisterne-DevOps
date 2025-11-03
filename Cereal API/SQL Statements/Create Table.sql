-- SQL Statements/Create Table.sql

/* 
   Opretter Cereal-tabellen og skifter primary key til en auto-increment Id.
   Bevarer unikhed på (name, mfr, type) via en separat UNIQUE constraint.
*/

-- Grundskema for cereal-rows. Navnefelter er required; øvrige felter kan være NULL.
CREATE TABLE dbo.Cereal (
    [name]     nvarchar(100)  NOT NULL, -- Produktravn (unik i kombination med mfr+type)
    [mfr]      nchar(1)       NOT NULL, -- Producentkode (K, G, P, ...)
    [type]     nchar(1)       NOT NULL, -- Produkttype (C, H, ...)
    [calories] int            NULL,
    [protein]  int            NULL,
    [fat]      int            NULL,
    [sodium]   int            NULL,
    [fiber]    float          NULL, -- Bemærk: FLOAT er approx. (OK ift. dataset)
    [carbo]    float          NULL,
    [sugars]   int            NULL,
    [potass]   int            NULL,
    [vitamins] int            NULL,
    [shelf]    int            NULL,
    [weight]   float          NULL,
    [cups]     float          NULL,
    [rating]   nvarchar(100)  NULL  -- Rating er tekst (ikke float i dette tilfælde)
);


/* 1) Tilføj IDENTITY-kolonne som ny primærnøgle (auto-increment) */
ALTER TABLE dbo.Cereal
    ADD Id INT IDENTITY(1,1) NOT NULL;

/* 2) Drop eksisterende PK (hvis der findes en på tabellen, fx på (name,mfr,type)) */
DECLARE @pkName sysname;
SELECT @pkName = kc.name
FROM sys.key_constraints kc
JOIN sys.tables t ON kc.parent_object_id = t.object_id
WHERE kc.type = 'PK' AND t.name = 'Cereal';
IF @pkName IS NOT NULL
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'ALTER TABLE dbo.Cereal DROP CONSTRAINT [' + @pkName + N'];';
    EXEC sp_executesql @sql;
END

/* 3) Opret ny PK på Id (clustered) for enkel reference og ydeevne på punktopslag */
ALTER TABLE dbo.Cereal
    ADD CONSTRAINT PK_Cereal_Id PRIMARY KEY CLUSTERED (Id);

/* 4) Sikr fortsat unikhed på (name,mfr,type) via UNIQUE constraint
      (Bem.: tjekker på det forventede navn; hvis der findes en anden constraint med andet navn,
      så justér EXISTS-tjekket til at kigge på kolonne-sættet i stedet.) */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'UQ_Cereal_name_mfr_type' AND object_id = OBJECT_ID('dbo.Cereal')
)
BEGIN
    ALTER TABLE dbo.Cereal
        ADD CONSTRAINT UQ_Cereal_name_mfr_type UNIQUE (name, mfr, type);
END
