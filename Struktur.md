Forkortet Struktur til Slides.

```text
Legend (kort):
📁 mappe • 🧪 CI-workflow • 🐳 Docker/Compose • 🐚 Shell • 🛠️ PowerShell • 🔐 .env • ⚙️ config/json/yaml • 🧾 MD

📁 Specialisterne-DevOps
├─ 📁 .github
│  └─ 📁 workflows
│     ├─ 🧪 ci.yml                 ← Build, smoketest (Docker), push image
│     └─ 🧪 docs.yml               ← DocFX build + GitHub Pages deploy
├─ 📁 docs                         ← DocFX site
├─ 📁 docker
│  └─ 🐚 db-init.sh                ← Init DB (sqlcmd + scripts)
├─ 📁 Scripts
│  ├─ 🛠️ Build-Docs.ps1            ← Lokalt DocFX build/serve
│  └─ 🛠️ RunDocker.ps1             ← Lokal opstart/teardown
├─ 🐳 docker-compose.yml           ← db, db-init, api stack
├─ 🐳 Dockerfile                   ← API container build
├─ 🔐 .env                         ← SA_PASSWORD, CRUD_PASSWORD (lokalt)
├─ 🔐 .env.app                     ← Jwt__SigningKey (lokalt)
├─ 📁 Cereal API
│  └─ 📁 Cereal API
│     ├─ ⚙️ appsettings*.json
│     ├─ 🪪 Cereal API.csproj
│     ├─ 🧾 README.md
│     └─ …                         ← Kildekode (endpoints, utils, data)
├─ 🙈 .dockerignore
├─ 🙈 .gitignore
├─ 📜 LICENSE
└─ 🧾 README.md                    ← Drift/CI/CD/Swagger/Docker beskrivelse
```
