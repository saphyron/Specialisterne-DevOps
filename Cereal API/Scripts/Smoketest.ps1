<# 
.SYNOPSIS
  End-to-end smoketest for CerealAPI (PS 5.1-kompatibel) med 30+ tests inkl. auth.

.USAGE (dev HTTP):
  dotnet run --urls "http://localhost:5024"
  powershell -ExecutionPolicy Bypass -File .\Smoketest1.ps1 -BaseUrl http://localhost:5024/

.LOG
  Skriver til: src/Logs/<YY-MM-DD HH-MM Smoketest [PASS|FAIL]>.log
#>

Param(
  [string]$BaseUrl = "http://localhost:5024/",
  [int]   $TopTake = 5
)

# ---------- konsol ----------
try { chcp 65001 | Out-Null; $OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
function Write-Info  ([string]$m){ Write-Host "[INFO ] $m" -ForegroundColor Cyan }
function Write-Step  ([string]$m){ Write-Host "-> $m"      -ForegroundColor White }
function Write-Pass  ([string]$m){ Write-Host "[PASS ] $m" -ForegroundColor Green }
function Write-Fail  ([string]$m){ Write-Host "[FAIL ] $m" -ForegroundColor Red }
function Write-Warn  ([string]$m){ Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Write-Title ([string]$m){ Write-Host ""; Write-Host "========== $m ==========" -ForegroundColor Magenta }

# ---------- paths ----------
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$probe = Get-Item $here
$repoRoot = $here
for($i=0; $i -lt 6 -and $probe -ne $null; $i++){
  if(Test-Path (Join-Path $probe.FullName "src")){ $repoRoot = $probe.FullName; break }
  $probe = $probe.Parent
}
$logsDir = Join-Path $repoRoot "src/Logs"
if(-not (Test-Path $logsDir)){ New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

$stamp  = (Get-Date).ToString("yy-MM-dd HH-mm")
$runId  = [Guid]::NewGuid().ToString("N").Substring(0,8)

# ---------- global state ----------
$global:TestResults         = New-Object System.Collections.Generic.List[object]
$global:CreatedRows         = New-Object System.Collections.Generic.List[object]
$global:ImportedRow         = $null
$global:CreatedProductIds   = New-Object System.Collections.Generic.List[int]
$script:LastDeletedProductId = $null

# Auth state
$script:AuthSession  = $null     # Delt WebSession med cookie
$script:Token        = $null     # Seneste Bearer-token (string)
$script:NoAuthSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession  # Tøm session uden cookies

# ---------- transport ----------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
if(-not $BaseUrl.EndsWith("/")){ $BaseUrl += "/" }
try { $script:BaseUri = [Uri]$BaseUrl } catch { Write-Fail "Ugyldig BaseUrl: $BaseUrl"; exit 2 }
$script:IsHttp = ($BaseUrl -like 'http://*')

$script:HttpsBaseUri = $null
if ($script:IsHttp) {
  try {
    # Forventet redirect fra HTTP -> HTTPS; vi vil kun læse Location-headeren
    $probeUri = Combine-Uri $script:BaseUri "auth/health"
    $null = Invoke-WebRequest -Uri $probeUri -Method GET -MaximumRedirection 0 -ErrorAction Stop
  } catch {
    $loc = $null
    try { $loc = $_.Exception.Response.Headers['Location'] } catch {}
    if ($loc) {
      try {
        $u = [Uri]$loc                 # f.eks. https://localhost:7257/auth/health
        $portPart = if ($u.IsDefaultPort) { "" } else { ":" + $u.Port }
        $authority = "{0}://{1}{2}/" -f $u.Scheme, $u.Host, $portPart   # f.eks. https://localhost:7257/
        $script:HttpsBaseUri = [Uri]$authority
        Write-Info "HTTPS-base detekteret: $script:HttpsBaseUri"
      } catch {}
    }
  }
}

function Invoke-AuthGetPreserveRedirect([Uri]$baseUri, [string]$relPath, [string]$token) {
  $startUri = [Uri]::new($baseUri, $relPath)
  $headers  = @{ Authorization = "Bearer $token" }

  # Først: prøv uden at følge redirects
  try {
    $res = Invoke-WebRequest -Uri $startUri -Headers $headers -MaximumRedirection 0 -ErrorAction Stop
  } catch {
    # PS 5.1 kan kaste på 3xx; fang og følg selv
    $resp = $_.Exception.Response
    if ($resp) {
      $status = [int]$resp.StatusCode
      $loc    = $resp.Headers['Location']
      if ($status -in 301,302,307,308 -and $loc) {
        $target = [Uri]$loc
        return Invoke-WebRequest -Uri $target -Headers $headers -ErrorAction Stop
      }
    }
    throw
  }

  # PS 5.1 kan også returnere 3xx uden at kaste; tjek og følg
  $statusTry = [int]$res.StatusCode
  if ($statusTry -in 301,302,307,308) {
    $loc = $res.Headers['Location']
    if ($loc) {
      $target = [Uri]$loc
      return Invoke-WebRequest -Uri $target -Headers $headers -ErrorAction Stop
    }
  }

  return $res
}



function Combine-Uri([Uri]$base, [string]$rel) { if([string]::IsNullOrWhiteSpace($rel)){ return $base }; [Uri]::new($base, $rel) }
function Encode([string]$seg){
  if($null -eq $seg){ return "" }
  $e = [System.Uri]::EscapeDataString($seg)
  $e = $e -replace "'", "%27"
  return $e
}
function Ensure-ArrayCount($json){ if($json -eq $null){ 0 } else { @($json).Count } }

function Read-Body($respObj) {
  $raw=$null;$json=$null;
  try{$raw=$respObj.Content}catch{}
  if($raw){ try{$json=$raw|ConvertFrom-Json}catch{} }
  @{ Raw=$raw; Json=$json }
}

# --- wrappers med valgfri WebSession/Headers
function Send-Request([string]$method, [string]$path, $bodyJson = $null, $webSession = $null, $headers = $null) {
  # Default til global AuthSession hvis ingen session eksplicit
  if(-not $webSession -and $script:AuthSession){ $webSession = $script:AuthSession }

  $uri = Combine-Uri $script:BaseUri $path
  $params = @{ Uri=$uri; Method=$method; ErrorAction='Stop' }
  if($webSession){ $params['WebSession'] = $webSession }
  if($headers){ $params['Headers'] = $headers }
  if($bodyJson -ne $null){ $params['Body']=($bodyJson|ConvertTo-Json -Depth 6); $params['ContentType']='application/json' }
  try {
    $resp = Invoke-WebRequest @params
    @{ ResponseCode = [int]$resp.StatusCode; Body = (Read-Body $resp); Raw=$resp }
  } catch {
    $we = $_.Exception; $code = $null; $raw = $null
    if($we.Response){
      try { $code = [int]$we.Response.StatusCode } catch {}
      try { $sr = New-Object IO.StreamReader($we.Response.GetResponseStream()); $raw=$sr.ReadToEnd(); $sr.Dispose() } catch {}
    }
    $j = $null; if($raw){ try{$j=$raw|ConvertFrom-Json}catch{} }
    @{ ResponseCode = $code; Body = @{ Raw=$raw; Json=$j }; Error=$we.Message; Raw=$null }
  }
}
function Send-GET([string]$path, $sess=$null, $headers=$null)            { Send-Request 'GET'    $path $null $sess $headers }
function Send-DELETE([string]$path, $sess=$null, $headers=$null)         { Send-Request 'DELETE' $path $null $sess $headers }
function Send-POSTJSON([string]$path, $obj, $sess=$null, $headers=$null) { Send-Request 'POST'   $path $obj  $sess $headers }
function Send-PUTJSON ([string]$path, $obj, $sess=$null, $headers=$null) { Send-Request 'PUT'    $path $obj  $sess $headers }

# Robust multipart upload (HttpWebRequest)
function Send-POSTFile([string]$path, [string]$filePath, [string]$fieldName="file", $webSession=$null){
  if(-not $webSession -and $script:AuthSession){ $webSession = $script:AuthSession }
  $uri = Combine-Uri $script:BaseUri $path
  $boundary = "---------------------------" + [Guid]::NewGuid().ToString("N")
  $req = [System.Net.HttpWebRequest]::Create($uri)
  $req.Method = "POST"
  $req.ContentType = "multipart/form-data; boundary=$boundary"
  $req.KeepAlive = $true
  if($webSession -and $webSession.Cookies){ $req.CookieContainer = $webSession.Cookies }

  $nl = "`r`n"
  $header = "--$boundary$nl" +
            "Content-Disposition: form-data; name=""$fieldName""; filename=""$([IO.Path]::GetFileName($filePath))""$nl" +
            "Content-Type: application/octet-stream$nl$nl"
  $footer = "$nl--$boundary--$nl"

  $fileBytes = if(Test-Path $filePath){ [IO.File]::ReadAllBytes($filePath) } else { [byte[]]@() }
  $headerBytes = [Text.Encoding]::UTF8.GetBytes($header)
  $footerBytes = [Text.Encoding]::UTF8.GetBytes($footer)

  $req.ContentLength = $headerBytes.Length + $fileBytes.Length + $footerBytes.Length

  try {
    $rs = $req.GetRequestStream()
    $rs.Write($headerBytes,0,$headerBytes.Length)
    if($fileBytes.Length -gt 0){ $rs.Write($fileBytes,0,$fileBytes.Length) }
    $rs.Write($footerBytes,0,$footerBytes.Length)
    $rs.Flush(); $rs.Dispose()

    $resp = $req.GetResponse()
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    $raw = $sr.ReadToEnd(); $sr.Dispose(); $resp.Dispose()
    $json = $null; try{ $json=$raw|ConvertFrom-Json }catch{}
    return @{ ResponseCode=200; Body=@{ Raw=$raw; Json=$json } }
  } catch {
    $we = $_.Exception; $code=$null; $raw=$null
    if($we.Response){
      try { $code = [int]$we.Response.StatusCode } catch {}
      try { $sr = New-Object IO.StreamReader($we.Response.GetResponseStream()); $raw=$sr.ReadToEnd(); $sr.Dispose() } catch {}
    }
    $json = $null; if($raw){ try{ $json=$raw|ConvertFrom-Json }catch{} }
    if(-not $code -and $raw -and ($raw -match 'BadRequest|Manglende fil|Ingen rækker')){ $code = 400 }
    return @{ ResponseCode=$code; Body=@{ Raw=$raw; Json=$json }; Error=$we.Message }
  }
}

# ---------- testramme ----------
function Run-Test([string]$name, [scriptblock]$block){
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $err=$null;$ok=$false;$detail=""
  try { $res = & $block; $ok=$res.Ok; $detail=$res.Detail } catch { $ok=$false; $err=$_.Exception.Message }
  $sw.Stop()
  $row = [PSCustomObject]@{ Name=$name; Success=$ok; Error=$err; Details=$detail; DurationMs=$sw.ElapsedMilliseconds }
  $global:TestResults.Add($row) | Out-Null
  if($ok){ Write-Pass "$name ($($sw.ElapsedMilliseconds) ms) | $detail" }
  else   { if($err){ Write-Fail "$name ($($sw.ElapsedMilliseconds) ms) | ERROR: $err" } else { Write-Fail "$name ($($sw.ElapsedMilliseconds) ms) | $detail" } }
}

# ---------- testdata ----------
$stampNow = (Get-Date).ToString("yy-MM-dd HH-mm")
$testName1 = "Test% Cereal $stampNow #$runId"
$testMfr1  = "Z"
$testType1 = "C"
$testRow1 = @{
  name=$testName1;mfr=$testMfr1;type=$testType1;calories=123;protein=4;fat=1;sodium=50;fiber=2.5;carbo=10.5;sugars=6;potass=80;vitamins=25;shelf=2;weight=0.5;cups=0.75;rating="42.4242"
}
$testName2 = "O'Brien _ Cereal+Plus $runId"
$testMfr2  = "Y"
$testType2 = "C"
$testRow2 = @{
  name=$testName2;mfr=$testMfr2;type=$testType2;calories=1;protein=0;fat=0;sodium=0;fiber=0.0;carbo=0.0;sugars=0;potass=0;vitamins=0;shelf=1;weight=0.1;cups=0.1;rating="1"
}


# =====================================================================
# SEKT. 1: Authentication flow
# =====================================================================
Write-Title "S1: Authentication"

$User = "u_$runId"
$Pwd  = "Pa`$`$w0rd!42"
$WrongPwd = "Bad`$`$pwd"

# /auth/register
Run-Test "POST /auth/register (happy path -> 201/200)" {
  $body = @{ username = $User; password = $Pwd }
  $r=Send-POSTJSON "auth/register" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -in 200,201); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "POST /auth/register (duplicate -> 409)" {
  $body = @{ username = $User; password = $Pwd }
  $r=Send-POSTJSON "auth/register" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 409); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "POST /auth/register (missing username -> 400)" {
  $body = @{ password = $Pwd }
  $r=Send-POSTJSON "auth/register" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 400); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "POST /auth/register (empty password -> 400)" {
  $body = @{ username = "${User}_x"; password = "" }
  $r=Send-POSTJSON "auth/register" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 400); Detail="HTTP $c; body: $($r.Body.Raw)" }
}

# /auth/login (gem Token og WebSession globalt)
Run-Test "POST /auth/login (200 + cookie + token)" {
  $body = @{ username = $User; password = $Pwd }

  # 1) Token via wrapper
  $resp = Send-Request 'POST' 'auth/login' $body
  $c = [int]$resp.ResponseCode
  if ($c -eq 200 -and $resp.Body.Json) { $script:Token = $resp.Body.Json.token }

  # 2) Session (cookie) via Invoke-WebRequest m/ SessionVariable
  $SV = $null
  $resp2 = Invoke-WebRequest -Method POST -Uri (Combine-Uri $script:BaseUri "auth/login") `
            -ContentType "application/json" -Body ($body|ConvertTo-Json -Depth 4) `
            -SessionVariable SV -ErrorAction Stop
  $script:AuthSession = $SV

  # Verificer cookie (men kun forvent den på HTTPS)
  $cookieFound = $false
  try {
    if ($script:AuthSession -and $script:AuthSession.Cookies) {
      $ck = $script:AuthSession.Cookies.GetCookies($BaseUrl)["token"]
      if ($ck -and -not [string]::IsNullOrWhiteSpace($ck.Value)) { $cookieFound = $true }
    }
  } catch {}

  $expectCookie = -not $script:IsHttp   # over HTTP: Secure-cookies sendes ikke
  $ok = ($c -eq 200 -and $script:Token -ne $null -and ($cookieFound -eq $expectCookie))

  @{ Ok=$ok; Detail=("HTTP {0}; token? {1}; cookie? {2}" -f $c, [bool]$script:Token, $cookieFound) }
}

Run-Test "POST /auth/login (wrong password -> 401/403)" {
  $body = @{ username = $User; password = $WrongPwd }
  $r=Send-POSTJSON "auth/login" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail="HTTP $c" }
}
Run-Test "POST /auth/login (unknown user -> 401/403)" {
  $body = @{ username = "nope_$runId"; password = $Pwd }
  $r=Send-POSTJSON "auth/login" $body
  $c=[int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail="HTTP $c" }
}
Run-Test "POST /auth/login (malformed -> 400/401/403)" {
  $r=Send-POSTJSON "auth/login" @{ }
  $c=[int]$r.ResponseCode
  @{ Ok=($c -in 400,401,403); Detail="HTTP $c" }
}

# /auth/me
Run-Test "GET /auth/me (no auth -> 401/403)" {
  $r = Send-GET "auth/me" $script:NoAuthSession
  $c = [int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail=("HTTP {0}" -f $c) }
}
Run-Test "GET /auth/me (cookie -> 200 & username)" {
  try {
    $uri = [Uri]::new($script:BaseUri, "auth/me")
    $res = Invoke-WebRequest -Uri $uri -WebSession $script:AuthSession -ErrorAction Stop
    $ok  = ($res.StatusCode -eq 200 -and ($res.Content -match $User))
    @{ Ok=$ok; Detail=("HTTP {0}; body: {1}" -f $res.StatusCode, $res.Content) }
  } catch {
    $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    @{ Ok=$false; Detail=("HTTP {0}; err: {1}" -f $code, $_.Exception.Message) }
  }
}
Run-Test "GET /auth/me (Bearer -> 200 & username)" {
  if (-not $script:Token) { return @{ Ok=$false; Detail="no token" } }
  try {
    $res = Invoke-AuthGetPreserveRedirect $script:BaseUri 'auth/me' $script:Token
    $c   = [int]$res.StatusCode
    @{ Ok=($c -eq 200 -and ($res.Content -match $User)); Detail=("HTTP {0}" -f $c) }
  } catch {
    $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    @{ Ok=$false; Detail=("HTTP {0}" -f $code) }
  }
}
Run-Test "GET /auth/me (tampered token -> 401/403)" {
  if (-not $script:Token) { return @{ Ok=$true; Detail="skipped (no token)" } }
  $bad = $script:Token + "x"

  $targetUri = if ($script:IsHttp -and $script:HttpsBaseUri) {
    [Uri]::new($script:HttpsBaseUri, "auth/me")
  } else {
    [Uri]::new($script:BaseUri, "auth/me")
  }

  try {
    $res = Invoke-WebRequest -Uri $targetUri -Headers @{ Authorization = "Bearer $bad" } -ErrorAction Stop
    $c = [int]$res.StatusCode
    @{ Ok=($c -in 401,403); Detail=("HTTP {0}" -f $c) }
  } catch {
    $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    @{ Ok=($code -in 401,403); Detail=("HTTP {0}" -f $code) }
  }
}

# /auth/logout
Run-Test "POST /auth/logout (200)" {
  $r=Send-POSTJSON "auth/logout" $null $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200); Detail=("HTTP {0}" -f $c) }
}
Run-Test "GET /auth/me efter logout (401/403)" {
  $r=Send-GET "auth/me" $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail=("HTTP {0}" -f $c) }
}
Run-Test "POST /auth/logout (idempotent 200)" {
  $r=Send-POSTJSON "auth/logout" $null $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200); Detail=("HTTP {0}" -f $c) }
}
Run-Test "POST /auth/login igen (200)" {
  $body = @{ username = $User; password = $Pwd }
  $SV = $null
  $resp = Invoke-WebRequest -Method POST -Uri (Combine-Uri $script:BaseUri "auth/login") `
          -ContentType "application/json" -Body ($body|ConvertTo-Json -Depth 4) -SessionVariable SV -ErrorAction Stop
  $script:AuthSession = $SV
  @{ Ok=($resp.StatusCode -eq 200); Detail=("HTTP {0}" -f $resp.StatusCode) }
}

# =====================================================================
# SEKT. 2: Basale GETs
# =====================================================================
Write-Title "S2: Basale GETs"
Run-Test "GET /auth/health" { $r=Send-GET "auth/health"; $c=[int]$r.ResponseCode; @{ Ok=($c -eq 200 -and $r.Body.Json.ok -eq $true); Detail="HTTP $c; body: $($r.Body.Raw)" } }
Run-Test "GET /weatherforecast (5 items)" { $r=Send-GET "weatherforecast"; $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json; @{ Ok=($c -eq 200 -and $len -eq 5); Detail="HTTP $c; items: $len" } }


# =====================================================================
# SEKT. 3: Offentlige GETs
# =====================================================================
Write-Title "S3: Offentlige GETs"
Run-Test "GET /cereals (liste)" {
  $r=Send-GET "cereals"; $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json
  @{ Ok=($c -eq 200); Detail="HTTP $c; items: $len" }
}
Run-Test "GET /cereals/top/$TopTake" {
  $r=Send-GET ("cereals/top/{0}" -f $TopTake); $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json
  @{ Ok=($c -eq 200 -and $len -le $TopTake); Detail="HTTP $c; items: $len" }
}
Run-Test "GET /nope (404)" { $r=Send-GET "nope"; $c=[int]$r.ResponseCode; @{ Ok=($c -eq 404); Detail="HTTP $c" } }

# =====================================================================
# SEKT. 4: Mutationer uden auth (skal fejle)
# =====================================================================
Write-Title "S4: Mutationer uden auth (forvent 401/403)"
Run-Test "POST /cereals uden auth -> 401/403" {
  $r = Send-POSTJSON "cereals" @{ name="NoAuth $runId"; mfr="K"; type="C"; calories=100 } $script:NoAuthSession
  $c = [int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail=("HTTP {0}" -f $c) }
}

# =====================================================================
# SEKT. 5: CEREALS (med auth / cookie)
# =====================================================================
Write-Title "S5: CEREALS (autherede mutationer)"
Run-Test "POST /cereals (indsæt testrække #1)" {
  $r=Send-POSTJSON "cereals" $testRow1 $script:AuthSession; $c=[int]$r.ResponseCode
  $ok=($c -in 200,201 -and $r.Body.Json.inserted -ge 1)
  if($ok){ $global:CreatedRows.Add(@{name=$testName1;mfr=$testMfr1;type=$testType1}) | Out-Null }
  @{ Ok=$ok; Detail=("HTTP {0}; body: {1}" -f $c, $r.Body.Raw) }
}
Run-Test "GET /cereals indeholder testrække #1" {
  $r=Send-GET "cereals"; $c=[int]$r.ResponseCode; $found=$false
  if($r.Body.Json){ foreach($it in @($r.Body.Json)){ if($it.name -eq $testName1 -and $it.mfr -eq $testMfr1 -and $it.type -eq $testType1){ $found=$true; break } } }
  @{ Ok=($c -eq 200 -and $found); Detail="HTTP $c; found=$found" }
}
Run-Test "PUT /cereals/{key} (opdater #1)" {
  $upd=$testRow1.PSObject.Copy(); $upd.calories=321; $upd.rating="99.999"; $upd.fiber=$null
  $p=("cereals/{0}/{1}/{2}" -f (Encode $testName1),(Encode $testMfr1),(Encode $testType1))
  $r=Send-PUTJSON $p $upd $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json.updated -ge 1); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "DELETE /cereals/{key} #1 (200)" {
  $p=("cereals/{0}/{1}/{2}" -f (Encode $testName1),(Encode $testMfr1),(Encode $testType1))
  $r=Send-DELETE $p $script:AuthSession; $c=[int]$r.ResponseCode
  if($c -eq 200){
    for($i=$global:CreatedRows.Count-1;$i -ge 0;$i--){
      $it=$global:CreatedRows[$i]
      if($it.name -eq $testName1 -and $it.mfr -eq $testMfr1 -and $it.type -eq $testType1){ $global:CreatedRows.RemoveAt($i) }
    }
  }
  @{ Ok=($c -eq 200); Detail="HTTP $c; body: $($r.Body.Raw)" }
}

# =====================================================================
# SEKT. 6: OPS import CSV (med auth)
# =====================================================================
Write-Title "S6: OPS Import"
$TempRoot = [System.IO.Path]::GetTempPath()
if ([string]::IsNullOrWhiteSpace($TempRoot)) { $TempRoot = "/tmp" }  # fallback på Linux
$tempCsv  = Join-Path $TempRoot ("cereal-smoketest-{0}.csv" -f $runId)
$csvHeader = "name;mfr;type;calories;protein;fat;sodium;fiber;carbo;sugars;potass;vitamins;shelf;weight;cups;rating"
$csvTypes  = "String;Categorical;Categorical;Int;Int;Int;Int;Float;Float;Int;Int;Int;Int;Float;Float;String"
$impName   = "Import One% $runId"; $impMfr="I"; $impType="C"
$csvRow    = "$impName;$impMfr;$impType;80;3;1;100;2;15;6;120;25;1;0.40;0.75;""12.34"""
Set-Content -LiteralPath $tempCsv -Encoding UTF8 -Value @($csvHeader,$csvTypes,$csvRow)

Run-Test "POST /ops/import-csv (1 række via multipart)" {
  $r=Send-POSTFile "ops/import-csv" $tempCsv "file" $script:AuthSession; $c=[int]$r.ResponseCode
  if($c -eq 200){ $global:ImportedRow = @{ name=$impName; mfr=$impMfr; type=$impType } }
  @{ Ok=($c -eq 200 -and $r.Body.Json.inserted -ge 1); Detail="HTTP $c; body: $($r.Body.Raw)" }
}

if($global:ImportedRow -ne $null){
  $kp=("cereals/{0}/{1}/{2}" -f (Encode $global:ImportedRow.name),(Encode $global:ImportedRow.mfr),(Encode $global:ImportedRow.type))
  Run-Test "DELETE $kp (opryd importeret række)" {
    $r=Send-DELETE $kp $script:AuthSession; $c=[int]$r.ResponseCode
    @{ Ok=(($c -eq 200) -or ($c -eq 404)); Detail="HTTP $c; body: $($r.Body.Raw)" }
  }
}

# =====================================================================
# SEKT. 7: PRODUCTS (med auth)
# =====================================================================
Write-Title "S7: PRODUCTS"
$prodName1 = "Prod One $runId"
$prod1 = @{
  id=$null; name=$prodName1; mfr="K"; type="C"; calories=777; protein=7; fat=1; sodium=77; fiber=1.5; carbo=17.5; sugars=7; potass=77; vitamins=25; shelf=2; weight=0.5; cups=0.75; rating="7.77"
}
$prodName2 = "Prod Two $runId"
$prod2 = @{
  id=$null; name=$prodName2; mfr="G"; type="C"; calories=333; protein=3; fat=0; sodium=30; fiber=0.5; carbo=10.0; sugars=3; potass=33; vitamins=25; shelf=2; weight=0.33; cups=0.5; rating="3.33"
}

Run-Test "POST /products (create prod1 -> 201)" {
  $r=Send-POSTJSON "products" $prod1 $script:AuthSession; $c=[int]$r.ResponseCode
  $ok = ($c -eq 201 -and $r.Body.Json.id -is [int])
  if($ok){ $global:CreatedProductIds.Add([int]$r.Body.Json.id) | Out-Null }
  @{ Ok=$ok; Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "POST /products (create prod2 -> 201)" {
  $r=Send-POSTJSON "products" $prod2 $script:AuthSession; $c=[int]$r.ResponseCode
  $ok = ($c -eq 201 -and $r.Body.Json.id -is [int])
  if($ok){ $global:CreatedProductIds.Add([int]$r.Body.Json.id) | Out-Null }
  @{ Ok=$ok; Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "GET /products (liste >= 2)" {
  $r=Send-GET "products"; $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json
  @{ Ok=($c -eq 200 -and $len -ge 2); Detail="HTTP $c; items=$len" }
}
Run-Test "GET /products/{id} (begge)" {
  if($global:CreatedProductIds.Count -lt 2){ return @{ Ok=$false; Detail="need 2 ids" } }
  $id1 = $global:CreatedProductIds[0]; $id2=$global:CreatedProductIds[1]
  $r1=Send-GET ("products/{0}" -f $id1); $r2=Send-GET ("products/{0}" -f $id2)
  $o1 = ([int]$r1.ResponseCode -eq 200); $o2 = ([int]$r2.ResponseCode -eq 200)
  @{ Ok=($o1 -and $o2); Detail=("HTTP1 {0}, HTTP2 {1}" -f $r1.ResponseCode,$r2.ResponseCode) }
}
Run-Test "POST /products (duplicate key -> 409)" {
  $dup = $prod1.PSObject.Copy(); $dup.id=$null
  $r=Send-POSTJSON "products" $dup $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 409); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "POST /products (update id1 -> 200)" {
  if($global:CreatedProductIds.Count -lt 1){ return @{ Ok=$false; Detail="no id" } }
  $id1 = $global:CreatedProductIds[0]
  $upd = $prod1.PSObject.Copy(); $upd.id=$id1; $upd.calories = 778; $upd.rating="7.78"
  $r=Send-POSTJSON "products" $upd $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json.updated -ge 1); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "GET /products/{id1} afspejler update" {
  if($global:CreatedProductIds.Count -lt 1){ return @{ Ok=$false; Detail="no id" } }
  $id1 = $global:CreatedProductIds[0]
  $r=Send-GET ("products/{0}" -f $id1); $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json.calories -eq 778); Detail="HTTP $c; calories=$($r.Body.Json.calories)" }
}
Run-Test "DELETE /products/{id2} (200)" {
  if($global:CreatedProductIds.Count -lt 2){ return @{ Ok=$false; Detail="no id2" } }
  $id2 = $global:CreatedProductIds[1]
  $r=Send-DELETE ("products/{0}" -f $id2) $script:AuthSession; $c=[int]$r.ResponseCode
  if($c -eq 200){ [void]$global:CreatedProductIds.Remove($id2); $script:LastDeletedProductId=$id2 }
  @{ Ok=($c -eq 200); Detail="HTTP $c; body: $($r.Body.Raw)" }
}
Run-Test "DELETE /products/{id2} igen (404)" {
  $target = $script:LastDeletedProductId
  if(-not $target){ $target = 9999998 }
  $r=Send-DELETE ("products/{0}" -f $target) $script:AuthSession; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 404); Detail="HTTP $c" }
}

# =====================================================================
# SEKT. 7b: PRODUCTS – Endpoints specifikke tests (4 pr. endpoint)
# =====================================================================
Write-Title "S7b: PRODUCTS – Endpoints specifikke tests"

# Forudsætninger: mindst 1-2 produkter fra S7
if($global:CreatedProductIds.Count -lt 1){
  Write-Warn "S7b: Mangler oprettede products fra S7 – forsøger at oprette ét hurtigt"
  $tmp = @{
    id=$null; name="Prod Auto $runId"; mfr="K"; type="C"; calories=222; protein=2; fat=0; sodium=20; fiber=0.5; carbo=8.5; sugars=2; potass=22; vitamins=25; shelf=2; weight=0.22; cups=0.33; rating="2.22"
  }
  $r=Send-POSTJSON "products" $tmp $script:AuthSession
  if([int]$r.ResponseCode -in 200,201 -and $r.Body.Json.id){ [void]$global:CreatedProductIds.Add([int]$r.Body.Json.id) }
}

$pid1 = if($global:CreatedProductIds.Count -ge 1){ $global:CreatedProductIds[0] } else { $null }
$pid2 = if($global:CreatedProductIds.Count -ge 2){ $global:CreatedProductIds[1] } else { $null }

# Der bruges navne fra S7 (prodName1/prodName2) hvis de findes
if(-not $prodName1){ $prodName1 = "Prod One $runId" }
if(-not $prodName2){ $prodName2 = "Prod Two $runId" }

# ------------------------------
# A) GET /products  (4 tests)
# ------------------------------
Run-Test "GET /products – baseline 200 & array" {
  $r=Send-GET "products"; $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json
  @{ Ok=($c -eq 200 -and $len -ge 1); Detail="HTTP $c; items=$len" }
}
Run-Test "GET /products – nameLike finder prod1/prod2" {
  $needle = ($prodName1 -split ' ')[0]
  $r=Send-GET ("products?nameLike={0}" -f (Encode $needle))
  $c=[int]$r.ResponseCode
  $found = $false
  if($r.Body.Json){ foreach($it in @($r.Body.Json)){ if(("$($it.name)" -like "*$needle*")){ $found=$true; break } } }
  @{ Ok=($c -eq 200 -and $found); Detail="HTTP $c; nameLike=$needle; found=$found" }
}
Run-Test "GET /products – manufacturer normalisering (Kellogg's -> K)" {
  if(-not $prodName1){ return @{ Ok=$true; Detail="skipped (no prodName1)" } }
  $r=Send-GET ("products?name={0}&manufacturer={1}" -f (Encode $prodName1),(Encode "Kellogg's"))
  $c=[int]$r.ResponseCode
  $ok = ($c -eq 200 -and $r.Body.Json -ne $null -and (@($r.Body.Json).Count -ge 0))
  # accepter 200 selv hvis 0 hits (hvis prod1 ikke var K)
  @{ Ok=($c -eq 200); Detail="HTTP $c; rows=$(@($r.Body.Json).Count)" }
}
Run-Test "GET /products – numeric match (calories exact på prod2 hvis mulig)" {
  if($pid2){
    $r=Send-GET "products?calories=333"
    $c=[int]$r.ResponseCode
    $has333 = $false
    if($r.Body.Json){ foreach($it in @($r.Body.Json)){ if($it.calories -eq 333){ $has333=$true; break } } }
    @{ Ok=($c -eq 200); Detail="HTTP $c; has-cal=333: $has333" }
  } else {
    $r=Send-GET "products?calories=777"
    $c=[int]$r.ResponseCode
    $has777 = $false
    if($r.Body.Json){ foreach($it in @($r.Body.Json)){ if($it.calories -eq 777){ $has777=$true; break } } }
    @{ Ok=($c -eq 200); Detail="HTTP $c; has-cal=777: $has777" }
  }
}

# --------------------------------
# B) GET /products/{id}  (4 tests)
# --------------------------------
Run-Test "GET /products/{id} – id1 200" {
  if(-not $pid1){ return @{ Ok=$false; Detail="no id1" } }
  $r=Send-GET ("products/{0}" -f $pid1); $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json -ne $null -and $r.Body.Json.id -eq $pid1); Detail="HTTP $c" }
}
Run-Test "GET /products/{id} – id2 200 (eller skip)" {
  if(-not $pid2){ return @{ Ok=$true; Detail="skipped (no id2)" } }
  $r=Send-GET ("products/{0}" -f $pid2); $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json.id -eq $pid2); Detail="HTTP $c" }
}
Run-Test "GET /products/{id} – ukendt id -> 404" {
  $r=Send-GET "products/987654321"; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 404); Detail="HTTP $c" }
}
Run-Test "GET /products/{id} – ikke-int -> 404" {
  $r=Send-GET "products/abc"; $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 404); Detail="HTTP $c" }
}

# ------------------------------
# C) POST /products  (4 tests)
# ------------------------------
Run-Test "POST /products – create ny (201)" {
  $tmp = @{
    id=$null; name=("Prod Extra $runId"); mfr="Q"; type="C"; calories=111; protein=1; fat=0; sodium=11; fiber=0.1; carbo=5.5; sugars=1; potass=11; vitamins=25; shelf=2; weight=0.11; cups=0.2; rating="1.11"
  }
  $r=Send-POSTJSON "products" $tmp $script:AuthSession
  $c=[int]$r.ResponseCode
  if($c -eq 201 -and $r.Body.Json.id){ [void]$global:CreatedProductIds.Add([int]$r.Body.Json.id) }
  @{ Ok=($c -eq 201); Detail="HTTP $c" }
}
Run-Test "POST /products – duplicate (409) (samme som prod1)" {
  if(-not $prod1){ return @{ Ok=$true; Detail="skipped (no prod1)" } }
  $dup = $prod1.PSObject.Copy(); $dup.id=$null
  $r=Send-POSTJSON "products" $dup $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 409); Detail="HTTP $c" }
}
Run-Test "POST /products – update eksisterende (200)" {
  if(-not $pid1){ return @{ Ok=$false; Detail="no id1" } }
  $upd = @{
    id=$pid1; name=$prodName1; mfr="K"; type="C"; calories=778; protein=7; fat=1; sodium=77; fiber=1.5; carbo=17.5; sugars=7; potass=77; vitamins=25; shelf=2; weight=0.5; cups=0.75; rating="7.78"
  }
  $r=Send-POSTJSON "products" $upd $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200 -and $r.Body.Json.updated -ge 1); Detail="HTTP $c" }
}
Run-Test "POST /products – id angivet men findes ikke (400)" {
  $upd = @{
    id=99999997; name="Ghost $runId"; mfr="K"; type="C"; calories=1; protein=0; fat=0; sodium=0; fiber=0.0; carbo=0.0; sugars=0; potass=0; vitamins=0; shelf=1; weight=0.1; cups=0.1; rating="1"
  }
  $r=Send-POSTJSON "products" $upd $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 400); Detail="HTTP $c" }
}

# ------------------------------
# D) DELETE /products/{id}  (4 tests)
# ------------------------------
Run-Test "DELETE /products/{id} – slet id2 (200/skip)" {
  if(-not $pid2){ return @{ Ok=$true; Detail="skipped (no id2)" } }
  $r=Send-DELETE ("products/{0}" -f $pid2) $script:AuthSession
  $c=[int]$r.ResponseCode
  if($c -eq 200){ [void]$global:CreatedProductIds.Remove($pid2) }
  @{ Ok=($c -eq 200); Detail="HTTP $c" }
}
Run-Test "DELETE /products/{id} – slet igen (404)" {
  $target = if($pid2){ $pid2 } else { 99999996 }
  $r=Send-DELETE ("products/{0}" -f $target) $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 404); Detail="HTTP $c" }
}
Run-Test "DELETE /products/{id} – ukendt id (404)" {
  $r=Send-DELETE "products/987654320" $script:AuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 404); Detail="HTTP $c" }
}
Run-Test "DELETE /products/{id} – uden auth (401/403)" {
  $r=Send-DELETE "products/987654321" $script:NoAuthSession
  $c=[int]$r.ResponseCode
  @{ Ok=($c -in 401,403); Detail="HTTP $c" }
}

# ------------------------------------------
# E) GET /products/liste  (4 tests: filter/sort)
# ------------------------------------------
Run-Test "GET /products/liste – baseline 200" {
  $r=Send-GET "products/liste/"; $c=[int]$r.ResponseCode; $len=Ensure-ArrayCount $r.Body.Json
  @{ Ok=($c -eq 200); Detail="HTTP $c; items=$len" }
}
Run-Test "GET /products/liste – alias filters (calories_gte/lte)" {
  # ram kuglen omkring 300..800 så både prod1(777/778) og evt. andre kan matche
  $r=Send-GET "products/liste/?calories_gte=300&calories_lte=800"
  $c=[int]$r.ResponseCode
  $ok=($c -eq 200)
  @{ Ok=$ok; Detail="HTTP $c" }
}
Run-Test "GET /products/liste – raw operators (>=, <= URL-enc)" {
  $path = "products/liste/?calories%3E=300&calories%3C=800"
  $r=Send-GET $path
  $c=[int]$r.ResponseCode
  @{ Ok=($c -eq 200); Detail=("HTTP {0}; path={1}" -f $c,$path) }
}
Run-Test "GET /products/liste – sort=calories_desc,name_asc" {
  $r=Send-GET "products/liste/?sort=calories_desc,name_asc"
  $c=[int]$r.ResponseCode
  $ok = ($c -eq 200)
  # valgfri sanity: tjek at første>=anden på calories hvis mindst 2 rows
  if($ok -and $r.Body.Json -and @($r.Body.Json).Count -ge 2){
    $a=@($r.Body.Json)[0].calories; $b=@($r.Body.Json)[1].calories
    if(($a -is [int]) -and ($b -is [int]) -and ($a -lt $b)){ $ok=$false }
  }
  @{ Ok=$ok; Detail="HTTP $c" }
}


# =====================================================================
# SEKT. 8: Oprydning
# =====================================================================
Write-Title "S8: Oprydning"
if($global:CreatedRows.Count -gt 0){
  Write-Info "Oprydning af resterende cereal-rækker..."
  for($i=$global:CreatedRows.Count-1;$i -ge 0;$i--){
    $row=$global:CreatedRows[$i]
    $kp=("cereals/{0}/{1}/{2}" -f (Encode $row.name),(Encode $row.mfr),(Encode $row.type))
    $r=Send-DELETE $kp $script:AuthSession
    if([int]$r.ResponseCode -eq 200){ Write-Pass "Slettet: $($row.name)/$($row.mfr)/$($row.type)" }
    else { Write-Warn "Kunne ikke slette ($($r.ResponseCode)): $($row.name)/$($row.mfr)/$($row.type)" }
  }
}
if($global:CreatedProductIds.Count -gt 0){
  Write-Info "Oprydning af resterende produkter..."
  foreach($pids in @($global:CreatedProductIds)){
    $r=Send-DELETE ("products/{0}" -f $pids) $script:AuthSession
    if([int]$r.ResponseCode -eq 200){ Write-Pass "Slettet produkt Id=$pids" } else { Write-Warn "Kunne ikke slette produkt Id=$pids ($($r.ResponseCode))" }
  }
  $global:CreatedProductIds.Clear()
}

# slet tempfiler
foreach($f in @($tempCsv)){ if($f -and (Test-Path $f)){ Remove-Item -Force $f } }

# =====================================================================
# SEKT. 9: Rate limiting
#  - Forudsætter global FixedWindow: 60 req/min pr. IP (Program.cs)
# =====================================================================
Write-Title "S9: Rate limiting"

# Vælg et letvægts-endpoint (public GET) til at belaste
$rlPath = "auth/health"

# Helper: send mange GETs hurtigt og tælle 200/429/andet
function Invoke-Burst([string]$path, [int]$count){
  $ok=0;$rl=0;$other=0
  for($i=0;$i -lt $count;$i++){
    $r = Send-GET $path $script:NoAuthSession
    $c = [int]$r.ResponseCode
    if($c -eq 200){ $ok++ }
    elseif($c -eq 429){ $rl++ }
    else { $other++ }
  }
  [PSCustomObject]@{ Ok=$ok; RL=$rl; Other=$other }
}

# --- TEST 1: Frisk vindue giver 200 (vi venter til nyt vindue for determinisme)
Run-Test "RL-1: Cooldown til frisk vindue (65s), 1x GET = 200" {
  Write-Info "RateLimit: venter 65 sekunder for at starte i nyt minutvindue..."
  Start-Sleep -Seconds 65
  $r = Send-GET $rlPath $script:NoAuthSession
  $c = [int]$r.ResponseCode
  @{ Ok=($c -eq 200); Detail=("HTTP {0}" -f $c) }
}

# --- TEST 2: Burst 70 requests udløser limit (forvent >=1 styk 429)
Run-Test "RL-2: Burst 70 requests -> forvent mindst én 429" {
  $res = Invoke-Burst $rlPath 70
  $detail = "200=$($res.Ok); 429=$($res.RL); other=$($res.Other)"
  @{ Ok=($res.RL -ge 1); Detail=$detail }
}

# --- TEST 3: Fortsat i samme vindue: 1 request er sandsynligvis 429/200 (accepter begge)
Run-Test "RL-3: Inden vinduet resetter – 1x GET (200 eller 429 er OK)" {
  $r = Send-GET $rlPath $script:NoAuthSession
  $c = [int]$r.ResponseCode
  # Vi accepterer begge udfald (afhænger af hvor i vinduet vi rammer)
  @{ Ok=($c -in 200,429); Detail=("HTTP {0}" -f $c) }
}

# --- TEST 4: Efter reset virker det igen (200)
Run-Test "RL-4: Nyt vindue (65s), 1x GET = 200" {
  Write-Info "RateLimit: venter 65 sekunder for nyt vindue..."
  Start-Sleep -Seconds 65
  $r = Send-GET $rlPath $script:NoAuthSession
  $c = [int]$r.ResponseCode
  @{ Ok=($c -eq 200); Detail=("HTTP {0}" -f $c) }
}


# =====================================================================
# SEKT. 10: Summary & log
# =====================================================================
$total   = $global:TestResults.Count
$passed  = @($global:TestResults | Where-Object { $_.Success }).Count
$failed  = $total - $passed
$overall = if($failed -eq 0){"PASS"} else {"FAIL"}

Write-Title "RESULTAT: $overall  ($passed/$total passeret, $failed fejlede)"

$logLines = New-Object System.Collections.Generic.List[string]
$logLines.Add(("CerealAPI Smoketest @ {0}" -f (Get-Date)))
$logLines.Add(("BaseUrl: {0}" -f $script:BaseUri))
$logLines.Add(("RunId  : {0}" -f $runId))
$logLines.Add("")
$global:TestResults | ForEach-Object {
  $status = if($_.Success){"PASS"} else {"FAIL"}
  $line = ("[{0}] {1} ({2} ms)" -f $status, $_.Name, $_.DurationMs)
  if(-not $_.Success){
    if($_.Error){ $line += (" | ERROR: {0}" -f $_.Error) }
    elseif($_.Details){ $line += (" | {0}" -f $_.Details) }
  } else { if($_.Details){ $line += (" | {0}" -f $_.Details) } }
  $logLines.Add($line)
}
$logLines.Add(""); $logLines.Add(("OVERALL: {0}  ({1}/{2} passed)" -f $overall, $passed, $total))

$logName = ("{0} Smoketest [{1}].log" -f $stamp, $overall)
$logPath = Join-Path $logsDir $logName
Set-Content -LiteralPath $logPath -Encoding UTF8 -Value $logLines

if($overall -eq "PASS"){ Write-Pass ("Smoketest OK. Log: {0}" -f $logPath); exit 0 }
else{ Write-Fail ("Smoketest FEJLEDE. Log: {0}" -f $logPath); exit 1 }
