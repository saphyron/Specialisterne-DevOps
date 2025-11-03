# Specialisterne-DevOps
Uge 8 DevOps. Arbejde med Dev Ops på en tidligere opgave.


```text
root
    .github
        workflow
            ci.yml
    Cereal API
        Cereal API
            src
                Cereal Pictures
                    *.jpg
                Data
                    Repository
                        UserRepository.cs
                    Cereal.csv
                    SqlConnection.cs
                Domain
                    Middleware
                        RequestloggingMiddleware.cs
                    Models
                        Services // Empty Folder for now
                        Cereal.cs
                        ProductInsertDto.cs
                        ProductQuery.cs
                        User.cs
                Endpoints
                    Authentication
                        AuthenticationEndpoints.cs
                    CRUD
                        CRUDEndpoints.cs
                    Ops
                        OpsEndpoint.cs
                    Product
                        ProductEndpoints.cs
                Properties
                    launchSettings.json
                Utils
                    Security
                        Authz.cs
                        JwtHelper.cs
                        PasswordHasher.cs
                    CsvParser.cs
                    FilterParser.cs
                    HttpHelpers.cs
                    SortParser.cs
                Logs    // Empty for now and part of gitignore
            appsettings.Development.json
            appsettings.json
            Cereal API.csproj
            Cereal API.http
            Program.cs
        Scripts
            Smoketest.ps1
            Smoketest2.ps1
        SQL Statements
            Create Table.sql
            Create User Table.sql
            Create User.sql
            Extra Queries.sql
        .gitignore
        Cereal API.slnx
        License
        README.md
    .gitignore
    LICENSE
    README.md
```