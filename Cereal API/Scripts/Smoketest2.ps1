Param(
  [string]$BaseUrl = "http://localhost:5024/"
)

# -------- helpers (PS 5.1 compatible) --------
if(-not $BaseUrl.EndsWith("/")){ $BaseUrl += "/" }
[System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function U([string]$p){ [Uri]::new([Uri]$BaseUrl, $p) }
function J($resp){ try{ $resp.Content | ConvertFrom-Json | ConvertTo-Json -Depth 8 } catch { $resp.Content } }

Write-Host "BaseUrl = $BaseUrl" -ForegroundColor Cyan

# Unique user
$runId = [Guid]::NewGuid().ToString("N").Substring(0,8)
$user  = "u_$runId"
$pass  = "Pa`$`$w0rd!42"

# -------- REGISTER --------
Write-Host "`n[REGISTER]" -ForegroundColor Magenta
$regBody = @{ username=$user; password=$pass } | ConvertTo-Json
$resp = Invoke-WebRequest -Method POST -Uri (U "auth/register") -ContentType "application/json" -Body $regBody -ErrorAction Stop
Write-Host ("HTTP {0} -> {1}" -f $resp.StatusCode, (J $resp))

# -------- LOGIN #1 (capture Bearer + WebSession) --------
Write-Host "`n[LOGIN #1 - capture token + WebSession]" -ForegroundColor Magenta
$S = $null
$resp1 = Invoke-WebRequest -Method POST -Uri (U "auth/login") -ContentType "application/json" -Body $regBody -SessionVariable S -ErrorAction Stop
$body1 = $resp1.Content | ConvertFrom-Json
$token = $body1.token
if(-not $token){ Write-Host "No token in response body." -ForegroundColor Red }

# show cookies we actually have
$cookies = $null
if($S -and $S.Cookies){
  $cookies = $S.Cookies.GetCookies($BaseUrl)
}
if($cookies -and $cookies.Count -gt 0){
  $cookieList = @()
  foreach($c in $cookies){ $cookieList += ("{0}={1};domain={2};path={3}" -f $c.Name,$c.Value,$c.Domain,$c.Path) }
  Write-Host ("WebSession cookies: {0}" -f ($cookieList -join " | "))
}else{
  Write-Host "WebSession cookies: (none)" -ForegroundColor Yellow
}

# -------- /auth/_echo (server sees cookie?) --------
Write-Host "`n[/auth/_echo with WebSession]" -ForegroundColor Magenta
try{
  $echo = Invoke-WebRequest -Uri (U "auth/_echo") -WebSession $S -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $echo.StatusCode, (J $echo))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} -> {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

# -------- /auth/me via cookie (WebSession) --------
Write-Host "`n[/auth/me via WebSession cookie]" -ForegroundColor Magenta
try{
  $meCookie = Invoke-WebRequest -Uri (U "auth/me") -WebSession $S -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $meCookie.StatusCode, (J $meCookie))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} (cookie attempt failed) {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

# -------- /auth/me via Bearer --------
Write-Host "`n[/auth/me via Bearer]" -ForegroundColor Magenta
try{
  $meBearer = Invoke-WebRequest -Uri (U "auth/me") -Headers @{ Authorization = ("Bearer {0}" -f $token) } -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $meBearer.StatusCode, (J $meBearer))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} (bearer failed) {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

# -------- Force-add cookie into CookieContainer (defensive) --------
Write-Host "`n[Inject cookie manually into CookieContainer]" -ForegroundColor Magenta
try{
  $cookieVal = $null
  if($S -and $S.Cookies){
    $col = $S.Cookies.GetCookies($BaseUrl)
    if($col){
      $tk = $col["token"]
      if($tk){ $cookieVal = $tk.Value }
    }
  }
  if([string]::IsNullOrWhiteSpace($cookieVal)){ $cookieVal = $token }

  $baseUriObj = [Uri]$BaseUrl
  $cookieObj = New-Object System.Net.Cookie("token", $cookieVal, "/", $baseUriObj.Host)
  if(-not $S){ $S = New-Object Microsoft.PowerShell.Commands.WebRequestSession }
  if(-not $S.Cookies){ $S.Cookies = New-Object System.Net.CookieContainer }
  $S.Cookies.Add($baseUriObj, $cookieObj)

  $cookies2 = $S.Cookies.GetCookies($BaseUrl)
  if($cookies2 -and $cookies2.Count -gt 0){
    $cookieList2 = @()
    foreach($c in $cookies2){ $cookieList2 += ("{0}={1};domain={2};path={3}" -f $c.Name,$c.Value,$c.Domain,$c.Path) }
    Write-Host ("Now cookies: {0}" -f ($cookieList2 -join " | "))
  } else {
    Write-Host "No cookies after injection." -ForegroundColor Yellow
  }
}catch{
  Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# -------- /auth/_echo again --------
Write-Host "`n[/auth/_echo after injection]" -ForegroundColor Magenta
try{
  $echo2 = Invoke-WebRequest -Uri (U "auth/_echo") -WebSession $S -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $echo2.StatusCode, (J $echo2))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} -> {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

# -------- /auth/me via cookie (again) --------
Write-Host "`n[/auth/me via cookie after injection]" -ForegroundColor Magenta
try{
  $meCookie2 = Invoke-WebRequest -Uri (U "auth/me") -WebSession $S -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $meCookie2.StatusCode, (J $meCookie2))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} (cookie attempt failed) {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

# -------- /auth/me with raw Cookie header (last resort) --------
Write-Host "`n[/auth/me with manual Cookie header]" -ForegroundColor Magenta
$cookieHeader = ("token={0}" -f $token)
try{
  $meManual = Invoke-WebRequest -Uri (U "auth/me") -Headers @{ Cookie=$cookieHeader } -ErrorAction Stop
  Write-Host ("HTTP {0} -> {1}" -f $meManual.StatusCode, (J $meManual))
}catch{
  $code = $null; try{ $code = [int]$_.Exception.Response.StatusCode }catch{}
  Write-Host ("HTTP {0} (manual cookie failed) {1}" -f $code, $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan
