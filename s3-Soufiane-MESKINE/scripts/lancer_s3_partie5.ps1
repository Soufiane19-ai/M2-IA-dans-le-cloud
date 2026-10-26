# Seance 3 - partie 5 (test de charge), precedee de la correction du serveur gunicorn.
# powershell -ExecutionPolicy Bypass -File .\lancer_s3_partie5.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, locust | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s3_partie5.log'
Set-Content -Path $LOG -Value "TP S3 partie 5 - debut $(Get-Date -Format s)" -Encoding UTF8
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
function Durees5([string]$chemin, [string]$methode = 'GET') {
    $t = @()
    for ($i = 1; $i -le 5; $i++) {
        if ($methode -eq 'POST') { $t += curl.exe -s -m 60 -o NUL -w "%{time_total}" -X POST "$APP_URL$chemin" -H "Content-Type: application/json" --data-binary "@charge.json" }
        else { $t += curl.exe -s -m 60 -o NUL -w "%{time_total}" "$APP_URL$chemin" }
    }
    return ($t -join ' ')
}

$RG = 'rg-dermascan-s3-sm26'
$PLAN_NAME = 'plan-dermascan-sm26'
$APP_NAME = ((Get-Content logs\ids.txt | ConvertFrom-StringData).APP_NAME)
$APP_URL = "https://$APP_NAME.azurewebsites.net"
az account set --subscription "Azure for Students"
Resume 'APP_URL' $APP_URL

# ---------------------------------------------------------------- Fin de la partie 4 (si lancer_s3.ps1 a ete interrompu pendant la panne)
Get-Job -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
$portActuel = az webapp config appsettings list --resource-group $RG --name $APP_NAME --query "[?name=='WEBSITES_PORT'].value" --output tsv
Resume 'WEBSITES_PORT au demarrage de ce script' $portActuel
if ($portActuel -ne '8000') {
    Run 'Panne vue du client (dernier essai avant reparation)' { curl.exe -s -m 60 -o NUL -w "code=%{http_code} duree=%{time_total}s" "$APP_URL/health" }
    Run 'Archive des logs (panne incluse)' { az webapp log download --resource-group $RG --name $APP_NAME --log-file logs\logs_s3.zip }
    az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=8000 --output none
    $tR = Get-Date; Log "REPARATION : WEBSITES_PORT=8000 sans restart explicite a $($tR.ToString('HH:mm:ss'))"
    $codes = @(); $ok = $false
    for ($i = 1; $i -le 60; $i++) {
        $r = curl.exe -s -m 30 -o NUL -w "%{http_code}" "$APP_URL/health"; if (-not $r) { $r = '000' }
        $codes += $r; Log "  essai $i : $r"
        if ($r -eq '200') { $ok = $true; break }
        Start-Sleep -Seconds 10
    }
    Resume 'Mesure 11 - codes apres correction' ($codes -join ' ')
    Resume 'Mesure 11 - delai correction -> premier 200 (s)' ([math]::Round(((Get-Date) - $tR).TotalSeconds, 0))
    Resume 'Mesure 11 - redemarrage explicite necessaire' $(if ($ok) { 'non (appsettings set recycle le conteneur)' } else { 'oui' })
    if (-not $ok) { az webapp restart --resource-group $RG --name $APP_NAME; Start-Sleep -Seconds 120 }
    $APP_ID0 = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
    Run 'Metriques app (Mesure 12)' { az monitor metrics list --resource $APP_ID0 --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H --output table }
}

# ---------------------------------------------------------------- Diagnostic et correction de la latence
Resume 'AVANT correction - 5 x GET /health (s)' (Durees5 '/health')
Resume 'AVANT correction - 5 x POST /predict (s)' (Durees5 '/predict' 'POST')
Run 'Commande de demarrage AVANT' { az webapp config show --resource-group $RG --name $APP_NAME --query "{startup:appCommandLine, alwaysOn:alwaysOn, http20:http20Enabled}" --output table }
$CMD = 'gunicorn --bind 0.0.0.0:8000 --workers 2 --threads 4 --worker-class gthread --access-logfile - app:app'
Run 'Correction : workers gthread (sans reconstruire l image)' { az webapp config set --resource-group $RG --name $APP_NAME --startup-file $CMD --query appCommandLine --output tsv }
$tC = Get-Date
$ok = $false
for ($i = 1; $i -le 60; $i++) {
    $r = curl.exe -s -m 30 -o NUL -w "%{http_code} %{time_total}" "$APP_URL/health"
    Log "  essai $i : $r"
    if ($r -match '^200 0\.|^200 [1-2]\.') { $ok = $true; break }
    Start-Sleep -Seconds 10
}
Resume 'Delai correction -> premier 200 rapide (s)' ([math]::Round(((Get-Date) - $tC).TotalSeconds, 0))
if (-not $ok) { Stop-Erreur "latence toujours elevee apres la correction" }
Start-Sleep -Seconds 20
Resume 'APRES correction - 5 x GET /health (s)' (Durees5 '/health')
Resume 'APRES correction - 5 x POST /predict (s)' (Durees5 '/predict' 'POST')
Run 'Reponse /predict apres correction' { curl.exe -s -X POST "$APP_URL/predict" -H "Content-Type: application/json" --data-binary "@charge.json" }

# ---------------------------------------------------------------- Locust
$py = $null
foreach ($c in @('py -3', 'python')) { try { Invoke-Expression "$c --version" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (-not $py) { Stop-Erreur "aucun Python trouve pour installer Locust" }
if (-not (Test-Path .venv-locust\Scripts\locust.exe)) {
    Run 'venv Locust' { Invoke-Expression "$py -m venv .venv-locust" }
    Run 'pip install locust' { .\.venv-locust\Scripts\python.exe -m pip install --quiet --disable-pip-version-check locust }
}
Run 'locust --version' { .\.venv-locust\Scripts\locust.exe --version }
Run 'Controle : une charge perturbee passe en 200' { .\.venv-locust\Scripts\python.exe -c "import json,urllib.request,locustfile as l;r=urllib.request.urlopen(urllib.request.Request('$APP_URL/predict',data=json.dumps(l.charge_utile_perturbee()).encode(),headers={'Content-Type':'application/json'}));print('code',r.status,r.read().decode())" }

Push-Location locust
Copy-Item ..\locustfile.py, ..\charge.json . -Force
$paliers = @(@(1, 10, 2), @(2, 50, 5), @(3, 150, 10), @(4, 300, 20))
foreach ($p in $paliers) {
    Log ("Palier {0} : {1} utilisateurs, spawn-rate {2}, debut" -f $p[0], $p[1], $p[2])
    Run ("Palier {0}" -f $p[0]) { ..\.venv-locust\Scripts\locust.exe -f locustfile.py --host $APP_URL --users $p[1] --spawn-rate $p[2] --run-time 3m --headless --only-summary --csv ("palier{0}" -f $p[0]) --html ("palier{0}.html" -f $p[0]) }
}
Run 'Lignes Aggregated des 4 paliers' { Get-ChildItem palier*_stats.csv | ForEach-Object { $_.Name; Get-Content $_ | Select-Object -First 1; Get-Content $_ | Select-String 'Aggregated' } }
Pop-Location

$APP_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
$PLAN_ID = az appservice plan show --name $PLAN_NAME --resource-group $RG --query id --output tsv
Run 'Metriques du plan (CPU / memoire, par minute)' { az monitor metrics list --resource $PLAN_ID --metric "CpuPercentage" "MemoryPercentage" --interval PT1M --offset 30m --output table }
Run 'Metriques app (derniere heure)' { az monitor metrics list --resource $APP_ID --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H --output table }
Run 'Http5xx par minute pendant les paliers' { az monitor metrics list --resource $APP_ID --metric "Http5xx" --interval PT1M --offset 20m --output table }
$con = @(); for ($i = 1; $i -le 20; $i++) { $con += [double]::Parse((curl.exe -s -o NUL -w "%{time_connect}" "$APP_URL/health"), [Globalization.CultureInfo]::InvariantCulture) }
$con = $con | Sort-Object
Resume 'Ligne de base time_connect (ms) min/mediane/max' ("{0:N1} / {1:N1} / {2:N1}" -f ($con[0] * 1000), (($con[9] + $con[10]) / 2 * 1000), ($con[19] * 1000))
Log ""
Log "TERMINE $(Get-Date -Format s). Previens Claude AVANT de lancer nettoyage_s3.ps1."
