# Séance 6 — Suivre, gouverner, préparer (Soufiane Meskine)

M2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. TP du 20/11/2026, sans réseau ni Azure pour la partie 1.

Le modèle tabulaire de S2 a été rejoué en **4 runs MLflow** (2 approches × 2 graines), écrits dans une base SQLite locale qui voyage avec le paquet. Le suivi a été exporté, cassé puis réparé par `importer_suivi.py`, et la comparaison a été arbitrée par un tableau de décisions écrit avant le premier entraînement.

La variante (gradient boosting) a été promue en `dermascan-tabulaire` **v2**, avec v1 en repli et un validateur nommé. `verifier_chaine.py` prouve que le fichier servi est bien celui-là (code 0), et refuse l'autre fichier (code 1).

| Fichier ou dossier | Contenu |
|---|---|
| `JOURNAL.md` | Tableau de décisions (15:17, avant tout entraînement), Q0.1, environnement, déroulé, décision de promotion |
| `MESURES.md` | Mesures 1 à 6, questions 1.1 à 1.5 |
| `GOUVERNANCE.md` | Tableau AI Act (2.1), tableau RGPD (2.2), chaîne de traçabilité (2.3), questions 2.1 à 2.5 |
| `poste/` | Le « poste » de la partie 1.3 : `suivi/` (base `mlflow.db` et artefacts des 4 runs, registre v1/v2), `model/`, `donnees/` (manifeste et découpages), scripts avec les blancs complétés. `data/train-metadata.csv` (246 Mo) est exclu, à recopier depuis `s4-dermascan/donnees/` |
| `depot-groupe/` | Brouillon de la partie 3 : `.gitignore`, `README.md`, `DECISIONS.md` (tableau 3.1 et questions 3.1 à 3.3), à pousser dans le dépôt **privé** du groupe |
| `captures/` | Interface MLflow : les 4 runs, la vue Compare, un run avant et après l'import, ses artefacts, le registre |
| `logs/` | Sorties brutes de chaque commande, `export_session.zip` (l'export de la « session Colab »), historique Git du dépôt de groupe |
| `fichiers-seance-originaux/` | Les 5 scripts distribués, avec leurs blancs, pour comparaison |

## Chiffres clés

| | reference-g42 | reference-g7 | variante-g42 | variante-g7 |
|---|---|---|---|---|
| PR-AUC | 0,0500 | 0,0654 | 0,0834 | 0,0469 |
| Précision à rappel 0,90 | 0,0041 | 0,0060 | 0,0051 | 0,0052 |
| Durée d'entraînement | 11,9 s | 10,9 s | 3,5 s | 2,7 s |

- Écarts variante − référence : **+0,0334** (graine 42) et **−0,0185** (graine 7). Ils sont de signes opposés, donc il n'y a pas d'écart réel. Départage sur la durée : variante promue.
- Manifeste `e3da1f52ff2c`. Données `536e8208…`. Commit `hors-git` : c'est le maillon que répare le dépôt de la partie 3.

## Rouvrir le suivi sur le poste

Les chemins d'artefacts enregistrés sont ceux du conteneur de travail (`/travail/poste/suivi/artefacts`). Avec le dossier monté sur `/travail`, l'interface s'ouvre sans réimport :

```
docker run -it --rm -p 5000:5000 -v "$HOME\Desktop\s6-Soufiane-MESKINE:/travail" -w /travail/poste python:3.12-slim bash
pip install mlflow==3.18.0 pandas==3.0.6 scikit-learn==1.9.1 joblib==1.6.0
mlflow ui --backend-store-uri sqlite:///suivi/mlflow.db --port 5000 --host 0.0.0.0
```

Monté ailleurs, il suffit de lancer `python importer_suivi.py` d'abord : c'est exactement la situation de la question 1.3 (c).
