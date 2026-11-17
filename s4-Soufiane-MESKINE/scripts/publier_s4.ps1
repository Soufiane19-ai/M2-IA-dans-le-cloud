# Publie le dossier s4-Soufiane-MESKINE sur GitHub (Soufiane19-ai/M2-IA-dans-le-cloud) avec git.
# modele.pt (44,8 Mo) depasse la limite de 25 Mo du depot par le navigateur : on passe par git.
# powershell -ExecutionPolicy Bypass -File .\publier_s4.ps1
Set-Location $PSScriptRoot
$SRC = Join-Path $env:USERPROFILE 'Desktop\s4-Soufiane-MESKINE'
$TMP = Join-Path $env:TEMP 'publication-m2-ia'
if (Test-Path $TMP) { Remove-Item -Recurse -Force $TMP }
git clone --depth 1 https://github.com/Soufiane19-ai/M2-IA-dans-le-cloud.git $TMP
if ($LASTEXITCODE -ne 0) { Read-Host "Clonage impossible : envoie une capture a Claude. Entree pour fermer"; exit 1 }
Copy-Item -Recurse -Force $SRC (Join-Path $TMP 's4-Soufiane-MESKINE')
Set-Location $TMP
git config user.name "Soufiane Meskine"
git config user.email "soufiane.meskine@ynov.com"
git add s4-Soufiane-MESKINE
git status --short | Select-Object -First 80
git commit -m "TP S4 : CNN sur les vignettes, image 2.0.0, deploiement B1"
git push origin HEAD:main
if ($LASTEXITCODE -ne 0) { Read-Host "Push refuse : envoie une capture a Claude. Entree pour fermer"; exit 1 }
git log --oneline -1
Write-Host "TERMINE : publie sur GitHub."
