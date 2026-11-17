# Séance 5 — Optimiser et surveiller (Soufiane Meskine)

Master 2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. TP réalisé le 17/11/2026, à partir de mon paquet de la séance 4 (`sha256_poids b44771c802585db7…`).

Le ResNet18 de S4 est exporté en ONNX : même calcul, à 3e-6 près, sans aucune décision changée. Une variante int8 a été testée et refusée (39 décisions changées). Le modèle est servi par ONNX Runtime, dans une image Wolfi sans PyTorch (`dermascan-api:2.1.0`) : 419 Mo au lieu de 1,67 Go, **zéro CVE**. L'API journalise chaque inférence au format de S3, avec quatre covariables facultatives. Une dérive provoquée (éclairage polarisé, puis âge) est détectée par un PSI sur fenêtre glissante, en local puis sur Azure, à travers Log Analytics.

| Fichier | Contenu |
|---|---|
| `JOURNAL.md` | Tableau de décisions daté (figé à 15:05, avant toute mesure), questions 0.1 et 0.2 |
| `MESURES.md` | Mesures 1 à 6 et 11, questions 1.1 à 4.7 et 5.7, décision de déploiement (ONNX float32, version 2.1.0) |
| `SURVEILLANCE.md` | Mesures 7 à 10 et 12, questions 5.1 à 5.6 et 6.1 |
| `exporter_onnx.py`, `comparer.py`, `app.py`, `rejouer_flux.py`, `derive.py`, `requetes.kql` | Fichiers distribués, blancs remplis (`entree`, `external_data=False`, proportions et seuil de la requête 3) |
| `api-s5/` | Contexte de construction (`Dockerfile`, `.dockerignore`, `requirements.txt`, `app.py`, `model/modele.onnx`, `model/modele_meta.json`), sans `.pt` |
| `reference_covariables.json`, `sorties/` | Référence, `comparaison_variantes.csv`, `psi_fenetres.csv` (dernier passage : éclairage, local), et les variantes `_age` et `_azure` |
| `journal_local.jsonl`, `journal_local_age.jsonl`, `journal_azure.jsonl` | Journaux bruts, non retouchés |
| `captures/` | Scan Docker Scout, `/model/info` local et en ligne, graphiques des requêtes 2, 3 et 4, rapports Locust, crédit |
| `locust/` | Sorties de Locust des deux paliers sur B1 |
| `logs/` | Journaux des scripts, et archive des logs App Service (IP publique masquée) |
| `scripts/` | Scripts PowerShell de la séance, `Dockerfile.outils`, `analyse_variantes.py`, `outils_s5.py`, fichiers KQL pour la CLI |

Écarts déclarés :
- **Outils** : comme en S4, ils tournent dans un conteneur Linux sur le portable.
- **Rejeu sur Azure** : une coupure Wi-Fi d'environ une heure a fait perdre 245 des 600 appels de dérive. Les 355 restants suffisent à mesurer la détection.
- **Tableau de bord** : l'épinglage est introuvable dans la nouvelle interface Journaux du portail, les captures sont donc celles des graphiques dans l'éditeur.
