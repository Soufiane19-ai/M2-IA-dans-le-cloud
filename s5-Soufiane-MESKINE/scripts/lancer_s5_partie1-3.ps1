# Seance 5 - parties 1 a 3 et reference (5.1) : paquet S4, export ONNX, quantization, comparaison.
# powershell -ExecutionPolicy Bypass -File .\lancer_s5_partie1-3.ps1
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs, captures, sorties, model, env-outils | Out-Null
$LOG = Join-Path $PSScriptRoot 'logs\sortie_s5_partie1-3.log'
Set-Content -Path $LOG -Value "TP S5 parties 1-3 - debut $(Get-Date -Format s)" -Encoding UTF8
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
function Stop-Erreur([string]$msg) { Log "ARRET : $msg"; Read-Host "Envoie une capture a Claude. Entree pour fermer"; exit 1 }

$W = $PSScriptRoot
$S4 = Join-Path (Split-Path $W -Parent) 's4-dermascan'
$DON = Join-Path $S4 'donnees'
$IMG = 'dermascan-outils:s5'
function Py([string]$cmd) { docker run --rm -v "${W}:/work" -v "${DON}:/work/donnees" $IMG sh -c $cmd }

# ---------------------------------------------------------------- 1.1 Paquet S4
Copy-Item "$S4\model\modele.pt", "$S4\model\modele_meta.json", "$S4\model\manifeste_echantillon.csv" model\ -Force
Run 'sha256 modele.pt / sha256_poids du meta' { (Get-FileHash model\modele.pt -Algorithm SHA256).Hash.ToLower(); (Get-Content model\modele_meta.json -Raw | ConvertFrom-Json).sha256_poids }
Copy-Item Dockerfile.outils env-outils\Dockerfile -Force
Run 'Image d outils (torch + onnx + onnxruntime)' { docker build -t $IMG env-outils }
if ($CODE -ne 0) { Stop-Erreur "construction de $IMG impossible" }
Run 'Versions' { Py 'python outils_s5.py versions' }
if (-not (Test-Path "$DON\train-metadata.csv")) {
    Run 'Extraction de train-metadata.csv (rejouer_flux.py et derive.py le lisent en clair)' { Py 'python outils_s5.py extraire_meta' }
}

# ---------------------------------------------------------------- 2. Export ONNX (deux fois : empreinte stable ?)
Run 'Export ONNX (1er)' { Py "QUANTIFIER=0 python exporter_onnx.py model" }
if ($CODE -ne 0) { Stop-Erreur "export ONNX en echec" }
$h1 = (Get-FileHash model\modele.onnx -Algorithm SHA256).Hash.ToLower()
Run 'Export ONNX (2e)' { Py "QUANTIFIER=0 python exporter_onnx.py model" }
$h2 = (Get-FileHash model\modele.onnx -Algorithm SHA256).Hash.ToLower()
Log "[RESUME] Mesure 2 - empreinte 1er export = $h1"
Log "[RESUME] Mesure 2 - empreinte 2e export  = $h2"
Run 'ls model' { Get-ChildItem model | Select-Object Name, Length | Format-Table -AutoSize | Out-String }

# ---------------------------------------------------------------- 3. Quantization puis comparaison
Run 'Export + quantization int8' { Py "python exporter_onnx.py model" }
if ($CODE -ne 0) { Stop-Erreur "quantization en echec" }
Run 'sha256 des trois fichiers' { Get-ChildItem model -Filter 'modele*' | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $_.Path -Leaf)" } }
Run 'comparer.py (1 fil, 20 + 300 appels, 1 058 vignettes)' { Py "python comparer.py model" }
if ($CODE -ne 0) { Stop-Erreur "comparer.py en echec" }
$script:OUT | Set-Content captures\comparer.txt -Encoding UTF8
Run 'Mesure 4 - ce que l int8 change' { Py "python analyse_variantes.py" }

# ---------------------------------------------------------------- 5.1 Reference
Run 'Reference des covariables (jeu d entrainement de S4)' { Py "python derive.py reference model/manifeste_echantillon.csv donnees/train-metadata.csv > reference_covariables.json && cat reference_covariables.json" }
Log ""
Log "TERMINE $(Get-Date -Format s). Previens Claude."
