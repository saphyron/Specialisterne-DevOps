param(
    [string]$DocsPath,
    [int]$Port = 8081,
    [switch]$Serve
)

$ErrorActionPreference = 'Stop'

# Resolve docs folder (default: repoRoot\docs)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($DocsPath) {
  $docs = (Resolve-Path -LiteralPath $DocsPath).Path
} else {
  $repoRoot = Split-Path $here -Parent
  $docs = Join-Path $repoRoot 'docs'
}
if (-not (Test-Path (Join-Path $docs 'docfx.json'))) {
  throw "Could not find docfx.json in '$docs'. Use -DocsPath to point at your docs folder."
}

# Prefer dotnet tool docfx (newer), fall back to choco
$docfx = Get-Command docfx -ErrorAction SilentlyContinue
if (-not $docfx) {
  Write-Host "DocFX not found. Installing dotnet global tool..." -ForegroundColor Yellow
  dotnet tool update -g docfx | Out-Null
  $env:PATH = "$env:USERPROFILE\.dotnet\tools;$env:PATH"
  $docfx = Get-Command docfx -ErrorAction SilentlyContinue
  if (-not $docfx -and (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Falling back to Chocolatey..." -ForegroundColor Yellow
    choco install docfx -y | Out-Null
    $docfx = Get-Command docfx -ErrorAction SilentlyContinue
  }
}
if (-not $docfx) { throw "DocFX is not installed. Run: dotnet tool update -g docfx" }

Push-Location $docs
try {
  Write-Host "Using docfx: $($docfx.Source)" -ForegroundColor Cyan
  Write-Host "Generating metadata (TargetFramework=net8.0)..." -ForegroundColor Green
  docfx metadata docfx.json

  $apiPath = Join-Path $docs 'api'
  $ymlCount = (Get-ChildItem -Recurse -Filter *.yml -Path $apiPath -ErrorAction SilentlyContinue | Measure-Object).Count
  if (-not $ymlCount -or $ymlCount -eq 0) {
    Write-Error "No API YAML generated in '$apiPath'."
    Write-Host "Try manual metadata:" -ForegroundColor Yellow
    Write-Host "  docfx metadata `".\Cereal API\Cereal API\Cereal API.csproj`" -o `"$apiPath`" /p:TargetFramework=net8.0 -v d"
    throw "Metadata step produced 0 files."
  }

  Write-Host "Building site..." -ForegroundColor Green
  docfx build docfx.json

  if ($Serve) {
    Write-Host "Serving site on http://localhost:$Port (Ctrl+C to stop)" -ForegroundColor Green
    docfx serve _site -p $Port
  } else {
    $out = Join-Path $docs '_site\index.html'
    Write-Host "Done. Open: $out" -ForegroundColor Green
  }
}
finally {
  Pop-Location
}
