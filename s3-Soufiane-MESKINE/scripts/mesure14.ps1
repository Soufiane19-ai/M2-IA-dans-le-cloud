# Mesure 14 - ligne de base reseau : 20 x time_connect (et time_appconnect) sur /health
# powershell -ExecutionPolicy Bypass -File .\mesure14.ps1
Set-Location $PSScriptRoot
$APP_NAME = ((Get-Content logs\ids.txt | ConvertFrom-StringData).APP_NAME)
$URL = "https://$APP_NAME.azurewebsites.net/health"
$OUT = 'logs\mesure14.txt'
Set-Content -Path $OUT -Value "Mesure 14 - $(Get-Date -Format s) - $URL" -Encoding UTF8
for ($i = 1; $i -le 20; $i++) {
    $l = curl.exe -s -m 60 -o NUL -w "essai $i code=%{http_code} tcp=%{time_connect} tls=%{time_appconnect} total=%{time_total}" $URL
    Write-Host $l; Add-Content -Path $OUT -Value $l -Encoding UTF8
}
Write-Host "TERMINE"
