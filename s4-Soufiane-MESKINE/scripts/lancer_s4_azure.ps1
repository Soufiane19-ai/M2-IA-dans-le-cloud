# Seance 4 - partie 5.5 : publier 2.0.0 dans le registre conserve, deployer sur B1, charge Locust.
# powershell -ExecutionPolicy Bypass -File .\lancer_s4_azure.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, locust | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s4_azure.log'
Set-Content -Path $LOG -Value "TP S4 Azure - debut $(Get-Date -Format s)" -Encoding UTF8
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
function Stop-Erreur([string]$msg) { Log "ARRET : $msg"; Read-Host "Entree pour fermer"; exit 1 }

$SUFFIX = 'sm26'
$RG_REGISTRE = "rg-dermascan-registre-$SUFFIX"     # LECTURE SEULE
$RG = "rg-dermascan-s4-$SUFFIX"                     # seul groupe cree puis detruit
$ACR_NAME = "acrdermascan$SUFFIX"
$PLAN_NAME = "plan-dermascan-s4-$SUFFIX"
$APP_NAME = "dermascan-api-s4-$SUFFIX"
$TAG = '2.0.0'

az account set --subscription "Azure for Students"
Run 'Compte' { az account show --query "{abonnement:name, utilisateur:user.name}" --output table }
$LOCATION = az acr show --name $ACR_NAME --query location --output tsv
if (-not $LOCATION) { Stop-Erreur "registre $ACR_NAME introuvable (az login ?)" }
Resume 'LOCATION' $LOCATION

# ---------------------------------------------------------------- Publication
Run 'az acr login' { az acr login --name $ACR_NAME }
$LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
$IMAGE_FULL = "$LOGIN_SERVER/dermascan-api:$TAG"
docker tag "dermascan-api:$TAG" $IMAGE_FULL
Run "docker push $IMAGE_FULL" { docker push $IMAGE_FULL }
if ($CODE -ne 0) { Run 'docker push (reprise)' { docker push $IMAGE_FULL } }
if ($CODE -ne 0) { Stop-Erreur "push impossible" }
Resume 'Mesure 18 - duree du push (s)' $DUREE
Run 'Tags du depot dermascan-api' { az acr repository show-tags --name $ACR_NAME --repository dermascan-api --output table }
Run 'Manifeste 2.0.0 (digest, taille)' { az acr manifest list-metadata --registry $ACR_NAME --name dermascan-api --query "[?tags[?@=='$TAG']].{digest:digest, octets:imageSize, arch:architecture, cree:createdTime}" --output table }
$DIGEST = az acr repository show --name $ACR_NAME --image "dermascan-api:$TAG" --query digest --output tsv
Resume 'digest 2.0.0' $DIGEST

# ---------------------------------------------------------------- Deploiement (routine S3)
Run 'Groupe de seance' { az group create --name $RG --location $LOCATION --tags projet=dermascan seance=s4 proprietaire=soufiane.meskine a_detruire=2026-11-17 --query "{nom:name, etat:properties.provisioningState}" --output table }
Run 'Plan B1' { az appservice plan create --name $PLAN_NAME --resource-group $RG --location $LOCATION --is-linux --sku B1 --query "{nom:name, sku:sku.name, etat:provisioningState}" --output table }
if ($CODE -ne 0) { Stop-Erreur "creation du plan impossible" }
Run 'Application' { az webapp create --resource-group $RG --plan $PLAN_NAME --name $APP_NAME --container-image-name $IMAGE_FULL --query "{nom:name, hote:defaultHostName}" --output table }
if ($CODE -ne 0) { Stop-Erreur "creation de l application impossible" }
Run 'Reglages' { az webapp config appsettings set --resource-group $RG --name $APP_NAME --settings WEBSITES_PORT=8000 PORT=8000 MODEL_VERSION=$TAG WEBSITES_CONTAINER_START_TIME_LIMIT=600 WEBSITES_ENABLE_APP_SERVICE_STORAGE=false --query "[].name" --output tsv }
Run 'Identite managee' { az webapp identity assign --resource-group $RG --name $APP_NAME --query principalId --output tsv }
$PRINCIPAL_ID = az webapp identity show --resource-group $RG --name $APP_NAME --query principalId --output tsv
$ACR_ID = az acr show --name $ACR_NAME --query id --output tsv
Set-Content -Path logs\ids_s4.txt -Value "PRINCIPAL_ID=$PRINCIPAL_ID`nACR_ID=$ACR_ID`nAPP_NAME=$APP_NAME`nRG=$RG" -Encoding ASCII
Run 'Role AcrPull sur le registre' { az role assignment create --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal --scope $ACR_ID --role AcrPull --query "{role:roleDefinitionName, portee:scope}" --output table }
$WEB_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
Run 'acrUseManagedIdentityCreds' { az resource update --ids "$WEB_ID/config/web" --set properties.acrUseManagedIdentityCreds=true --query properties.acrUseManagedIdentityCreds --output tsv }
Start-Sleep -Seconds 30
$APP_URL = "https://$APP_NAME.azurewebsites.net"
Run 'Restart (force le pull)' { az webapp restart --resource-group $RG --name $APP_NAME }
$tR = Get-Date; Log "Restart a $($tR.ToString('HH:mm:ss')) : attente du premier 200 (jusqu'a 15 min)"
$ok = $false; $codes = @()
for ($i = 1; $i -le 60; $i++) {
    $c = curl.exe -s -m 60 -o NUL -w "%{http_code}" "$APP_URL/health"; if (-not $c) { $c = '000' }
    $codes += $c; Log "  essai $i : $c"
    if ($c -eq '200') { $ok = $true; break }
    Start-Sleep -Seconds 15
}
Resume 'Mesure 18 - restart -> premier 200 (s)' ([math]::Round(((Get-Date) - $tR).TotalSeconds))
Resume 'Mesure 18 - codes' ($codes -join ' ')
if (-not $ok) {
    az webapp log download --resource-group $RG --name $APP_NAME --log-file logs\logs_s4_echec.zip
    Stop-Erreur "pas de 200 apres 15 min (logs dans logs\logs_s4_echec.zip)"
}
Run '/health en ligne' { curl.exe -s "$APP_URL/health" }
Run '/model/info en ligne' { curl.exe -s "$APP_URL/model/info" }
$script:OUT | Set-Content captures\model_info_azure.json -Encoding UTF8
$ID = (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).controle.isic_id
Run "/predict en ligne ($ID)" { curl.exe -s -F "image=@$ID.jpg" "$APP_URL/predict" }
$script:OUT | Set-Content captures\predict_azure.json -Encoding UTF8
Run 'Latence sur une connexion reutilisee (6 x /predict, la 1re ouvre la connexion TLS)' {
    $a = @(); 1..6 | ForEach-Object { $a += @('-o', 'NUL', '-F', "image=@$ID.jpg", "$APP_URL/predict"); if ($_ -lt 6) { $a += '--next' } }
    curl.exe -s -w "%{http_code} tls=%{time_appconnect} total=%{time_total}\n" @a
}

# ---------------------------------------------------------------- Charge
$py = $null
foreach ($c in @('py -3', 'python')) { try { Invoke-Expression "$c --version" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {} }
if (-not (Test-Path .venv-locust\Scripts\locust.exe)) {
    Run 'venv Locust' { Invoke-Expression "$py -m venv .venv-locust" }
    Run 'pip install locust' { .\.venv-locust\Scripts\python.exe -m pip install --quiet --disable-pip-version-check locust }
}
Run 'locust --version' { .\.venv-locust\Scripts\locust.exe --version }
Copy-Item locustfile_s4.py, "$ID.jpg" locust\ -Force
Push-Location locust
$env:IMAGE_CONTROLE_S4 = "$ID.jpg"
foreach ($p in @(@(1, 10), @(2, 50))) {
    Run ("Palier {0} : {1} utilisateurs, 3 min" -f $p[0], $p[1]) { ..\.venv-locust\Scripts\locust.exe -f locustfile_s4.py --headless -u $p[1] -r 5 -t 3m --host $APP_URL --csv ("palier_s4_{0}" -f $p[0]) --html ("palier_s4_{0}.html" -f $p[0]) --only-summary }
}
Run 'CSV des paliers' { Get-ChildItem palier_s4_*_stats.csv | ForEach-Object { $_.Name; Get-Content $_ } }
Pop-Location
$PLAN_ID = az appservice plan show --name $PLAN_NAME --resource-group $RG --query id --output tsv
$APP_ID = az webapp show --resource-group $RG --name $APP_NAME --query id --output tsv
Run 'CPU / memoire du plan par minute' { az monitor metrics list --resource $PLAN_ID --metric CpuPercentage MemoryPercentage --interval PT1M --offset 20m --output table }
Run 'Requetes, 5xx, temps de reponse serveur par minute' { az monitor metrics list --resource $APP_ID --metric Requests Http5xx HttpResponseTime --interval PT1M --offset 20m --output table }
Log ""
Log "TERMINE $(Get-Date -Format s). L application tourne encore (nettoyage ensuite)."
