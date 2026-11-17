# Séance 4 — Modèle lourd : un CNN sur les vignettes (Soufiane Meskine)

Master 2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. TP réalisé le 17/11/2026.

Un ResNet18 pré-entraîné (ImageNet) a été ajusté sur les vignettes de l'archive ISIC 2024 SLICE-3D Permissive (CC-BY 4.0) : 294 malignes et 5 000 bénignes, découpées par patient. Ses probabilités sont ensuite recalées à la prévalence réelle (0,135 %). Le réseau est servi par l'API de S2, dont seul le modèle change (`dermascan-api:2.0.0`) : l'image est publiée dans le registre conservé depuis S1, déployée sur App Service B1, chargée par Locust, puis le groupe de la séance est détruit.

**Repli déclaré (annexe B)** : entraînement **local, sans GPU, en mode dégradé** (`N_NEGATIFS=5000`), dans un conteneur Linux sur le portable (`Dockerfile.entrainement`), le code distribué étant exécuté sans modification. Le notebook `entrainer_colab.ipynb` est fourni tel que distribué, **sans sorties** : il n'a pas été exécuté.

| Fichier | Contenu |
|---|---|
| `JOURNAL.md` | Décisions, mesures 1 à 10, questions 0.1 à 3.6 |
| `MESURES.md` | Mesures 11 à 19 et 21, questions 4.1 à 5.6 et 7.1 |
| `MODEL_CARD.md` | Model card de S2 complétée pour 2.0.0, mesure 20, questions 6.1 à 6.3 |
| `donnees.py`, `entrainer.py`, `verifier_s4.py`, `entrainer_colab.ipynb`, `requirements-entrainement.txt` | Code distribué, exécuté tel quel |
| `Dockerfile.entrainement` | Environnement Linux d'entraînement (Python 3.12.7, torch 2.14.1+cpu) |
| `analyses_s4.py`, `analyse_partie4.py` | Mes calculs : mesures 3, 4, 5, 20, question 3.1 ; partie 4 |
| `model/` | Paquet complet : `modele.pt` (44,8 Mo, sha256 `b44771c802585db7…`), `modele_meta.json`, `manifeste_echantillon.csv` |
| `sorties/` | `historique.csv`, `predictions_validation.csv`, sorties console de l'entraînement (avant et après la coupure) |
| `api-s4/` | `Dockerfile` et `.dockerignore` de S2 adaptés, `app.py`, `requirements.txt` |
| `locustfile_s4.py`, `palier_s4_*` | Scénario et sorties brutes de Locust |
| `captures/` | `verifier_s4.py` (13/13), `docker scout cves`, `/predict` local et public, `/model/info` local et public, crédit |
| `logs/` | Journaux des scripts, `analyses_s4.json`, archive des logs App Service (IP publique du poste masquée) |
| `scripts/` | Scripts PowerShell qui ont exécuté la séance |

Résultats clés :
- **PR-AUC 0,48** en validation, mais **0,044** une fois ramenée à la prévalence réelle, contre 0,055 pour le modèle tabulaire de S2 : pas de supériorité démontrée.
- Environ **206 lésions examinées par maligne trouvée** au rappel de 0,90.
- L'image de **1,67 Go** démarre sans réseau, et sert la même probabilité que l'entraînement à 10⁻⁶ près.
- Une **exception CVE est écrite** : les failles viennent toutes de la base Debian de S2.
- Sur B1, le **CPU sature dès 10 utilisateurs** (p50 1,4 s contre 83 ms en S3) : l'engagement de S3 ne tient plus.
