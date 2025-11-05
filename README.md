# Specialisterne-DevOps — Docker + CI/CD for *Cereal API*

Dette repo viser, hvordan et tidligere .NET-projekt containeriseres med **Docker/Compose** og bygges, testes og udgives via **GitHub Actions**.
Der er tilføjet **Swagger/OpenAPI**, en CI-venlig **Smoketest.CI.ps1** (PowerShell 7), samt opsætning til **GHCR** (GitHub Container Registry).

> **Framework:** .NET 9 • **Database:** SQL Server 2022 (Docker) • **Auth:** JWT (Bearer)
> **Lokal porte:** API `http://localhost:8080` (Compose) • Swagger `http://localhost:8080/swagger`

---

## Overblik (tjekliste)

* [x] Link til repo: *([Cereal API](https://github.com/saphyron/Uge-4-Opgave-1-API-Cereal))*
* [x] **Kørsel via Docker/Compose** (trin nedenfor)
* [x] **CI/CD-pipeline** beskrevet (jobs, secrets, artefakter)
* [x] **Tests**: hvordan de køres og tolkes (Smoketest + “OVERALL: PASS”)
* [x] **Deployment**: hvad der sker i hvert trin (push til GHCR + tags)
* [x] **Docstrings**: XML-kommentarer aktiveret, vises i Swagger

---

## Projektstruktur

```text
Legend (kort): 
📁 mappe • 🧩 C#-kode • ⚙️ config/json/yaml • 🪪 .sln/.csproj • 🧾 README/MD • 📑 CSV • 📊 Excel
🧱 SQL • 🛠️ PowerShell • 🐳 Dockerfile/Compose • 🐚 Shell-script • 🔐 .env • 🌐 HTTP-requests 
🖼️ Billeder • 📜 LICENSE • 🙈 ignore/dotfiles • 🧪 CI-workflow

📁 Specialisterne-DevOps
├─ 📁 .github
│  └─ 📁 workflows
│     ├─ 🧪 docs.yml
│     └─ 🧪 ci.yml
├─ 📁 Cereal API
│  ├─ 🪪 Cereal API.slnx
│  ├─ 🧾 README.md
│  ├─ 🙈 .gitignore
│  ├─ 📜 LICENSE
│  └─ 📁 Cereal API
│     ├─ 🪪 Cereal API.csproj
│     ├─ ⚙️ appsettings.json
│     ├─ ⚙️ appsettings.Development.json
│     ├─ 🧩 Program.cs
│     ├─ 🌐 Cereal API.http
│     ├─ 📁 src
│     │  ├─ 📁 Data
│     │  │  ├─ 📑 Cereal.csv
│     │  │  ├─ 📁 Repository
│     │  │  │  └─ 🧩 UserRepository.cs
│     │  │  └─ 🧩 SqlConnection.cs
│     │  ├─ 📁 Domain
│     │  │  ├─ 📁 Middleware
│     │  │  │  └─ 🧩 RequestloggingMiddleware.cs
│     │  │  └─ 📁 Models
│     │  │     ├─ 📁 Services  (tom)
│     │  │     ├─ 🧩 Cereal.cs
│     │  │     ├─ 🧩 ProductInsertDto.cs
│     │  │     ├─ 🧩 ProductQuery.cs
│     │  │     └─ 🧩 User.cs
│     │  ├─ 📁 Endpoints
│     │  │  ├─ 📁 Authentication
│     │  │  │  └─ 🧩 AuthenticationEndpoints.cs
│     │  │  ├─ 📁 CRUD
│     │  │  │  └─ 🧩 CRUDEndpoints.cs
│     │  │  ├─ 📁 Ops
│     │  │  │  └─ 🧩 OpsEndpoints.cs
│     │  │  └─ 📁 Product
│     │  │     └─ 🧩 ProductEndpoints.cs
│     │  ├─ 📁 Utils
│     │  │  ├─ 🧩 CsvParser.cs
│     │  │  ├─ 🧩 FilterParser.cs
│     │  │  ├─ 🧩 HttpHelpers.cs
│     │  │  ├─ 🧩 SortParser.cs
│     │  │  └─ 📁 Security
│     │  │     ├─ 🧩 Authz.cs
│     │  │     ├─ 🧩 JwtHelper.cs
│     │  │     └─ 🧩 PasswordHasher.cs
│     │  ├─ 📁 Properties
│     │  │  └─ ⚙️ launchSettings.json
│     │  ├─ 📁 Cereal Pictures
│     │  │  └─ 🖼️ *.jpg
│     │  └─ 📁 Logs  (tom, i .gitignore)
│     └─ 🙈 .gitignore
├─ 📁 Scripts
│  ├─ 🛠️ Build-Docs.ps1
│  └─ 🛠️ RunDocker.ps1
├─ 📁 docs
│  ├─ 🧾 index.md
│  ├─ ⚙️ docfx.json
│  ├─ 🧪 toc.yml
│  └─ 📁 articles
│      └─ 🧾 getting-started.md
├─ 📁 docker
│  └─ 🐚 db-init.sh
├─ 🐳 docker-compose.yml
├─ 🐳 Dockerfile
├─ 🔐 .env
├─ 🔐 .env.app
├─ 🙈 .dockerignore
├─ 🙈 .gitignore
├─ 📜 LICENSE
└─ 🧾 README.md
```

---

## Sådan startes projektet (Docker Compose)

### 1) Forudsætninger

* Docker Desktop (eller kompatibel runtime)

### 2) Miljøfiler

Opret to filer i projektroden, hvis du kører lokalt uden CI:

**`.env`**

```dotenv
SA_PASSWORD=YourStrong!Passw0rd
CRUD_PASSWORD=YourStrong!Passw0rd
```

**`.env.app`**

```dotenv
Jwt__SigningKey=CHANGE_ME_TO_A_LONG_RANDOM_SECRET_AT_LEAST_64_CHARS
```

> CI opretter de samme filer automatisk ud fra GitHub Secrets (se [CI/CD-pipeline](#cicd-pipeline-github-actions)).

### 3) Start stacken

```bash
docker compose up -d --build
```

* SQL Server kører som `db` på port **1433**.
* API kører som `api` på port **8080** (`http://localhost:8080`).

### 4) Sundhedstjek & Swagger

* Health: `GET http://localhost:8080/auth/health` → `{ "ok": true }`
* Swagger UI: `http://localhost:8080/swagger`
  (Swagger er aktiveret i **Development**; i produktion kan du sætte `Swagger__Enabled=true`.)

---

## CI/CD-pipeline (GitHub Actions)

Workflow: **`.github/workflows/ci.yml`**

### Trin (jobs)

1. **build-and-test** *(Windows)*

   * Tjekker ud, installerer .NET 9, `restore` og `build` API-projektet.
   * Forbereder, at kildekoden kompilérer på tværs af miljøer.

2. **smoketest** *(Ubuntu)*

   * Tjekker ud, opretter **.env** + **.env.app** fra **secrets**
     (`SA_PASSWORD`, `CRUD_PASSWORD`, `JWT_SECRET`).
   * Starter miljøet med `docker compose up -d --build`.
   * **Venter på health** (`/auth/health` → HTTP 200).
   * Kører **Smoketest.CI.ps1** (PowerShell 7).
   * Validerer, at loggen indeholder `OVERALL: PASS`.
   * **Uploader artefakter** (compose-logs, DB-schema, smoketest-log).
   * Rydder op (`docker compose down -v`).

3. **docker** *(Ubuntu)* — kører **kun hvis smoketest består**

   * Logger ind i **GHCR**.
   * Bygger og **pusher** image til `ghcr.io/<org>/<repo>/cereal-api` med tags:

     * `sha-<GITHUB_SHA>`
     * `latest`

### Secrets (kræves i repo/org)

* `SA_PASSWORD` – SA-kodeord til DB-container (kun CI/dev).
* `CRUD_PASSWORD` – kodeord til applikationens DB-bruger.
* `JWT_SECRET` – hemmelig nøgle til JWT-signering.

### Required checks (branch-regler) – forslag

* Kræv, at **ci** (workflow) er **grøn**, før PR kan merges.
* Kræv **review** + **linear history** (squash/rebase), hvis ønsket.

---

## Tests

### Lokalt (Windows PowerShell 5.1)

```powershell
# HTTPS eksempel (udviklingsport typisk 7257 i launchSettings)
powershell -ExecutionPolicy Bypass -File .\"Cereal API"\Scripts\Smoketest.ps1 -BaseUrl https://localhost:7257/
```

### CI (PowerShell 7 på Ubuntu)

Workflow kører:

```pwsh
pwsh -NoLogo -NoProfile -File Smoketest.CI.ps1 -BaseUrl 'http://localhost:8080/' -TopTake 5 -SkipRateLimit
```

**Tolkning:** Logfil skal indeholde linjen `OVERALL: PASS`.
CI stopper og fejler, hvis linjen ikke findes. Seneste log uploades som artefakt.

---

## Deployment

Denne pipeline udgiver et Docker-image til **GitHub Container Registry (GHCR)**:

* Registry: `ghcr.io`
* Repo: `ghcr.io/<org>/<repo>/cereal-api`
* Tags: `sha-<commit-sha>` og `latest`

**Kør i et eksternt miljø (eksempel):**

```bash
docker pull ghcr.io/<org>/<repo>/cereal-api:latest
docker run -d -p 8080:8080 \
  -e ConnectionStrings__Default="Server=<db-host>,1433;Database=CerealDb;User Id=CerealApiCrudUser;Password=<pwd>;Encrypt=True;TrustServerCertificate=true;MultipleActiveResultSets=true" \
  -e Jwt__SigningKey="<your-64+char-secret>" \
  --name cereal-api ghcr.io/<org>/<repo>/cereal-api:latest
```

> I Compose-produktion kan du bruge et separat `docker-compose.prod.yml` og/eller miljøvariabler fra en vault.

---

## API-dokumentation (Swagger/OpenAPI)

* Swagger er aktiv i **Development** eller hvis `Swagger__Enabled=true`.
* URL: `/swagger` (fx `http://localhost:8080/swagger`).
* **JWT i Swagger**: Klik **Authorize** og indsæt **kun token-strengen** (UI tilføjer `Bearer`).

XML-kommentarer (docstrings) er aktiveret i `Cereal API.csproj`:

```xml
<PropertyGroup>
  <GenerateDocumentationFile>true</GenerateDocumentationFile>
  <NoWarn>$(NoWarn);1591</NoWarn>
</PropertyGroup>
```

Swagger inkluderer automatisk XML-filen, hvis den findes i output.

---

## Vigtige ændringer i koden (DevOps-relateret)

* **Ny CI-smoketest**: `Smoketest.CI.ps1` (PowerShell 7) til GitHub Actions
  – den originale `Smoketest.ps1` (PS 5.1) beholdes til lokal Windows-kørsel.

* **CSV-import-endpoint**: skift til `IFormFile` for bedre **Swagger-integration** og mere stabil upload i Docker/CI:

  ```csharp
  app.MapPost("/ops/import-csv", async (IFormFile file, SqlConnectionCeral cereal) => { ... })
      .Accepts<IFormFile>("multipart/form-data")
      .WithTags("Ops");
  ```

* **Swagger**: tilføjet `AddSwaggerGen` + JWT-security-scheme i `Program.cs`.

* **HTTPS-redirect**: kun uden for Development (container bruger kun HTTP på 8080).

---

## Kørsel uden Docker (valgfrit)

1. SQL Server kørende lokalt (1433).
2. Opdatér `ConnectionStrings:Default` i `appsettings.Development.json`.
3. Kør:

```bash
cd "Cereal API/Cereal API"
dotnet run
```

* Standard: `http://localhost:5024; https://localhost:7257` (fra `launchSettings.json`).

---

## Kendte faldgruber

* **HTTPS i container**: Bruges ikke; API lytter HTTP på 8080. Undgå `UseHttpsRedirection()` i Development-container.
* **Workflow-sti**: Sørg for **`.github/workflows/ci.yml`** (ikke `workflow`).
* **Secrets i CI**: manglende `SA_PASSWORD`/`CRUD_PASSWORD`/`JWT_SECRET` får smoketest til at fejle tidligt.
* **Swagger i prod**: aktiver via `Swagger__Enabled=true`, hvis UI skal være offentligt (overvej auth/proxy).

---

## Licens

Se `LICENSE` i roden.

---

## Kontakt

* Issues/PRs er velkomne.
