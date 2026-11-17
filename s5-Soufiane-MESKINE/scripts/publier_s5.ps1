# Publie le dossier s5-Soufiane-MESKINE sur GitHub (Soufiane19-ai/M2-IA-dans-le-cloud) avec git.
# modele.onnx (44,8 Mo) depasse la limite de 25 Mo du navigateur : on passe par git.
# powershell -ExecutionPolicy Bypass -File .\publier_s5.ps1
Set-Location $PSScriptRoot
$SRC = Join-Path $env:USERPROFILE 'Desktop\s5-Soufiane-MESKINE'
$TMP = Join-Path $env:TEMP 'publication-m2-ia'
if (Test-Path $TMP) { Remove-Item -Recurse -Force $TMP }
git clone --depth 1 https://github.com/Soufiane19-ai/M2-IA-dans-le-cloud.git $TMP
if ($LASTEXITCODE -ne 0) { Read-Host "Clonage impossible : envoie une capture a Claude. Entree pour fermer"; exit 1 }
Copy-Item -Recurse -Force $SRC (Join-Path $TMP 's5-Soufiane-MESKINE')
Set-Location $TMP
git config user.name "Soufiane Meskine"
git config user.email "soufiane.meskine@ynov.com"
git add s5-Soufiane-MESKINE
git status --short | Select-Object -First 80
git commit -m "TP S5 : ONNX, image 2.1.0 sans PyTorch, journal et derive"
git push origin HEAD:main
if ($LASTEXITCODE -ne 0) { Read-Host "Push refuse : envoie une capture a Claude. Entree pour fermer"; exit 1 }
git log --oneline -1
Write-Host "TERMINE : publie sur GitHub."
