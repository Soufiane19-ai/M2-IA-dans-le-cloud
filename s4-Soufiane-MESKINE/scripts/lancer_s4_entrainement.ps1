# Seance 4 - parties 1 a 3 : donnees, echantillon, entrainement (CPU, conteneur Linux), verification.
# powershell -ExecutionPolicy Bypass -File .\lancer_s4_entrainement.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, donnees, model, sorties, captures, env-entrainement | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s4_entrainement.log'
Set-Content -Path $LOG -Value "TP S4 entrainement - debut $(Get-Date -Format s)" -Encoding UTF8
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

$IMG = 'dermascan-entrainement:s4'
$W = $PSScriptRoot

# ---------------------------------------------------------------- 0. Docker
Run 'Docker (version, CPU, memoire, architecture)' { docker info --format '{{.ServerVersion}} | NCPU {{.NCPU}} | MemTotal {{.MemTotal}} | {{.OSType}}/{{.Architecture}}' }
if ($LASTEXITCODE -ne 0) { Stop-Erreur "Docker ne repond pas : demarre Docker Desktop puis relance" }
Run 'Processeur du poste' { Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors | Format-List | Out-String }

# ---------------------------------------------------------------- 1.1 Donnees
# L'ancienne adresse de l'enonce (isic-challenge-data.s3.amazonaws.com/2024) renvoie desormais une page HTML
# de 428 octets 'This file has moved' : nouvelle adresse ci-dessous.
$B = 'https://isic-archive.s3.amazonaws.com/challenges/2024'
Get-ChildItem donnees -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 100000 -and $_.Name -like 'ISIC_2024_Permissive_*' } | Remove-Item
$ZIP = 'donnees\ISIC_2024_Permissive_Training_Input.zip'
$ATTENDU = 653107434
if (-not (Test-Path $ZIP) -or (Get-Item $ZIP).Length -lt 600000000) {
    Run 'Telechargement de l archive des vignettes (623 Mio)' { curl.exe -L -C - --retry 5 -s -S -o $ZIP "$B/ISIC_2024_Permissive_Training_Input.zip"; "taille : $((Get-Item $ZIP).Length) octets" }
}
if ((Get-Item $ZIP).Length -lt 600000000) { Stop-Erreur "archive incomplete ($((Get-Item $ZIP).Length) octets au lieu de $ATTENDU) : relance le script, le telechargement reprendra" }
Resume 'archive (octets)' (Get-Item $ZIP).Length
if (-not (Test-Path 'donnees\ISIC_2024_Permissive_Training_GroundTruth.csv')) {
    curl.exe -L -s -S -o donnees\ISIC_2024_Permissive_Training_GroundTruth.csv "$B/ISIC_2024_Permissive_Training_GroundTruth.csv"
}
if (-not (Test-Path 'donnees\train-metadata.csv.zip') -and -not (Test-Path 'donnees\train-metadata.csv')) {
    Copy-Item "$env:USERPROFILE\Downloads\train-metadata.csv.zip" donnees\ -ErrorAction SilentlyContinue
}
if (-not (Test-Path 'donnees\train-metadata.csv.zip') -and -not (Test-Path 'donnees\train-metadata.csv')) { Stop-Erreur "train-metadata.csv(.zip) de S2 introuvable (attendu dans Telechargements)" }
Run 'Contenu de donnees\' { Get-ChildItem donnees | Select-Object Name, Length | Format-Table -AutoSize | Out-String }
Run 'sha256 des donnees' { Get-ChildItem donnees -File | Where-Object { $_.Name -notlike 'cache_*' } | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower().Substring(0,16))  $(Split-Path $_.Path -Leaf)" } }

# ---------------------------------------------------------------- Environnement d'entrainement (conteneur Linux)
Copy-Item Dockerfile.entrainement env-entrainement\Dockerfile -Force
Run 'Construction de l environnement d entrainement' { docker build -t $IMG env-entrainement }
if ($LASTEXITCODE -ne 0) { Stop-Erreur "echec de construction de $IMG" }
Run 'Versions dans le conteneur' { docker run --rm $IMG python -c "import sys,torch,torchvision,sklearn,pandas;print(sys.version.split()[0],'torch',torch.__version__,'torchvision',torchvision.__version__,'sklearn',sklearn.__version__,'pandas',pandas.__version__,'threads',torch.get_num_threads())" }

# ---------------------------------------------------------------- 1.2 Inventaire (deux lancements)
Get-ChildItem donnees -Filter 'cache_*.npy' -ErrorAction SilentlyContinue | Remove-Item
Run 'python donnees.py (premier lancement)' { docker run --rm -e N_NEGATIFS=5000 -v "${W}:/work" $IMG python donnees.py }
Resume 'Mesure 1 - duree premier lancement (s)' $DUREE
Run 'python donnees.py (second lancement, cache .npy)' { docker run --rm -e N_NEGATIFS=5000 -v "${W}:/work" $IMG python donnees.py }
Resume 'Mesure 1 - duree second lancement (s)' $DUREE
Run 'sha256 du manifeste' { (Get-FileHash model\manifeste_echantillon.csv -Algorithm SHA256).Hash.ToLower() }
Run 'Analyses (mesures 3, 4, 5, 20, question 3.1)' { docker run --rm -e N_NEGATIFS=5000 -v "${W}:/work" $IMG sh -c "python analyses_s4.py > logs/analyses_s4.json && echo ok" }

# ---------------------------------------------------------------- 3.2 / 3.3 Entrainement, coupure volontaire pendant l'epoque 2
Remove-Item sorties\reprise.pt -ErrorAction SilentlyContinue
docker rm -f s4-entrainement s4-entrainement-reprise 2>$null | Out-Null
Log ""; Log "===== Entrainement : premier lancement (sera interrompu pendant l'epoque 2) ====="
docker run -d --name s4-entrainement -e N_NEGATIFS=5000 -v "${W}:/work" $IMG python -u entrainer.py | Out-Null
$t0 = Get-Date
$fini1 = $false
while ($true) {
    Start-Sleep -Seconds 10
    $l = @(docker logs s4-entrainement 2>&1 | ForEach-Object { "$_" })
    $etat = docker inspect -f '{{.State.Running}}' s4-entrainement
    if ($l | Where-Object { $_ -match '^epoque 1 ' }) { break }
    if ($etat -ne 'true') { $fini1 = $true; break }
    Write-Host ("  {0:N0} s ecoulees, epoque 1 en cours..." -f ((Get-Date) - $t0).TotalSeconds)
}
if ($fini1) { docker logs s4-entrainement 2>&1 | ForEach-Object { Log "$_" }; Stop-Erreur "l entrainement s est arrete avant la fin de l epoque 1" }
Log "Epoque 1 terminee apres $([math]::Round(((Get-Date) - $t0).TotalSeconds)) s ; on laisse l'epoque 2 avancer 30 s puis Ctrl+C (SIGINT)"
Start-Sleep -Seconds 30
docker kill --signal=SIGINT s4-entrainement | Out-Null
$tCoupure = Get-Date
docker wait s4-entrainement | Out-Null
Log "COUPURE a $($tCoupure.ToString('HH:mm:ss')) pendant l'epoque 2"
docker logs s4-entrainement 2>&1 | ForEach-Object { "$_" } | Set-Content sorties\entrainement_avant_coupure.txt -Encoding UTF8
Get-Content sorties\entrainement_avant_coupure.txt | ForEach-Object { Log "  | $_" }
Resume 'Mesure 8 - epoque interrompue' 2
Resume 'Mesure 8 - taille de reprise.pt (octets)' $(if (Test-Path sorties\reprise.pt) { (Get-Item sorties\reprise.pt).Length } else { 'ABSENT' })
docker rm s4-entrainement | Out-Null

Log ""; Log "===== Entrainement : relance (reprise) ====="
docker run -d --name s4-entrainement-reprise -e N_NEGATIFS=5000 -v "${W}:/work" $IMG python -u entrainer.py | Out-Null
$tR = Get-Date
docker logs -f s4-entrainement-reprise 2>&1 | ForEach-Object { Write-Host "  | $_" }
$code = docker wait s4-entrainement-reprise
docker logs s4-entrainement-reprise 2>&1 | ForEach-Object { "$_" } | Set-Content sorties\entrainement.txt -Encoding UTF8
Get-Content sorties\entrainement.txt | ForEach-Object { Add-Content -Path $LOG -Value "  | $_" -Encoding UTF8 }
docker rm s4-entrainement-reprise | Out-Null
Resume 'Duree de la relance (s)' ([math]::Round(((Get-Date) - $tR).TotalSeconds))
if ("$code".Trim() -ne '0') { Stop-Erreur "entrainement termine avec le code $code" }

# ---------------------------------------------------------------- 3.5 Verification du paquet
Run 'verifier_s4.py model' { docker run --rm -v "${W}:/work" $IMG python verifier_s4.py model }
$script:OUT | Set-Content captures\verifier_s4.txt -Encoding UTF8
Run 'sha256 de modele.pt et sha256_poids du meta' { (Get-FileHash model\modele.pt -Algorithm SHA256).Hash.ToLower(); Select-String -Path model\modele_meta.json -Pattern 'sha256_poids' | ForEach-Object { $_.Line.Trim() } }
Run 'Paquet' { Get-ChildItem model, sorties | Select-Object FullName, Length | Format-Table -AutoSize | Out-String }
Log ""
Log "TERMINE $(Get-Date -Format s). Previens Claude."
