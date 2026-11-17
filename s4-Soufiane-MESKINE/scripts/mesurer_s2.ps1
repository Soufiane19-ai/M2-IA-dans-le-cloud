# Seance 4 - mesure 17, colonne S2 : memes mesures sur l'image dermascan-api:1.0.0 (si presente).
# powershell -ExecutionPolicy Bypass -File .\mesurer_s2.ps1
Set-Location $PSScriptRoot
$LOG = Join-Path $PSScriptRoot 'logs\mesures_s2.log'
Set-Content -Path $LOG -Value "Mesures S2 - $(Get-Date -Format s)" -Encoding UTF8
function Log([string]$s) { $l = "$(Get-Date -Format 'HH:mm:ss') $s"; Write-Host $l; Add-Content -Path $LOG -Value $l -Encoding UTF8 }
docker image inspect dermascan-api:1.0.0 --format 'Size={{.Size}}' 2>&1 | ForEach-Object { Log "image 1.0.0 : $_" }
if ($LASTEXITCODE -ne 0) {
    Log "image 1.0.0 absente : on la tire du registre"
    az acr login --name acrdermascansm26 2>&1 | ForEach-Object { Log "$_" }
    docker pull acrdermascansm26.azurecr.io/dermascan-api:1.0.0 2>&1 | Select-Object -Last 3 | ForEach-Object { Log "$_" }
    docker tag acrdermascansm26.azurecr.io/dermascan-api:1.0.0 dermascan-api:1.0.0
}
docker images dermascan-api 2>&1 | ForEach-Object { Log "$_" }
docker rm -f dermascan-api-s2 2>$null | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
docker run -d --name dermascan-api-s2 -p 8002:8000 dermascan-api:1.0.0 | Out-Null
for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8002/health; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 }
$sw.Stop(); Log ("[RESUME] S2 demarrage jusqu au premier /health 200 (s) = {0:N1}" -f $sw.Elapsed.TotalSeconds)
Copy-Item ..\s2-dermascan\charge.json charge_s2.json -Force
for ($i = 1; $i -le 5; $i++) { curl.exe -s -o NUL -X POST -H "Content-Type: application/json" --data-binary "@charge_s2.json" http://localhost:8002/predict }
$t = @(); for ($i = 1; $i -le 50; $i++) { $t += [double]::Parse((curl.exe -s -o NUL -w "%{time_total}" -X POST -H "Content-Type: application/json" --data-binary "@charge_s2.json" http://localhost:8002/predict), [Globalization.CultureInfo]::InvariantCulture) }
$t = $t | Sort-Object
Log ("[RESUME] S2 latence /predict p50 / p95 (ms), 50 appels = {0:N1} / {1:N1}" -f ($t[24] * 1000), ($t[47] * 1000))
Start-Sleep -Seconds 10
docker stats --no-stream dermascan-api-s2 2>&1 | ForEach-Object { Log "$_" }
docker rm -f dermascan-api-s2 | Out-Null
Log "TERMINE"
