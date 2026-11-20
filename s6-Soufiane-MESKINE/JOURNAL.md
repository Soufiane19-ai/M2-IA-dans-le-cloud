# Journal — Séance 6 (Soufiane Meskine)

M2 YNOV Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027, 20/11/2026.

## Tableau de décisions

Écrit le **20/11/2026 à 15:17** (heure de Paris), **avant** `preparer.py` et avant tout entraînement. Il n'a pas été modifié après la lecture des résultats.

| Décision | Contrainte | Ma valeur |
|---|---|---|
| Métrique d'arbitrage entre deux approches | calculée par `entrainer_suivi.py` | **`pr_auc`** (précision moyenne sur le test). Elle mesure le classement des malignes devant les bénignes sur tous les seuils, et part de la prévalence (≈ 0,1 %) au lieu de 0,5 : c'est la métrique qui ne se laisse pas flatter par 99,9 % de bénignes (S2, question 2.5). `rappel_au_seuil` est fixé à 0,90 par construction et ne départage rien. |
| Écart minimal pour déclarer une approche meilleure | à confronter au bruit (partie 1.4) | **0,010 de PR-AUC en absolu**, **avec le même signe sur les deux graines**. En S2, le nombre de positifs en test variait de 57 à 110 selon la graine : avec une centaine de positifs, quelques lésions bien ou mal classées déplacent la PR-AUC de plusieurs millièmes. |
| Critère de départage si l'écart est sous le bruit | une grandeur que le run enregistre | **`duree_entrainement_s`, la plus courte** (moyenne des deux graines). À qualité égale, je préfère le modèle le moins coûteux à ré-entraîner et à rejouer. |
| Nom du validateur au registre | une personne, pas un rôle | **Soufiane Meskine** |

**Question 0.1** — Je croirai qu'un écart de PR-AUC entre deux approches est réel s'il dépasse 0,010, **va dans le même sens sur les deux graines**, et dépasse la variation de chaque approche d'une graine à l'autre (le bruit du découpage).
Sinon, c'est une égalité : un écart plus petit que ce que le seul tirage des patients fait varier n'est pas une victoire, et je départage sur la durée.

## Environnement

- La partie 1 a été exécutée dans un **conteneur Linux** (Python 3.12.3, `mlflow==3.18.0`, `pandas==3.0.6`, `scikit-learn==1.9.1`, `joblib==1.6.0` installés dans un `venv`, comme dans l'énoncé).
- Le dossier de travail est monté sur **`/travail`**, comme avec la commande Docker du poste :
  ```
  docker run -it --name s6 -p 5000:5000 -v "$HOME\Desktop\s6-Soufiane-MESKINE:/travail" -w /travail python:3.12-slim bash
  ```
  Les chemins enregistrés par MLflow (`/travail/poste/suivi/artefacts`) sont donc valides dans ce conteneur.
- Seul ajout à l'énoncé : `apt-get install -y zip unzip`. L'image `python:3.12-slim` ne les contient pas et la partie 1.3 en a besoin.
- Données : `train-metadata.csv` repris de S4 (`s4-dermascan/donnees/`, le dossier `s2-…/data/` n'existe plus). Contrôle : `sha256sum` donne `536e8208cfb3502b71ad70160a249c87703669f6004314b6537254fb59a93e7e`, ce qui est conforme.

## Déroulé

| Heure | Étape |
|---|---|
| 15:17 | Tableau de décisions, puis `preparer.py` (manifeste `e3da1f52ff2c`) |
| 15:17 | Blancs complétés, run `reference-g42` |
| 15:17 | Export `export_session.zip` (36 Ko), `session` → `session_fermee`, dézippage dans `poste/`. Métriques lisibles, artefacts absents |
| 15:18 | `importer_suivi.py` : 2 lignes réécrites, artefacts relus |
| 15:18 | Runs `reference-g7`, `variante-g42`, `variante-g7` |
| 15:19 | Promotion v1 (`reference-g42`), puis v2 (`variante-g42`), `verifier_chaine.py` sur le bon fichier (code 0), puis sur le mauvais (code 1) |
| 15:20 | Captures de l'interface MLflow (`captures/`) |
| 15:21 | Contre-épreuve de reproductibilité : `reference-g42` et `variante-g42` relancés dans une copie jetable, résultats identiques à la 4ᵉ décimale (PR-AUC 0,0500 et 0,0834, seuils 0,2864 et 0,0615) |

## Décision de promotion

Appliquée **sans modifier le tableau** (détail dans `MESURES.md`, question 1.4) :
- Les écarts variante − référence sont **+0,0334** (graine 42) et **−0,0185** (graine 7) : signes opposés.
- Le bruit d'une graine à l'autre vaut 0,0154 pour la référence et 0,0365 pour la variante.

Il n'y a donc **pas d'écart réel**. Départage par la durée : la variante prend 3,1 s en moyenne, contre 11,4 s pour la référence. **La variante est promue** en `dermascan-tabulaire` v2 (run `variante-g42`), avec v1 (`reference-g42`) en repli. Validateur : Soufiane Meskine.

La graine 42 a été choisie parce que c'est le découpage de référence (celui de S2 et de v1), **pas** pour son score : le score d'une graine n'est pas une propriété de l'approche.
