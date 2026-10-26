# Seance 3 - deploiement manage (parties 1 a 5). Aucune destruction ici : voir nettoyage_s3.ps1.
# Lancer depuis ce dossier :  powershell -ExecutionPolicy Bypass -File .\lancer_s3.ps1
# Duree : environ 1 h. Journal complet : logs\sortie_s3.log (le sel n'y est jamais ecrit).

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, locust | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s3.log'
if (Test-Path $LOG) { Move-Item $LOG (Join-Path $PSScriptRoot ("logs\sortie_s3_" + (Get-Date -Format 'HHmmss') + ".log")) -Force }
Set-Content -Path $LOG -Value "TP S3 - debut $(Get-Date -Format s)" -Encoding UTF8

function Log([string]$s) { $l = "$(Get-Date -Format 'HH:mm:ss') $s"; Write-Host $l; Add-Content -Path $LOG -Value $l -Encoding UTF8 }
function Run([string]$titre, [scriptblock]$sb) {
    Log ""
    Log "===== $titre ====="
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $script:OUT = @(& $sb 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' })
    $sw.Stop()
    $script:OUT | ForEach-Object { Add-Content -Path $LOG -Value $_ -Encoding UTF8; Write-Host $_ }
    $script:DUREE = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Log ("[duree] {0} s" -f $script:DUREE)
}
function Resume([string]$cle, $val) { Log ("[RESUME] {0} = {1}" -f $cle, $val) }
function Stop-Erreur([string]$msg) { Log "ARRET : $msg"; Read-Host "Envoie une capture a Claude. Entree pour fermer"; exit 1 }
function Code([string]$url, [int]$max = 30) {
    $r = curl.exe -s -m $max -o NUL -w "%{http_code} %{time_total}" $url
    if (-not $r) { $r = "000 $max" }
    return $r
}
# Sonde /health toutes les $pas secondes jusqu'au premier 200 ; renvoie le delai en secondes.
function Attendre-200([string]$titre, [int]$essais = 60, [int]$pas = 10) {
    Log ""; Log "===== $titre ====="
    $sw = [Diagnostics.Stopwatch]::StartNew(); $codes = @()
    for ($i = 1; $i -le $essais; $i++) {
        $r = Code "$APP_URL/health" 30
        $c = $r.Split(' ')[0]; $codes += $c
        Log ("  essai {0,2} : code {1} ({2} s)" -f $i, $c, $r.Split(' ')[1])
        if ($c -eq '200') { break }
        Start-Sleep -Seconds $pas
    }
    $sw.Stop(); $d = [math]::Round($sw.Elapsed.TotalSeconds, 0)
    Resume "$titre - codes" ($codes -join ' ')
    Resume "$titre - delai jusqu'au 200 (s)" $d
    return ($codes[-1] -eq '200')
}
function Predict([string]$fichier) {
    return (curl.exe -s -m 60 -X POST "$APP_URL/predict" -H "Content-Type: application/json" --data-binary "@$fichier")
}

# ---------------------------------------------------------------- Decisions
$SUFFIX = 'sm26'
$LOCATION = 'francecentral'
$RG = "rg-dermascan-s3-$SUFFIX"
$RG_REG = "rg-dermascan-registre-$SUFFIX"
$ACR_NAME = "acrdermascan$SUFFIX"
$IMAGE_REPO = 'dermascan-api'
$IMAGE_TAG = '1.0.0'
$PLAN_NAME = "plan-dermascan-$SUFFIX"
$APP_NAME = "app-dermascan-$SUFFIX"
$SKU = 'B1'
$SEUIL_S2 = '0.34747330294391954'
$SEUIL_BAS = '0.0347'
$MODEL_VERSION = '1.0.0-azure'
Resume 'Decisions' "$SUFFIX | $LOCATION | $RG | $ACR_NAME | ${IMAGE_REPO}:$IMAGE_TAG | $PLAN_NAME | $APP_NAME | $SKU"
if (-not (Test-Path charge.json)) { Stop-Erreur "charge.json introuvable dans ce dossier" }
Resume 'Colonnes de charge.json' ((Get-Content charge.json -Raw | ConvertFrom-Json).PSObject.Properties.Name.Count)

# ================================================================ PARTIE 1
$chrono = [Diagnostics.Stopwatch]::StartNew()
Resume 'Debut sonde de faisabilite' (Get-Date -Format 'HH:mm:ss')
az account set --subscription "Azure for Students"
Run 'az account show' { az account show --output table }
Run 'Sonde 1 - politique de regions' { az policy assignment list --output tsv --query "[?displayName=='Allowed resource deployment regions'].parameters.listOfAllowedLocations.value[]" }
Resume 'Regions autorisees par politique' ($(if ($OUT.Count -eq 0) { 'aucune politique (sortie vide)' } else { $OUT -join ', ' }))
Run 'Toutes les affectations de politique' { az policy assignment list --query "[].displayName" --output tsv }
foreach ($ns in 'Microsoft.Web', 'Microsoft.ContainerInstance', 'Microsoft.ContainerRegistry') {
    $etat = az provider show --namespace $ns --query registrationState --output tsv
    Resume "Fournisseur $ns (avant)" $etat
    if ($etat -ne 'Registered') {
        Run "Enregistrement $ns" { az provider register --namespace $ns --wait }
        Resume "Fournisseur $ns (apres)" (az provider show --namespace $ns --query registrationState --output tsv)
    }
}
Run 'Creation du groupe de la seance' { az group create --name $RG --location $LOCATION --tags projet=dermascan seance=s3 proprietaire=soufiane.meskine a_detruire=2026-10-26 --output table }
Run 'Creation du plan App Service Linux (Mesure 1)' { az appservice plan create --name $PLAN_NAME --resource-group $RG --location $LOCATION --is-linux --sku $SKU --output table }
$planErr = ($OUT | Where-Object { $_ -match 'ERROR|Code:|quota|Disallowed' }) -join ' | '
Run 'Etat du plan' { az appservice plan show --name $PLAN_NAME --resource-group $RG --query "{nom:name, sku:sku.name, etat:properties.status}" --output table }
$etatPlan = az appservice plan show --name $PLAN_NAME --resource-group $RG --query "properties.status" --output tsv 2>$null
$chrono.Stop()
Resume 'Creation du plan' $(if ($etatPlan -eq 'Ready') { 'succes (Ready)' } else { "echec : $planErr" })
Resume 'Duree totale de la sonde (s)' ([math]::Round($chrono.Elapsed.TotalSeconds, 0))
Resume 'Heure de la decision' (Get-Date -Format 'HH:mm:ss')
if ($etatPlan -ne 'Ready') { Stop-Erreur "plan App Service refuse : cible A impossible, il faut passer a l'annexe B (ACI). Previens Claude." }
Resume 'Cible retenue' 'A - App Service for Containers'

# ================================================================ PARTIE 2
$LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
$IMAGE_FULL = "$LOGIN_SERVER/${IMAGE_REPO}:$IMAGE_TAG"
Resume 'loginServer' $LOGIN_SERVER
Resume 'IMAGE_FULL' $IMAGE_FULL
Run 'Tags du depot' { az acr repository show-tags --name $ACR_NAME --repository $IMAGE_REPO --output table }
Run 'Manifestes (Mesure 3)' { az acr manifest list-metadata --registry $ACR_NAME --name $IMAGE_REPO --output table }
Resume 'Digest du tag' (az acr manifest list-metadata --registry $ACR_NAME --name $IMAGE_REPO --query "[?tags[0]=='$IMAGE_TAG'].digest" --output tsv)
Resume 'Architecture du tag' (az acr manifest list-metadata --registry $ACR_NAME --name $IMAGE_REPO --query "[?tags[0]=='$IMAGE_TAG'].architecture" --output tsv)
Resume 'Date de publication du tag' (az acr manifest list-metadata --registry $ACR_NAME --name $IMAGE_REPO --query "[?tags[0]=='$IMAGE_TAG'].createdTime" --output tsv)

$pris = $false; try { Resolve-DnsName "$APP_NAME.azurewebsites.net" -ErrorAction Stop | Out-Null; $pris = $true } catch {}
$mien = az webapp list --query "[?name=='$APP_NAME'].name" --output tsv
if ($pris -and -not $mien) { $APP_NAME = "app-dermascan-$SUFFIX-" + (Get-Random -Minimum 100 -Maximum 999); Log "Nom deja pris sur Azure, nouveau nom : $APP_NAME" }
$APP_URL = "https://$APP_NAME.azurewebsites.net"
Resume 'APP_NAME' $APP_NAME
Resume 'APP_URL' $APP_URL
Run 'az webapp create' { az webapp create --resource-group $RG --plan $PLAN_NAME --name $APP_NAME --container-image-name $IMAGE_FULL --output table }
az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=8000 --output none
Log "WEBSITES_PORT=8000 pose. Attente de 60 s avant l'observation."
Start-Sleep -Seconds 60
Run 'Mesure 4 - /health avant tout droit sur le registre' { curl.exe -s -m 120 -o captures\avant_droits.html -w "code=%{http_code} duree=%{time_total}s" "$APP_URL/health" }
Run 'Mesure 4 - debut de la page renvoyee' { Get-Content captures\avant_droits.html -TotalCount 15 -ErrorAction SilentlyContinue }

# Identite managee
Run 'Geste 1 - identite systeme' { az webapp identity assign --resource-group $RG --name $APP_NAME --output table }
$PRINCIPAL_ID = az webapp identity show --resource-group $RG --name $APP_NAME --query principalId --output tsv
$ACR_ID = az acr show --name $ACR_NAME --query id --output tsv
Resume 'principalId' $PRINCIPAL_ID
Resume 'ACR_ID (portee)' $ACR_ID
Set-Content -Path logs\ids.txt -Value "PRINCIPAL_ID=$PRINCIPAL_ID`nACR_ID=$ACR_ID`nAPP_NAME=$APP_NAME" -Encoding ASCII
Run 'Geste 4 - role AcrPull' { az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal --scope $ACR_ID --role AcrPull --output table }
$tRole = Get-Date
Resume 'Heure attribution du role' ($tRole.ToString('HH:mm:ss'))
$WEB_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
Run 'Geste 5 - acrUseManagedIdentityCreds' { az resource update --ids "$WEB_ID/config/web" --set properties.acrUseManagedIdentityCreds=true --query properties.acrUseManagedIdentityCreds --output tsv }
Run 'Geste 6 - restart' { az webapp restart --resource-group $RG --name $APP_NAME }
$tRestart = Get-Date
$ok = Attendre-200 'Mesure 6 - premier demarrage apres restart' 60 10
if (-not $ok) {
    Log "Pas de 200 apres 10 min : propagation du role probablement en cours, second restart."
    az webapp restart --resource-group $RG --name $APP_NAME
    $ok = Attendre-200 'Mesure 6 - second essai apres nouveau restart' 60 10
}
if (-not $ok) { Stop-Erreur "le service ne repond toujours pas 200 apres 20 minutes" }
Resume 'Delai attribution du role -> premier 200 (s)' ([math]::Round(((Get-Date) - $tRole).TotalSeconds, 0))
Resume 'Delai restart -> premier 200 (s)' ([math]::Round(((Get-Date) - $tRestart).TotalSeconds, 0))
Run 'Attributions sur le registre' { az role assignment list --scope $ACR_ID --output table }
Run 'GET /health public' { curl.exe -s -i "$APP_URL/health" }
$OUT | Set-Content captures\health_public.txt -Encoding UTF8
Run 'GET /model/info public' { curl.exe -s "$APP_URL/model/info" }
Run 'POST /predict public' { curl.exe -s -i -X POST "$APP_URL/predict" -H "Content-Type: application/json" --data-binary "@charge.json" }
$OUT | Set-Content captures\predict_public.txt -Encoding UTF8
$t = @(); for ($i = 1; $i -le 5; $i++) { $t += curl.exe -s -o NUL -w "%{time_total}" -X POST "$APP_URL/predict" -H "Content-Type: application/json" --data-binary "@charge.json" }
Resume 'Durees des 5 predictions (s)' ($t -join ' ')

# ================================================================ PARTIE 3
Run 'Reglages applicatifs' { az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings PORT=8000 MODEL_VERSION=$MODEL_VERSION LOG_LEVEL=info ENVIRONMENT=recette SEUIL=$SEUIL_S2 --query "[].name" --output tsv }
Run 'Configuration effective (sans secret)' { az webapp config appsettings list --resource-group $RG --name $APP_NAME --output table }
# Secret : genere localement, jamais ecrit dans le journal.
$b = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$SALT = -join ($b | ForEach-Object { $_.ToString('x2') })
az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings "INFERENCE_LOG_SALT=$SALT" --output none
$vu = az webapp config appsettings list --resource-group $RG --name $APP_NAME --query "[?name=='INFERENCE_LOG_SALT'].value" --output tsv
Resume 'Mesure 7 - le CLI affiche-t-il le sel en clair' $(if ($vu -eq $SALT) { 'OUI, valeur complete affichee en clair (non recopiee ici)' } elseif (-not $vu) { 'non, valeur nulle/masquee' } else { "masquee : $vu" })
Remove-Variable SALT, vu, b
Resume 'Nombre total de reglages' ((az webapp config appsettings list --resource-group $RG --name $APP_NAME --query "[].name" --output tsv | Measure-Object).Count)
Run 'Noms des reglages' { az webapp config appsettings list --resource-group $RG --name $APP_NAME --query "[].name" --output tsv }

Run 'Sonde de sante declaree' { az webapp update --resource-group $RG --name $APP_NAME --set siteConfig.healthCheckPath=/health --query "siteConfig.healthCheckPath" --output tsv }
Resume 'Chemin de sonde enregistre' (az webapp config show --resource-group $RG --name $APP_NAME --query healthCheckPath --output tsv)
az webapp restart --resource-group $RG --name $APP_NAME
Attendre-200 'Mesure 8 - redemarrage avec sonde' 60 10 | Out-Null
Run '/model/info apres reglages (MODEL_VERSION visible ?)' { curl.exe -s "$APP_URL/model/info" }
Resume 'MODEL_VERSION visible dans /model/info' $(if (($OUT -join ' ') -match [regex]::Escape($MODEL_VERSION)) { 'oui' } else { "non (valeur posee : $MODEL_VERSION)" })
Run 'predict charge.json, seuil S2' { Predict 'charge.json' }
Run 'predict charge_seuil.json, seuil S2' { Predict 'charge_seuil.json' }

az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings SEUIL=$SEUIL_BAS --output none
$tS = Get-Date; Log "SEUIL abaisse a $SEUIL_BAS a $($tS.ToString('HH:mm:ss')), sans redemarrage."
$vu = $false
for ($i = 1; $i -le 60; $i++) {
    $r = Predict 'charge.json'
    try { if ([math]::Abs(([double]($r | ConvertFrom-Json).seuil) - [double]$SEUIL_BAS) -lt 1e-9) { $vu = $true; break } } catch {}
    Log "  $i : seuil pas encore applique"; Start-Sleep -Seconds 5
}
Resume 'Delai appsettings set -> nouveau seuil visible (s)' $(if ($vu) { [math]::Round(((Get-Date) - $tS).TotalSeconds, 0) } else { 'non applique apres 5 min' })
Run 'predict charge.json, seuil abaisse' { Predict 'charge.json' }
$OUT | Set-Content captures\predict_seuil_bas.txt -Encoding UTF8
Run 'predict charge_seuil.json, seuil abaisse' { Predict 'charge_seuil.json' }
Add-Content captures\predict_seuil_bas.txt -Value $OUT -Encoding UTF8
az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings SEUIL=$SEUIL_S2 --output none
$tS = Get-Date; Log "SEUIL remis a $SEUIL_S2."
for ($i = 1; $i -le 60; $i++) {
    $r = Predict 'charge.json'
    try { if ([math]::Abs(([double]($r | ConvertFrom-Json).seuil) - [double]$SEUIL_S2) -lt 1e-9) { break } } catch {}
    Start-Sleep -Seconds 5
}
Resume 'Delai retour au seuil S2 (s)' ([math]::Round(((Get-Date) - $tS).TotalSeconds, 0))
Run 'predict charge.json, seuil S2 restaure' { Predict 'charge.json' }

# ================================================================ PARTIE 4
Run 'Activation des logs' { az webapp log config --resource-group $RG --name $APP_NAME --docker-container-logging filesystem --application-logging filesystem --level information --output none }
function Demarrer-Tail([string]$fichier) {
    return Start-Job -ScriptBlock { param($rg, $app, $f)
        az webapp log tail --resource-group $rg --name $app 2>&1 | ForEach-Object { "$(Get-Date -Format HH:mm:ss) $_" | Out-File -FilePath $f -Append -Encoding utf8 }
    } -ArgumentList $RG, $APP_NAME, (Join-Path $PSScriptRoot $fichier)
}
$job = Demarrer-Tail 'logs\tail_trafic.txt'
Start-Sleep -Seconds 30
Set-Content -Path incomplet.json -Value '{"age_approx": 55}' -Encoding ASCII
Log "Trafic : GET /health, GET /model/info, POST /predict incomplet"
curl.exe -s -o NUL "$APP_URL/health"; curl.exe -s -o NUL "$APP_URL/model/info"
Run 'POST /predict incomplet' { curl.exe -s -w " HTTP %{http_code}" -X POST "$APP_URL/predict" -H "Content-Type: application/json" --data-binary "@incomplet.json" }
Start-Sleep -Seconds 90
Stop-Job $job; Remove-Job $job
Run 'Flux de logs pendant le trafic (Mesure 9)' { Get-Content logs\tail_trafic.txt -ErrorAction SilentlyContinue }

# Panne provoquee
$job = Demarrer-Tail 'logs\tail_panne.txt'
Start-Sleep -Seconds 15
az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=9999 --output none
az webapp restart --resource-group $RG --name $APP_NAME
$tP = Get-Date; Log "PANNE : WEBSITES_PORT=9999 + restart a $($tP.ToString('HH:mm:ss'))"
for ($i = 1; $i -le 20; $i++) {
    $r = curl.exe -s -m 60 -o NUL -w "code=%{http_code} duree=%{time_total}s" "$APP_URL/health"
    Log ("  panne essai {0,2} : {1}" -f $i, $r)
    Start-Sleep -Seconds 30
}
Stop-Job $job; Remove-Job $job
Run 'Logs pendant la panne (Mesure 10)' { Get-Content logs\tail_panne.txt -ErrorAction SilentlyContinue }
Run 'Archive des logs' { az webapp log download --resource-group $RG --name $APP_NAME --log-file logs\logs_s3.zip }

az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=8000 --output none
Log "REPARATION : WEBSITES_PORT=8000 sans restart explicite"
$ok = Attendre-200 'Mesure 11 - retour au service apres correction' 60 10
Resume 'Redemarrage explicite necessaire' $(if ($ok) { 'non, la plateforme a repris seule (appsettings set recycle le conteneur)' } else { 'oui' })
if (-not $ok) { az webapp restart --resource-group $RG --name $APP_NAME; Attendre-200 'Mesure 11 - apres restart explicite' 60 10 | Out-Null }

$APP_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
$PLAN_ID = az appservice plan show --name $PLAN_NAME --resource-group $RG --query id --output tsv
Run 'Metriques app (Mesure 12)' { az monitor metrics list --resource $APP_ID --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H --output table }

# ================================================================ PARTIE 5
$py = $null
foreach ($c in @('py -3', 'python')) { try { $v = Invoke-Expression "$c --version" 2>&1; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (-not $py) { Stop-Erreur "aucun Python trouve pour installer Locust" }
if (-not (Test-Path .venv-locust)) { Run 'venv Locust' { Invoke-Expression "$py -m venv .venv-locust" } }
Run 'pip install locust' { .\.venv-locust\Scripts\python.exe -m pip install --quiet --disable-pip-version-check locust }
Run 'locust --version' { .\.venv-locust\Scripts\locust.exe --version }
Run 'Controle charge perturbee' { .\.venv-locust\Scripts\python.exe -c "import json,urllib.request,locustfile as l;r=urllib.request.urlopen(urllib.request.Request('$APP_URL/predict',data=json.dumps(l.charge_utile_perturbee()).encode(),headers={'Content-Type':'application/json'}));print('code',r.status)" }

$paliers = @(@(1, 10, 2), @(2, 50, 5), @(3, 150, 10), @(4, 300, 20))
Push-Location locust
Copy-Item ..\locustfile.py, ..\charge.json . -Force
foreach ($p in $paliers) {
    Run ("Palier {0} : {1} utilisateurs, spawn {2}" -f $p[0], $p[1], $p[2]) {
        ..\.venv-locust\Scripts\locust.exe -f locustfile.py --host $APP_URL --users $p[1] --spawn-rate $p[2] --run-time 3m --headless --only-summary --csv ("palier{0}" -f $p[0]) --html ("palier{0}.html" -f $p[0])
    }
}
Pop-Location
Run 'Metriques du plan apres les paliers (CPU / memoire)' { az monitor metrics list --resource $PLAN_ID --metric "CpuPercentage" "MemoryPercentage" --interval PT1M --output table }
Run 'Metriques app apres les paliers' { az monitor metrics list --resource $APP_ID --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H --output table }
$con = @(); for ($i = 1; $i -le 20; $i++) { $con += [double]::Parse((curl.exe -s -o NUL -w "%{time_connect}" "$APP_URL/health"), [Globalization.CultureInfo]::InvariantCulture) }
$con = $con | Sort-Object
Resume 'Ligne de base time_connect 20 mesures (ms) min/mediane/max' ("{0:N1} / {1:N1} / {2:N1}" -f ($con[0] * 1000), (($con[9] + $con[10]) / 2 * 1000), ($con[19] * 1000))

Log ""
Log "TERMINE $(Get-Date -Format s). Les ressources tournent encore : previens Claude AVANT de lancer nettoyage_s3.ps1."
