# Seance 4 - nettoyage obligatoire (partie 7, mesure 21). A lancer apres releve des mesures.
# powershell -ExecutionPolicy Bypass -File .\nettoyage_s4.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
$LOG = Join-Path $PSScriptRoot 'logs\nettoyage_s4.log'
Set-Content -Path $LOG -Value "Nettoyage S4 - $(Get-Date -Format s)" -Encoding UTF8
function Run([string]$titre, [scriptblock]$sb) {
    $o = @(& $sb 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' })
    Add-Content -Path $LOG -Value ("`n===== $titre ($(Get-Date -Format HH:mm:ss)) =====") -Encoding UTF8
    $o | ForEach-Object { Write-Host $_; Add-Content -Path $LOG -Value $_ -Encoding UTF8 }
}
$RG = 'rg-dermascan-s4-sm26'
$ids = Get-Content logs\ids_s4.txt | ConvertFrom-StringData
$PRINCIPAL_ID = $ids.PRINCIPAL_ID; $ACR_ID = $ids.ACR_ID
az account set --subscription "Azure for Students"
Run 'Archive des logs de l application' { az webapp log download --resource-group $RG --name $ids.APP_NAME --log-file logs\logs_s4.zip }
Run 'Inventaire avant destruction' { az resource list --resource-group $RG --output table }
Run 'Attributions sur le registre (avant)' { az role assignment list --scope $ACR_ID --output table }
Run 'Suppression de l attribution AcrPull' { az role assignment delete --assignee-object-id $PRINCIPAL_ID --scope $ACR_ID }
Run 'Suppression du groupe de la seance' { az group delete --name $RG --yes --no-wait }
for ($i = 1; $i -le 40; $i++) {
    $e = az group exists --name $RG
    Add-Content -Path $LOG -Value "$(Get-Date -Format HH:mm:ss) az group exists = $e" -Encoding UTF8; Write-Host "az group exists = $e"
    if ($e -eq 'false') { break }
    Start-Sleep -Seconds 15
}
Run 'Attributions sur le registre (apres)' { az role assignment list --scope $ACR_ID --output table }
Run 'az group list' { az group list --output table }
Run 'Ressources du groupe registre' { az resource list --resource-group rg-dermascan-registre-sm26 --output table }
Run 'Tags du depot dermascan-api (conserves)' { az acr repository show-tags --name acrdermascansm26 --repository dermascan-api --output table }
Run 'Arret des conteneurs locaux' { docker rm -f dermascan-api-s4 dermascan-api-s2 2>&1; docker ps -a --format '{{.Names}} {{.Status}}' }
if (Test-Path .venv-locust) { Remove-Item -Recurse -Force .venv-locust; Add-Content -Path $LOG -Value "venv Locust supprime" -Encoding UTF8 }
Write-Host "`nTERMINE."
