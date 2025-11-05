# Kom i gang

Denne sektion forklarer kort, hvordan du kører API'et og hvor du finder Swagger.

## Forudsætninger
- Docker Desktop (for Compose) eller .NET 9 SDK
- SQL Server (Docker container leveres i repoet)

## Start med Docker Compose
```bash
docker compose up -d --build
```
- API: http://localhost:8080
- Swagger: http://localhost:8080/swagger

## Kør lokalt uden Docker
```bash
cd "Cereal API/Cereal API"
dotnet run
```
- Standardporte: `http://localhost:5024` og `https://localhost:7257`

## API-dokumentation
Denne side (DocFX) bygger en API-reference ud fra dine `///` docstrings.
Sørg for at `GenerateDocumentationFile` er slået til i csproj.
