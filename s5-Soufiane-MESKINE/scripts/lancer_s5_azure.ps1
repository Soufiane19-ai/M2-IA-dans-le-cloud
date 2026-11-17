# Seance 5 - parties 5.3 et 5.4 : publier 2.1.0, deployer sur B1 avec Log Analytics, rejouer la derive, charge.
# powershell -ExecutionPolicy Bypass -File .\lancer_s5_azure.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, sorties, locust | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s5_azure.log'
Set-Content -Path $LOG -Value "TP S5 Azure - debut $(Get-Date -Format s)" -Encoding UTF8
function Log([string]$s) { $l = "$(Get-Date -Format 'HH:mm:ss') $s"; Write-Host $l; Add-Content -Path $LOG -Value $l -Encoding UTF8 }
function Run([string]$titre, [scriptblock]$sb) {
    Log ""; Log "===== $titre ====="
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $script:OUT = @(& $sb 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' })
    $script:CODE = $LASTEXITCODE
    $sw.Stop()
    $script:OUT | ForEach-Object { Add-Content -Path $LOG -Value $_ -Encoding UTF8; Write-Host $_ }
    $script:DUREE = [math]::Round($sw.Elapsed.TotalSeconds, 1); Log ("[duree] {0} s  [code] {1}" -f $script:DUREE, $script:CODE)
}
function Resume([string]$cle, $val) { Log ("[RESUME] {0} = {1}" -f $cle, $val) }
function Stop-Erreur([string]$msg) { Log "ARRET : $msg"; Read-Host "Envoie une capture a Claude. Entree pour fermer"; exit 1 }
function Sel { $b = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $_.ToString('x2') }) }

$W = $PSScriptRoot
$DON = Join-Path (Split-Path $W -Parent) 's4-dermascan\donnees'
function Py([string]$cmd) { docker run --rm -v "${W}:/work" -v "${DON}:/work/donnees" dermascan-outils:s5 sh -c $cmd }
$SUFFIX = 'sm26'
$RG_REGISTRE = "rg-dermascan-registre-$SUFFIX"    # LECTURE SEULE
$RG = "rg-dermascan-s5-$SUFFIX"                   # seul groupe cree puis detruit
$ACR_NAME = "acrdermascan$SUFFIX"
$PLAN_NAME = "plan-dermascan-s5-$SUFFIX"
$APP_NAME = "dermascan-api-s5-$SUFFIX"
$LAW_NAME = "law-dermascan-s5-$SUFFIX"
$VERSION = '2.1.0'
$ID = (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).controle.isic_id

az account set --subscription "Azure for Students"
$LOCATION = az acr show --name $ACR_NAME --query location --output tsv
if (-not $LOCATION) { Stop-Erreur "registre introuvable (az login ?)" }
Resume 'LOCATION' $LOCATION
foreach ($ns in 'Microsoft.Web', 'Microsoft.OperationalInsights', 'Microsoft.Insights') {
    Run "Fournisseur $ns" { az provider register --namespace $ns --wait; az provider show --namespace $ns --query registrationState --output tsv }
}
Run 'Extension log-analytics' { az extension add --name log-analytics --only-show-errors; az extension list --query "[?name=='log-analytics'].version" --output tsv }

# ---------------------------------------------------------------- Publication
Run 'az acr login' { az acr login --name $ACR_NAME }
$LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
$IMAGE_FULL = "$LOGIN_SERVER/dermascan-api:$VERSION"
docker tag "dermascan-api:$VERSION" $IMAGE_FULL
Run "docker push $IMAGE_FULL" { docker push $IMAGE_FULL }
if ($CODE -ne 0) { Run 'docker push (reprise)' { docker push $IMAGE_FULL } }
if ($CODE -ne 0) { Stop-Erreur "push impossible" }
Resume 'duree du push (s)' $DUREE
$DIGEST = az acr repository show --name $ACR_NAME --image "dermascan-api:$VERSION" --query digest --output tsv
Resume 'DIGEST' $DIGEST
Run 'Tags du depot' { az acr repository show-tags --name $ACR_NAME --repository dermascan-api --output table }

# ---------------------------------------------------------------- Deploiement (routine S4)
Run 'Groupe de seance' { az group create --name $RG --location $LOCATION --tags projet=dermascan seance=s5 proprietaire=soufiane.meskine a_detruire=2026-11-17 --query "{nom:name, etat:properties.provisioningState}" --output table }
Run 'Plan B1' { az appservice plan create --name $PLAN_NAME --resource-group $RG --location $LOCATION --is-linux --sku B1 --query "{nom:name, sku:sku.name}" --output table }
if ($CODE -ne 0) { Stop-Erreur "plan impossible" }
Run 'Application' { az webapp create --resource-group $RG --plan $PLAN_NAME --name $APP_NAME --container-image-name $IMAGE_FULL --query "{nom:name, hote:defaultHostName}" --output table }
if ($CODE -ne 0) { Stop-Erreur "application impossible" }
$SEL = Sel
Run 'Reglages (le sel n est pas affiche)' { az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=8000 PORT=8000 MODEL_VERSION=$VERSION ENVIRONMENT=recette IMAGE_DIGEST=$DIGEST INFERENCE_LOG_SALT=$SEL WEBSITES_CONTAINER_START_TIME_LIMIT=600 --query "[].name" --output tsv }
$SEL = $null
Run 'Identite managee' { az webapp identity assign --resource-group $RG --name $APP_NAME --query principalId --output tsv }
$PRINCIPAL_ID = az webapp identity show --resource-group $RG --name $APP_NAME --query principalId --output tsv
$ACR_ID = az acr show --name $ACR_NAME --query id --output tsv
Set-Content -Path logs\ids_s5.txt -Value "PRINCIPAL_ID=$PRINCIPAL_ID`nACR_ID=$ACR_ID`nAPP_NAME=$APP_NAME`nRG=$RG`nLAW_NAME=$LAW_NAME" -Encoding ASCII
Run 'Role AcrPull' { az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal --scope $ACR_ID --role AcrPull --query roleDefinitionName --output tsv }
$WEB_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
Run 'acrUseManagedIdentityCreds' { az resource update --ids "$WEB_ID/config/web" --set properties.acrUseManagedIdentityCreds=true --query properties.acrUseManagedIdentityCreds --output tsv }
Start-Sleep -Seconds 30
$APP_URL = "https://$APP_NAME.azurewebsites.net"
Run 'Restart (force le pull)' { az webapp restart --resource-group $RG --name $APP_NAME }
$tR = Get-Date; $ok = $false; $codes = @()
for ($i = 1; $i -le 60; $i++) {
    $c = curl.exe -s -m 30 -o NUL -w "%{http_code}" "$APP_URL/health"; if (-not $c) { $c = '000' }
    $codes += $c; Log "  essai $i : $c"; if ($c -eq '200') { $ok = $true; break }; Start-Sleep -Seconds 10
}
Resume 'restart -> premier 200 (s)' ([math]::Round(((Get-Date) - $tR).TotalSeconds))
Resume 'codes' ($codes -join ' ')
if (-not $ok) { Stop-Erreur "pas de 200 apres 10 min" }
Run '/model/info en ligne' { curl.exe -s "$APP_URL/model/info" }
$script:OUT | Set-Content captures\model_info_azure_s5.json -Encoding UTF8

# ---------------------------------------------------------------- Log Analytics
Run 'Espace Log Analytics (retention 30 j)' { az monitor log-analytics workspace create --resource-group $RG --workspace-name $LAW_NAME --location $LOCATION --retention-time 30 --query "{nom:name, retention:retentionInDays, sku:sku.name}" --output table }
$LAW_ID = az monitor log-analytics workspace show -g $RG -n $LAW_NAME --query id -o tsv
$LAW_GUID = az monitor log-analytics workspace show -g $RG -n $LAW_NAME --query customerId -o tsv
Add-Content -Path logs\ids_s5.txt -Value "LAW_GUID=$LAW_GUID" -Encoding ASCII
$APP_ID = $WEB_ID
function Hote { try { (Invoke-RestMethod -Uri "$APP_URL/health" -TimeoutSec 30).hostname } catch { '' } }
$AVANT = Hote; Resume 'hostname avant le parametre de diagnostic' $AVANT
Run 'Parametre de diagnostic (AppServiceConsoleLogs + AppServiceHTTPLogs)' { az monitor diagnostic-settings create --name diag-dermascan-s5 --resource $APP_ID --workspace $LAW_ID --logs "@logs_diag.json" --query "logs[].{categorie:category, actif:enabled}" --output table }
$tD = Get-Date
for ($i = 1; $i -le 90; $i++) { $H = Hote; Log "  hostname : $H"; if ($H -and $H -ne $AVANT) { break }; Start-Sleep -Seconds 10 }
Resume 'nouveau hostname, et delai apres le parametre de diagnostic (s)' ("$H, " + [math]::Round(((Get-Date) - $tD).TotalSeconds))
Run '/predict temoin (heure UTC de l appel)' { curl.exe -s -F "image=@$ID.jpg" -F "tbp_tile_type=3D: white" -H "X-Request-Id: temoin-s5-0001" "$APP_URL/predict"; (Get-Date).ToUniversalTime().ToString('HH:mm:ss') }
$tT = Get-Date
$vu = $false
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 30
    $n = az monitor log-analytics query --workspace $LAW_GUID --analytics-query "AppServiceConsoleLogs | where ResultDescription has 'temoin-s5-0001' | count" --query "[0].Count" -o tsv 2>$null
    Log "  temoin dans Log Analytics ? $n"
    if ($n -and [int]$n -gt 0) { $vu = $true; break }
}
Resume 'Mesure 10 - delai appel -> apparition dans Log Analytics (s)' ([math]::Round(((Get-Date) - $tT).TotalSeconds))

# ---------------------------------------------------------------- Rejeu sur Azure, a debit fixe (1 req/s)
Log "DEBUT DU REJEU (UTC) $((Get-Date).ToUniversalTime().ToString('HH:mm:ss'))"
Run 'Rejeu conforme (600 appels, 1 req/s)' { Py "python rejouer_flux.py $APP_URL conforme 600 1" }
Log "DEBUT DE LA DERIVE (UTC) $((Get-Date).ToUniversalTime().ToString('HH:mm:ss'))"
Run 'Rejeu derive eclairage (600 appels, 1 req/s)' { Py "python rejouer_flux.py $APP_URL derive 600 1 eclairage" }
Log "FIN DU REJEU (UTC) $((Get-Date).ToUniversalTime().ToString('HH:mm:ss'))"

# ---------------------------------------------------------------- Charge (pendant l'ingestion)
$py = $null
foreach ($c in @('py -3', 'python')) { try { Invoke-Expression "$c --version" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (-not (Test-Path .venv-locust\Scripts\locust.exe)) {
    Run 'venv Locust' { Invoke-Expression "$py -m venv .venv-locust" }
    Run 'pip install locust' { .\.venv-locust\Scripts\python.exe -m pip install --quiet --disable-pip-version-check locust }
}
Copy-Item ..\s4-dermascan\locustfile_s4.py, "$ID.jpg" locust\ -Force
Push-Location locust
$env:IMAGE_CONTROLE_S4 = "$ID.jpg"
foreach ($p in @(@(1, 10), @(2, 50))) {
    Run ("Palier {0} : {1} utilisateurs, 3 min" -f $p[0], $p[1]) { ..\.venv-locust\Scripts\locust.exe -f locustfile_s4.py --headless -u $p[1] -r 5 -t 3m --host $APP_URL --csv ("s5_palier{0}" -f $p[0]) --html ("s5_palier{0}.html" -f $p[0]) --only-summary }
}
Run 'CSV des paliers' { Get-ChildItem s5_palier*_stats.csv | ForEach-Object { $_.Name; Get-Content $_ } }
Pop-Location
$PLAN_ID = az appservice plan show -n $PLAN_NAME -g $RG --query id -o tsv
Run 'CPU / memoire du plan (PT1M)' { az monitor metrics list --resource $PLAN_ID --metric CpuPercentage MemoryPercentage --interval PT1M --offset 45m --output table }

# ---------------------------------------------------------------- Export du journal et PSI
Run 'Export du journal (2 h)' {
    $lignes = @(az monitor log-analytics query --workspace $LAW_GUID -o tsv --query "[].ResultDescription" --analytics-query "@export_journal.kql")
    [IO.File]::WriteAllLines((Join-Path $W 'journal_azure.jsonl'), [string[]]$lignes)
    "lignes exportees : $($lignes.Count)"
}
Run 'derive.py mesurer - journal Azure (fenetre 200, seuil 0.25)' { Py 'python derive.py mesurer reference_covariables.json journal_azure.jsonl 200 0.25' }
Copy-Item sorties\psi_fenetres.csv sorties\psi_fenetres_azure.csv -Force
Run 'Requete 3 : PSI de l eclairage par fenetre de 5 min' { az monitor log-analytics query --workspace $LAW_GUID --analytics-query "@requete3_cli.kql" --query "[].{fenetre:fenetre, psi:psi, appels:appels}" -o table }
Run 'Requete 4 : taux a_examiner par fenetre de 5 min' { az monitor log-analytics query --workspace $LAW_GUID --analytics-query "@requete4_cli.kql" --query "[].{fenetre:fenetre, taux:taux_a_examiner, p95_ms:p95_inference_ms, appels:appels}" -o table }
Log ""
Log "TERMINE $(Get-Date -Format s). L application et Log Analytics tournent : tableau de bord, puis nettoyage. Previens Claude."
