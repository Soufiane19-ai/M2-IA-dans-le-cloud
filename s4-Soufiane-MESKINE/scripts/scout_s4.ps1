# Seance 4 - mesure 15 (scan) apres `docker login`, puis colonne S2 de la mesure 17.
# powershell -ExecutionPolicy Bypass -File .\scout_s4.ps1
Set-Location $PSScriptRoot
$LOG = Join-Path $PSScriptRoot 'logs\scout_s4.log'
Set-Content -Path $LOG -Value "Scan S4 - $(Get-Date -Format s)" -Encoding UTF8
function Log([string]$s) { Write-Host $s; Add-Content -Path $LOG -Value $s -Encoding UTF8 }
Log "== docker scout version"; docker scout version 2>&1 | ForEach-Object { Log "$_" }
Log "== docker scout quickview"; docker scout quickview "local://dermascan-api:2.0.0" 2>&1 | ForEach-Object { Log "$_" }
Log "== docker scout cves --exit-code"
$sortie = @(docker scout cves --exit-code --platform linux/amd64 "local://dermascan-api:2.0.0" 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE
$sortie | ForEach-Object { Log $_ }
$sortie | Set-Content captures\scout_cves_s4.txt -Encoding UTF8
Log "[RESUME] Mesure 15 - code retour de docker scout cves --exit-code = $code"
Log "== recommandations d'image de base"; docker scout recommendations "local://dermascan-api:2.0.0" 2>&1 | Select-Object -First 60 | ForEach-Object { Log "$_" }
Log "TERMINE scan"
& (Join-Path $PSScriptRoot 'mesurer_s2.ps1')
