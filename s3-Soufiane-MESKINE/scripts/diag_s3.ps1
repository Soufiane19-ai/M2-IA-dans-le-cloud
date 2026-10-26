# Diagnostic de la latence de 19 s : ou part le temps ? (client ou serveur)
# powershell -ExecutionPolicy Bypass -File .\diag_s3.ps1
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\diag_s3.log'
Set-Content -Path $LOG -Value "Diagnostic S3 - $(Get-Date -Format s)" -Encoding UTF8
function Log([string]$s) { Write-Host $s; Add-Content -Path $LOG -Value $s -Encoding UTF8 }
$APP_NAME = ((Get-Content logs\ids.txt | ConvertFrom-StringData).APP_NAME)
$URL = "https://$APP_NAME.azurewebsites.net/health"
$FMT = "code=%{http_code} ip=%{remote_ip} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} premier_octet=%{time_starttransfer} total=%{time_total}"

Log "curl : $(curl.exe --version | Select-Object -First 1)"
Log "nslookup :"; nslookup "$APP_NAME.azurewebsites.net" 2>&1 | ForEach-Object { Log "  $_" }

Log ""; Log "== A. curl normal (3 fois)"
1..3 | ForEach-Object { Log ("  " + (curl.exe -s -m 60 -o NUL -w $FMT $URL)) }
Log ""; Log "== B. curl sans verification de revocation du certificat (--ssl-no-revoke)"
1..3 | ForEach-Object { Log ("  " + (curl.exe -s -m 60 --ssl-no-revoke -o NUL -w $FMT $URL)) }
Log ""; Log "== C. curl force IPv4 (-4)"
1..3 | ForEach-Object { Log ("  " + (curl.exe -s -m 60 -4 -o NUL -w $FMT $URL)) }
Log ""; Log "== D. HTTP sans TLS (http://, redirection non suivie)"
1..3 | ForEach-Object { Log ("  " + (curl.exe -s -m 60 -o NUL -w $FMT ($URL -replace '^https', 'http'))) }
Log ""; Log "== E. Invoke-WebRequest (pile .NET, pas curl)"
1..3 | ForEach-Object {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $r = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec 60; $c = $r.StatusCode } catch { $c = "erreur $($_.Exception.Message)" }
    $sw.Stop(); Log ("  code={0} total={1:N3}" -f $c, $sw.Elapsed.TotalSeconds)
}
Log ""; Log "== F. Python (requests absent ? urllib)"
$py = if (Test-Path .venv-locust\Scripts\python.exe) { '.\.venv-locust\Scripts\python.exe' } else { 'python' }
& $py -c "import time,urllib.request as u
for i in range(3):
    t=time.time(); r=u.urlopen('$URL',timeout=60); r.read(); print('  code',r.status,'total %.3f'%(time.time()-t))" 2>&1 | ForEach-Object { Log "$_" }
Log ""; Log "TERMINE"
