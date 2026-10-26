# Seance 3 - partie 5 (test de charge), apres le diagnostic TLS (diag_s3.ps1).
# powershell -ExecutionPolicy Bypass -File .\lancer_s3_partie5b.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, locust | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s3_partie5b.log'
Set-Content -Path $LOG -Value "TP S3 partie 5b - debut $(Get-Date -Format s)" -Encoding UTF8
function Log([string]$s) { $l = "$(Get-Date -Format 'HH:mm:ss') $s"; Write-Host $l; Add-Content -Path $LOG -Value $l -Encoding UTF8 }
function Run([string]$titre, [scriptblock]$sb) {
    Log ""; Log "===== $titre ====="
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $script:OUT = @(& $sb 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' })
    $sw.Stop()
    $script:OUT | ForEach-Object { Add-Content -Path $LOG -Value $_ -Encoding UTF8; Write-Host $_ }
    $script:DUREE = [math]::Round($sw.Elapsed.TotalSeconds, 1); Log ("[duree] {0} s" -f $script:DUREE)
}
function Resume([string]$cle, $val) { Log ("[RESUME] {0} = {1}" -f $cle, $val) }
function Stop-Erreur([string]$msg) { Log "ARRET : $msg"; Read-Host "Envoie une capture a Claude. Entree pour fermer"; exit 1 }

$RG = 'rg-dermascan-s3-sm26'
$PLAN_NAME = 'plan-dermascan-sm26'
$APP_NAME = ((Get-Content logs\ids.txt | ConvertFrom-StringData).APP_NAME)
$APP_URL = "https://$APP_NAME.azurewebsites.net"
az account set --subscription "Azure for Students"
Resume 'APP_URL' $APP_URL
Run 'Commande de demarrage en place' { az webapp config show --resource-group $RG --name $APP_NAME --query "{startup:appCommandLine, alwaysOn:alwaysOn}" --output table }

# ---------------------------------------------------------------- Latence reelle sur UNE connexion reutilisee
# curl enchaine 6 requetes dans la meme invocation : la 1re ouvre la connexion TLS (~19 s), les suivantes la reutilisent.
$F = "%{http_code} tls=%{time_appconnect} total=%{time_total}\n"
Run 'GET /health x6 sur une connexion (1re = ouverture TLS)' { curl.exe -s -o NUL -o NUL -o NUL -o NUL -o NUL -o NUL -w $F "$APP_URL/health" "$APP_URL/health" "$APP_URL/health" "$APP_URL/health" "$APP_URL/health" "$APP_URL/health" }
$args6 = @(); 1..6 | ForEach-Object { $args6 += @('-o', 'NUL', '-X', 'POST', '-H', 'Content-Type: application/json', '--data-binary', '@charge.json', "$APP_URL/predict") ; if ($_ -lt 6) { $args6 += '--next' } }
Run 'POST /predict x6 sur une connexion (1re = ouverture TLS)' { curl.exe -s -w $F @args6 }
Run 'Meme chose en HTTP sans TLS (GET /health x6)' { curl.exe -s -o NUL -o NUL -o NUL -o NUL -o NUL -o NUL -w $F "http://$APP_NAME.azurewebsites.net/health" "http://$APP_NAME.azurewebsites.net/health" "http://$APP_NAME.azurewebsites.net/health" "http://$APP_NAME.azurewebsites.net/health" "http://$APP_NAME.azurewebsites.net/health" "http://$APP_NAME.azurewebsites.net/health" }

# ---------------------------------------------------------------- Locust
$py = $null
foreach ($c in @('py -3', 'python')) { try { Invoke-Expression "$c --version" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (-not $py) { Stop-Erreur "aucun Python trouve pour installer Locust" }
if (-not (Test-Path .venv-locust\Scripts\locust.exe)) {
    Run 'venv Locust' { Invoke-Expression "$py -m venv .venv-locust" }
    Run 'pip install locust' { .\.venv-locust\Scripts\python.exe -m pip install --quiet --disable-pip-version-check locust }
}
Run 'locust --version' { .\.venv-locust\Scripts\locust.exe --version }
Run 'Controle : une charge perturbee passe en 200' { .\.venv-locust\Scripts\python.exe -c "import json,urllib.request,locustfile as l;r=urllib.request.urlopen(urllib.request.Request('$APP_URL/predict',data=json.dumps(l.charge_utile_perturbee()).encode(),headers={'Content-Type':'application/json'}),timeout=90);print('code',r.status,r.read().decode())" }

Push-Location locust
Copy-Item ..\locustfile.py, ..\charge.json . -Force
Remove-Item palier*.csv, palier*.html -ErrorAction SilentlyContinue
$paliers = @(@(1, 10, 2), @(2, 50, 5), @(3, 150, 10), @(4, 300, 20))
foreach ($p in $paliers) {
    Log ("Palier {0} : {1} utilisateurs, spawn-rate {2}, debut" -f $p[0], $p[1], $p[2])
    Run ("Palier {0}" -f $p[0]) { ..\.venv-locust\Scripts\locust.exe -f locustfile.py --host $APP_URL --users $p[1] --spawn-rate $p[2] --run-time 3m --headless --only-summary --csv ("palier{0}" -f $p[0]) --html ("palier{0}.html" -f $p[0]) }
}
Run 'Lignes des 4 paliers' { Get-ChildItem palier*_stats.csv | ForEach-Object { $_.Name; Get-Content $_ } }
Pop-Location

$APP_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
$PLAN_ID = az appservice plan show --name $PLAN_NAME --resource-group $RG --query id --output tsv
Run 'Metriques du plan (CPU / memoire, par minute)' { az monitor metrics list --resource $PLAN_ID --metric "CpuPercentage" "MemoryPercentage" --interval PT1M --offset 20m --output table }
Run 'Metriques app par minute (requetes, 5xx, temps de reponse serveur)' { az monitor metrics list --resource $APP_ID --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1M --offset 20m --output table }
Run 'Metriques app (derniere heure)' { az monitor metrics list --resource $APP_ID --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H --output table }
Log ""
Log "TERMINE $(Get-Date -Format s). Previens Claude AVANT de lancer nettoyage_s3.ps1."
