# Décisions du projet (brouillon, écrit le 20/11/2026 avant toute mesure)

## Tableau de décisions (sujet pressenti : ISIC approfondi)

| Décision | Valeur | Pourquoi |
|---|---|---|
| Métrique d'arbitrage | **PR-AUC** sur les patients de test (complétée par la pAUC au-dessus de 80 % de rappel, la métrique officielle d'ISIC 2024, rapportée sans arbitrer) | Prévalence ≈ 0,1 % : la ROC-AUC et l'exactitude flattent ; la PR-AUC part de la prévalence |
| Seuil d'acceptation | Une approche bat la référence si l'écart de PR-AUC est **≥ 0,010**, **de même signe sur au moins 3 graines** (42, 7, 2026), et supérieur à la variation de la référence entre graines ; seuil de décision fixé pour un **rappel de 0,90** | Séance 6 : sur 2 graines, l'écart a changé de signe (+0,033 puis −0,019) |
| Découpage | `GroupShuffleSplit` par **`patient_id`**, 25 % des patients en test, graines 42, 7 et 2026 ; validation externe par **institution** (`attribution`) en complément | Les lésions d'un même patient se ressemblent ; un découpage ligne à ligne mesurerait la reconnaissance du patient |
| Approche de référence | Régression logistique tabulaire équilibrée (`reference` de la séance 6) : PR-AUC 0,050 à 0,065 selon la graine | Simple, rapide, reproductible : c'est elle qu'il faut battre |

## 3.1 — Sujets et découpages

> Le sujet du projet n'était pas joint à la séance. DEEP-VOICE et Eedi sont décrits d'après les jeux publics de même nom, **à vérifier** avec le sujet.

| Sujet | Unité de découpage | Pourquoi un découpage ligne à ligne mentirait | Approche de référence à battre | Piège structurel |
|---|---|---|---|---|
| ISIC approfondi | **Patient** (`patient_id`), et **institution** pour une validation externe | Un patient porte jusqu'à des milliers de lésions qui partagent peau, âge, cabine et éclairage. Avec ses lésions des deux côtés, le modèle reconnaît le patient et non la malignité | Régression logistique tabulaire (PR-AUC ≈ 0,05), puis le ResNet18 de S4 (PR-AUC 0,48 en validation croisée par patient) | Prévalence ≈ 0,1 % (393 positifs) concentrée chez peu de patients, donc métrique instable d'une graine à l'autre. Dérive d'institution et d'éclairage (`tbp_tile_type`) |
| DEEP-VOICE | **Locuteur** (et enregistrement source) | Les fenêtres d'une seconde d'un même enregistrement sont presque identiques. La voix fausse est une conversion d'un enregistrement vrai du même locuteur. Le modèle reconnaît le clip ou la personne | Régression logistique ou gradient boosting sur les caractéristiques acoustiques fournies (MFCC, spectre), évalués en « un locuteur laissé de côté » | Seulement 8 locuteurs, donc très peu de groupes et une variance énorme. L'étiquette est confondue avec un seul outil de conversion (RVC) : un détecteur qui ne généralise pas à d'autres générateurs |
| Eedi | **Question** (`QuestionId`), et misconceptions jamais vues | Les 3 mauvaises réponses d'une question partagent l'énoncé et la notion. Une même question des deux côtés donne la réponse | Recherche par similarité de texte (TF-IDF ou plongements) entre question, mauvaise réponse et intitulés de misconceptions, mesurée en MAP@25 | Longue traîne : beaucoup de misconceptions apparaissent 0 ou 1 fois, et le test en contient que l'entraînement n'a jamais vues. Étiquettes bruitées |

**Question 3.1 (ISIC approfondi)** — Notre métrique répond à : « Chez un **patient que le modèle n'a jamais vu**, les lésions malignes remontent-elles en tête de la liste des alertes ? »

## Questions 3.2 et 3.3

**Question 3.2** — Versionner `suivi/mlflow.db` ferait perdre la fusion : c'est un binaire qu'on ne peut pas fusionner entre membres. Il contient des chemins absolus propres à un poste, et il ferait entrer les artefacts et modèles dans l'historique. Ne pas le versionner fait perdre la preuve si le seul poste qui le porte disparaît.
**Choix : `suivi/` reste hors de Git.** Chaque livraison publie une archive datée du suivi (base et artefacts), avec son sha256 noté ici, dans un stockage privé du groupe (conteneur Azure Blob privé ou Drive du groupe). Un membre désigné la réimporte avec `importer_suivi.py`.

**Question 3.3** — Les plus chères à changer au jour 9 sont **l'unité de découpage** et **la métrique d'arbitrage**. En changer invalide tous les runs et toutes les comparaisons faits depuis, et oblige à ré-entraîner et à re-promouvoir.
Vient ensuite le **seuil d'acceptation**, rappel visé compris : le changer après avoir vu les résultats, c'est exactement le biais que le tableau doit empêcher.
L'approche de référence, elle, peut être enrichie sans tout refaire, à condition de garder l'ancienne dans la comparaison.
