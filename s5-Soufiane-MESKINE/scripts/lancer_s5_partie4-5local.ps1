# Seance 5 - partie 4 (image sans PyTorch, journal) et partie 5.2 (derive provoquee, en local).
# powershell -ExecutionPolicy Bypass -File .\lancer_s5_partie4-5local.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, sorties, api-s5\model | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s5_partie4-5local.log'
Set-Content -Path $LOG -Value "TP S5 parties 4-5 locales - debut $(Get-Date -Format s)" -Encoding UTF8
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
function Sel { $b = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $_.ToString('x2') }) }

$W = $PSScriptRoot
$S4 = Join-Path (Split-Path $W -Parent) 's4-dermascan'
$DON = Join-Path $S4 'donnees'
$OUTILS = 'dermascan-outils:s5'
function Py([string]$cmd) { docker run --rm --add-host host.docker.internal:host-gateway -v "${W}:/work" -v "${DON}:/work/donnees" $OUTILS sh -c $cmd }
$VERSION = '2.1.0'          # decision 3.3 : variante ONNX float32 (meme calcul que 2.0.0), contrat enrichi
$VARIANTE = 'onnx_fp32'
$ID = (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).controle.isic_id
Copy-Item "$S4\$ID.jpg" . -Force

# ---------------------------------------------------------------- 4.1 diff app.py S4 / S5
Run 'diff app.py S4 / S5 (nombre de lignes differentes)' { (Compare-Object (Get-Content "$S4\api-s4\app.py") (Get-Content app.py)).Count }

# ---------------------------------------------------------------- 4.2 Contexte de construction
Copy-Item Dockerfile, requirements.txt, app.py api-s5\ -Force
(Get-Content "$S4\api-s4\.dockerignore") + '**/*.pt' | Set-Content api-s5\.dockerignore -Encoding ASCII
Copy-Item model\modele.onnx api-s5\model\modele.onnx -Force
Run 'meta de l image S5' { Py "python outils_s5.py meta $VERSION $VARIANTE" }
Run 'diff Dockerfile S4 / S5' { Compare-Object (Get-Content "$S4\api-s4\Dockerfile") (Get-Content api-s5\Dockerfile) | Format-Table -AutoSize | Out-String -Width 220 }
Run 'diff .dockerignore S4 / S5' { Compare-Object (Get-Content "$S4\api-s4\.dockerignore") (Get-Content api-s5\.dockerignore) | Format-Table -AutoSize | Out-String }
Run 'Contexte api-s5' { Get-ChildItem api-s5 -Recurse -Force | Select-Object FullName, Length | Format-Table -AutoSize | Out-String -Width 220 }
Run 'docker history de l image S4 (question 4.5)' { docker history dermascan-api:2.0.0 --format '{{.Size}}  {{.CreatedBy}}' }

# ---------------------------------------------------------------- 4.3 Construire, scanner, demarrer hors ligne
Run "docker build dermascan-api:$VERSION" { docker build --pull --platform linux/amd64 --provenance=false -t "dermascan-api:$VERSION" api-s5 }
if ($CODE -ne 0) { Stop-Erreur "construction impossible" }
Resume 'Mesure 5 - duree de construction (s)' $DUREE
Run 'docker images dermascan-api' { docker images dermascan-api }
Run 'docker scout cves --exit-code' { docker scout cves --exit-code --platform linux/amd64 "local://dermascan-api:$VERSION" }
Resume 'Mesure 5 - code retour scout' $CODE
$script:OUT | Set-Content captures\scout_cves_s5.txt -Encoding UTF8
$SCOUT = $CODE
Run 'docker scout quickview' { docker scout quickview "local://dermascan-api:$VERSION" }
docker rm -f dermascan-s5-horsligne dermascan-api-s5 dermascan-s5-1cpu dermascan-s5-1cpu-8fils 2>$null | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
docker run -d --name dermascan-s5-horsligne --network none "dermascan-api:$VERSION" | Out-Null
for ($i = 0; $i -lt 300; $i++) { docker exec dermascan-s5-horsligne python -c "import urllib.request as u;u.urlopen('http://localhost:8000/health')" 2>$null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep -Milliseconds 500 }
$sw.Stop(); Resume 'Mesure 6 - demarrage hors ligne jusqu au premier 200 (s)' ([math]::Round($sw.Elapsed.TotalSeconds, 1))
docker rm -f dermascan-s5-horsligne | Out-Null
Run 'docker history S5' { docker history "dermascan-api:$VERSION" --format '{{.Size}}  {{.CreatedBy}}' }
Run 'Taille des images' { docker image inspect "dermascan-api:2.0.0" "dermascan-api:$VERSION" --format '{{index .RepoTags 0}} Size={{.Size}}' }

# ---------------------------------------------------------------- 4.4 Concordance et journal
docker run -d --name dermascan-api-s5 -p 8000:8000 -e MODEL_VERSION=$VERSION -e ENVIRONMENT=local -e INFERENCE_LOG_SALT=$(Sel) "dermascan-api:$VERSION" | Out-Null
for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8000/health; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 }
Run '/model/info' { curl.exe -s http://localhost:8000/model/info }
$script:OUT | Set-Content captures\model_info_local_s5.json -Encoding UTF8
Run '/predict avec covariables et X-Patient-Ref' { curl.exe -s -F "image=@$ID.jpg" -F age_approx=60 -F sex=male -F "tbp_tile_type=3D: white" -H "X-Patient-Ref: IP_0000001" http://localhost:8000/predict }
$script:OUT | Set-Content captures\predict_local_s5.json -Encoding UTF8
Run '/predict avec tbp_tile_type=UV' { curl.exe -s -w "`ncode %{http_code}" -F "image=@$ID.jpg" -F tbp_tile_type=UV http://localhost:8000/predict }
Run '/predict sans covariable (poste S4)' { curl.exe -s -w "`ncode %{http_code}" -F "image=@$ID.jpg" http://localhost:8000/predict }
Start-Sleep -Seconds 1
Run 'Deux dernieres lignes de journal' { docker logs dermascan-api-s5 2>&1 | Where-Object { "$_".StartsWith('{') } | Select-Object -Last 3 }
$script:OUT | Set-Content captures\journal_exemple.txt -Encoding UTF8
Run 'Le patient_ref contient-il IP_0000001 en clair ?' { if ((docker logs dermascan-api-s5 2>&1 | Out-String) -match 'IP_0000001') { 'OUI (fuite)' } else { 'non' } }

# ---------------------------------------------------------------- 4.5 Ce que l image a gagne
function Latence([int]$port) {
    for ($i = 1; $i -le 5; $i++) { curl.exe -s -o NUL -F "image=@$ID.jpg" "http://localhost:$port/predict" }
    $t = @(); for ($i = 1; $i -le 50; $i++) { $t += [double]::Parse((curl.exe -s -o NUL -w "%{time_total}" -F "image=@$ID.jpg" "http://localhost:$port/predict"), [Globalization.CultureInfo]::InvariantCulture) }
    $t = $t | Sort-Object; return ("{0:N1} / {1:N1}" -f ($t[24] * 1000), ($t[47] * 1000))
}
Resume 'Mesure 6 - latence p50 / p95 (ms), sans limite' (Latence 8000)
Start-Sleep -Seconds 10
Run 'docker stats au repos' { docker stats --no-stream dermascan-api-s5 }
docker run -d --name dermascan-s5-1cpu --cpus 1 -p 8001:8000 "dermascan-api:$VERSION" | Out-Null
docker run -d --name dermascan-s5-1cpu-8fils --cpus 1 -e ORT_THREADS=8 -p 8002:8000 "dermascan-api:$VERSION" | Out-Null
foreach ($p in 8001, 8002) { for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$p/health"; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 } }
Resume 'Mesure 6 - latence p50 / p95 (ms), --cpus 1, ORT_THREADS=1' (Latence 8001)
Resume 'Mesure 6 - latence p50 / p95 (ms), --cpus 1, ORT_THREADS=8' (Latence 8002)
docker rm -f dermascan-s5-1cpu dermascan-s5-1cpu-8fils | Out-Null
# Memes mesures sur l'image S4 sous --cpus 1, pour comparer a usage egal
docker run -d --name dermascan-s4-1cpu --cpus 1 -p 8003:8000 "dermascan-api:2.0.0" | Out-Null
for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:8003/health"; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 }
Resume 'Comparaison - S4 (PyTorch) sous --cpus 1, p50 / p95 (ms)' (Latence 8003)
docker rm -f dermascan-s4-1cpu | Out-Null

# ---------------------------------------------------------------- 5.2 Derive provoquee : eclairage
function Rejeu([string]$levier, [string]$nom) {
    docker rm -f dermascan-api-s5 2>$null | Out-Null
    docker run -d --name dermascan-api-s5 -p 8000:8000 -e MODEL_VERSION=$VERSION -e ENVIRONMENT=local -e INFERENCE_LOG_SALT=$(Sel) "dermascan-api:$VERSION" | Out-Null
    for ($i = 0; $i -lt 300; $i++) { $c = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8000/health; if ($c -eq '200') { break }; Start-Sleep -Milliseconds 500 }
    Run "Rejeu conforme (400 appels) - $levier" { Py 'python rejouer_flux.py http://host.docker.internal:8000 conforme 400 0' }
    Run "Rejeu derive (400 appels) - $levier" { Py "python rejouer_flux.py http://host.docker.internal:8000 derive 400 0 $levier" }
    docker logs dermascan-api-s5 2>&1 | ForEach-Object { "$_" } | Set-Content $nom -Encoding UTF8
    Run "derive.py mesurer - $levier (fenetre 200, seuil 0.25)" { Py "python derive.py mesurer reference_covariables.json $nom 200 0.25" }
    Copy-Item sorties\psi_fenetres.csv "sorties\psi_fenetres_$levier.csv" -Force
}
Rejeu 'eclairage' 'journal_local.jsonl'
Rejeu 'age' 'journal_local_age.jsonl'
# Le dernier passage demande par l'enonce est celui de l'eclairage : on le remet en place.
Copy-Item sorties\psi_fenetres_eclairage.csv sorties\psi_fenetres.csv -Force
docker rm -f dermascan-api-s5 | Out-Null
Log ""
if ($SCOUT -ne 0) { Log "ATTENTION : docker scout a rendu le code $SCOUT (porte zero CVE)." }
Log "TERMINE $(Get-Date -Format s)."
