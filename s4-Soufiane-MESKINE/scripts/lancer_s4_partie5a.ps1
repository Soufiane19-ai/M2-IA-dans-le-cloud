# Seance 4 - partie 5 (locale) : image 2.0.0, scan, demarrage hors ligne, concordance, cout de la substitution.
# powershell -ExecutionPolicy Bypass -File .\lancer_s4_partie5a.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, api-s4\model | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s4_partie5a.log'
Set-Content -Path $LOG -Value "TP S4 partie 5a - debut $(Get-Date -Format s)" -Encoding UTF8
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
$TAG = '2.0.0'

# ---------------------------------------------------------------- 5.1 Contexte de construction
Copy-Item model\modele.pt, model\modele_meta.json api-s4\model\ -Force
Run 'Contexte api-s4' { Get-ChildItem api-s4 -Recurse -Force | Select-Object FullName, Length | Format-Table -AutoSize | Out-String }
Run 'diff Dockerfile S2 / S4' { Compare-Object (Get-Content ..\s2-dermascan\Dockerfile) (Get-Content api-s4\Dockerfile) | Format-Table -AutoSize | Out-String -Width 200 }
Run 'diff .dockerignore S2 / S4' { Compare-Object (Get-Content ..\s2-dermascan\.dockerignore) (Get-Content api-s4\.dockerignore) | Format-Table -AutoSize | Out-String -Width 200 }
Run 'diff app.py S2 / S4 (lignes)' { Compare-Object (Get-Content ..\s2-dermascan\app.py) (Get-Content api-s4\app.py) | Measure-Object | Select-Object -ExpandProperty Count }
Run 'sha256 api-s4/model/modele.pt' { (Get-FileHash api-s4\model\modele.pt -Algorithm SHA256).Hash.ToLower() }

# ---------------------------------------------------------------- 5.2 Construction a froid et scan
Run "docker build a froid dermascan-api:$TAG" { docker build --no-cache --pull --platform linux/amd64 --provenance=false -t "dermascan-api:$TAG" api-s4 }
if ($CODE -ne 0) { Stop-Erreur "echec de la construction" }
Resume 'Mesure 15 - duree de construction a froid (s)' $DUREE
Run 'docker images dermascan-api' { docker images dermascan-api }
Run 'docker image inspect (taille, arch, user)' { docker image inspect "dermascan-api:$TAG" --format 'Size={{.Size}} Arch={{.Architecture}} User={{.Config.User}} Id={{.Id}}' }
Run 'docker scout quickview' { docker scout quickview "local://dermascan-api:$TAG" }
Run 'docker scout cves --exit-code' { docker scout cves --exit-code --platform linux/amd64 "local://dermascan-api:$TAG" }
Resume 'Mesure 15 - code retour de docker scout cves --exit-code' $CODE
$script:OUT | Set-Content captures\scout_cves_s4.txt -Encoding UTF8
Run 'docker scout cves (resume par paquet)' { docker scout cves --format only-packages --only-vuln-packages "local://dermascan-api:$TAG" }

# ---------------------------------------------------------------- 5.3 Demarrage sans reseau
docker rm -f dermascan-s4-horsligne dermascan-api-s4 2>$null | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
docker run -d --name dermascan-s4-horsligne --network none "dermascan-api:$TAG" | Out-Null
$ok = $false
for ($i = 0; $i -lt 300; $i++) {
    docker exec dermascan-s4-horsligne python -c "import urllib.request as u;u.urlopen('http://localhost:8000/health')" 2>$null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Milliseconds 500
}
$sw.Stop()
Resume 'Mesure 16 - delai jusqu au premier /health 200 sous --network none (s)' ([math]::Round($sw.Elapsed.TotalSeconds, 1))
Run 'Corps de /health (hors ligne)' { docker exec dermascan-s4-horsligne python -c "import urllib.request as u;print(u.urlopen('http://localhost:8000/health').read().decode())" }
Run 'Reseau du conteneur hors ligne' { docker inspect -f '{{json .NetworkSettings.Networks}}' dermascan-s4-horsligne }
docker rm -f dermascan-s4-horsligne | Out-Null
if (-not $ok) { Stop-Erreur "le conteneur hors ligne ne repond pas" }

# ---------------------------------------------------------------- Concordance
$ID = (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).controle.isic_id
docker run --rm -v "${PSScriptRoot}:/work" dermascan-entrainement:s4 python -c "import zipfile;z=zipfile.ZipFile('donnees/ISIC_2024_Permissive_Training_Input.zip');open('$ID.jpg','wb').write(z.read('ISIC_2024_Permissive_Training_Input/$ID.jpg'))"
$sw = [Diagnostics.Stopwatch]::StartNew()
docker run -d --name dermascan-api-s4 -p 8000:8000 -e MODEL_VERSION=$TAG "dermascan-api:$TAG" | Out-Null
for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8000/health; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 }
$sw.Stop()
Resume 'Mesure 17 - demarrage jusqu au premier /health 200, avec reseau (s)' ([math]::Round($sw.Elapsed.TotalSeconds, 1))
Run '/model/info' { curl.exe -s http://localhost:8000/model/info }
$script:OUT | Set-Content captures\model_info_local.json -Encoding UTF8
Run "/predict image de controle $ID" { curl.exe -s -F "image=@$ID.jpg" http://localhost:8000/predict }
$script:OUT | Set-Content captures\predict_local.json -Encoding UTF8
Run 'controle du meta' { (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).controle | ConvertTo-Json -Compress }
Run 'Codes : sans image / pas une image' { curl.exe -s -o NUL -w "sans image : %{http_code}`n" -X POST http://localhost:8000/predict; curl.exe -s -w "`npas une image : %{http_code}`n" -F "image=@app.py" http://localhost:8000/predict }

# ---------------------------------------------------------------- 5.4 Cout de la substitution
for ($i = 1; $i -le 5; $i++) { curl.exe -s -o NUL -F "image=@$ID.jpg" http://localhost:8000/predict }
$t = @(); for ($i = 1; $i -le 50; $i++) { $t += [double]::Parse((curl.exe -s -o NUL -w "%{time_total}" -F "image=@$ID.jpg" http://localhost:8000/predict), [Globalization.CultureInfo]::InvariantCulture) }
$t = $t | Sort-Object
Resume 'Mesure 17 - latence /predict p50 / p95 (ms), 50 appels' ("{0:N1} / {1:N1}" -f ($t[24] * 1000), ($t[47] * 1000))
Log ("  50 valeurs (s) : " + (($t | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ' '))
Start-Sleep -Seconds 10
Run 'docker stats au repos' { docker stats --no-stream dermascan-api-s4 }
Run 'Processus dans le conteneur' { docker top dermascan-api-s4 }

# ---------------------------------------------------------------- Image S2 pour comparaison (si encore presente)
Run 'Image S2 encore presente ?' { docker image inspect dermascan-api:1.0.0 --format 'Size={{.Size}} Created={{.Created}}' }
Log ""
Log "TERMINE $(Get-Date -Format s). Le conteneur dermascan-api-s4 tourne encore (port 8000). Previens Claude."
