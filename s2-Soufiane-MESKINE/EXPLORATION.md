# Séance 2 — Exploration (mesures 1 à 5, questions 0.1 à 1.5)

Soufiane Meskine · M2 YNOV Montpellier · données ISIC 2024 (`train-metadata.csv`) · script : `explorer.py`

## Tableau de décisions

| Décision | Valeur |
|---|---|
| Suffixe personnel, identique à la séance 1 | `sm26` |
| Nom du groupe portant le registre, créé en séance 1 | `rg-dermascan-registre-sm26` |
| Nom du registre ACR de la séance 1 | `acrdermascansm26` (supprimé le 06/10 et recréé en séance 2, voir `MESURES.md`) |
| Rappel visé, décidé avant de voir le moindre résultat | **0,90** |
| Date portée par l'étiquette `a_detruire` | 2027-06-30 |

**Question 0.1** — Si l'on fixe le rappel après avoir vu la courbe, on choisit le point qui flatte le modèle : l'objectif s'ajuste aux résultats au lieu de les juger. C'est un biais de confirmation, du *p-hacking* appliqué au seuil. Le rappel visé est une exigence clinique (combien de cancers on accepte de manquer). Il doit être fixé par le besoin médical et pouvoir être opposé au modèle : si celui-ci ne l'atteint pas à un coût acceptable, on doit pouvoir dire « pas prêt », et non déplacer la cible.

---

## 1.1 — Environnement

### Mesure 1 — versions et volumétrie

| Relevé | Commande | Valeur |
|---|---|---|
| Version de Python | `python3 --version` | 3.12.7 (identique à l'image Docker) |
| Version de scikit-learn | `python3 -c "import sklearn; ..."` | 1.9.1 |
| Version de pandas | `python3 -c "import pandas; ..."` | 3.0.6 |
| Poids du fichier d'annotation | `ls -lh` | 246 Mo (257 543 161 octets, archive Kaggle de 91 Mo) |

Autres versions de l'environnement : numpy 2.5.4, joblib 1.6.0, Flask 3.1.3, gunicorn 26.2.0.

## 1.2 — Volumétrie et structure

Paramètres du script : `low_memory=False`, colonne de regroupement `patient_id`.

### Mesure 2

| Relevé | Valeur |
|---|---|
| Nombre de lignes | 401 059 |
| Nombre de colonnes | 55 |
| Nombre de patients distincts | 1 042 |
| Lésions par patient : minimum / médiane / maximum | 1 / 241 / 9 184 |

Types : 35 colonnes numériques (`float64`/`int64`, dont toutes les mesures `tbp_lv_*`, `age_approx`, `clin_size_long_diam_mm`) et 20 colonnes texte (`isic_id`, `patient_id`, `sex`, `anatom_site_general`, `image_type`, `tbp_tile_type`, `tbp_lv_location`, `tbp_lv_location_simple`, `attribution`, `copyright_license`, `lesion_id`, `iddx_*`, `mel_mitotic_index`). La liste complète est affichée par `explorer.py`.

**Question 1.1** — 401 059 lignes pour 1 042 patients, soit 241 lésions par patient en médiane et jusqu'à 9 184. Une ligne n'est pas indépendante des autres : les lésions d'un même patient partagent sa peau, son phototype, son âge, la cabine et les conditions de prise de vue, et le modèle peut apprendre à reconnaître le patient plutôt que la lésion. La taille réelle de l'échantillon est donc le **nombre de patients** (1 042). C'est lui qui commande le découpage de la partie 2 : on découpe par patient.

## 1.3 — Les colonnes qui trahissent la réponse

Paramètres : 5e colonne suspecte `lesion_id`, cible `target`. Malignes au total : 393.

### Mesure 3

| Colonne | Valeurs renseignées | Dont malignes | Écartée ? |
|---|---|---|---|
| `iddx_1` | 401 059 | 393 | Oui, c'est le diagnostic lui-même (`Benign` / `Malignant` / `Indeterminate`) |
| `iddx_full` | 401 059 | 393 | Oui, diagnostic histologique complet (« Malignant::…::Basal cell carcinoma ») |
| `mel_thick_mm` | 63 | 63 | Oui, épaisseur de Breslow, mesurée seulement sur un mélanome excisé |
| `mel_mitotic_index` | 53 | 53 | Oui, index mitotique, mesuré seulement après analyse histologique |
| `lesion_id` | 22 058 | **393** | Oui : les 393 malignes ont toutes un `lesion_id` (voir question 1.2) |

Les colonnes `iddx_2` à `iddx_5`, sous-niveaux du même diagnostic, sont écartées pour la même raison. Cela fait **9 colonnes de fuite** au total.

**Question 1.2** — `lesion_id` n'est renseigné que pour 22 058 lignes (5,5 %), mais **100 % des 393 malignes** en ont un. Sa seule présence signifie que la lésion a été repérée et suivie par un clinicien (biopsie, suivi), donc déjà suspectée. L'identifiant est attribué **après** la consultation, au moment où la lésion entre dans un parcours de diagnostic, et non au moment de la photographie en cabine. En production, une nouvelle lésion n'en a pas encore : le modèle apprendrait « a un `lesion_id` ⇒ suspect », un signal qui n'existera jamais au moment de la prédiction.

**Question 1.3** — `iddx_1` donne 100 % parce qu'il **est** la réponse : c'est le diagnostic posé par le dermatologue ou l'anatomopathologiste, recopié dans le tableau. Le modèle n'apprend donc rien sur la lésion, il apprend à lire le diagnostic. Le jour où une nouvelle lésion arrive de la cabine, cette colonne est vide, et le modèle ne sait plus rien faire : son score parfait s'effondre.

## 1.4 — Valeurs manquantes et colonnes sans information

Paramètres : `ascending=False`, seuil `<= 1`.

### Mesure 4

| Relevé | Valeur |
|---|---|
| Colonnes avec au moins une valeur manquante, hors fuites | `sex`, `anatom_site_general`, `age_approx` (3 colonnes) |
| Taux de valeurs manquantes | `sex` 2,872 % (11 517) · `anatom_site_general` 1,435 % (5 756) · `age_approx` 0,698 % (2 798) |
| Colonnes constantes (une seule modalité) | `image_type` (= « TBP tile: close-up ») ; `iddx_5` (une seule valeur renseignée, déjà écartée comme fuite) |
| Variables restantes après retrait des fuites, identifiants et constantes | **40** (35 numériques, 5 catégorielles) |

Calcul des 40 : 55 − 1 cible − 9 fuites − 2 identifiants (`isic_id`, `patient_id`) − 2 colonnes administratives (`attribution`, `copyright_license`, qui décrivent l'hôpital et la licence, pas la lésion, et n'existeront pas en cabine) − 1 constante (`image_type`) = 40.

**Question 1.4** — *La retirer* : elle occupe le contrat d'interface pour rien. Chaque appel à `/predict` devrait la fournir, et si un jour la source change (une cabine qui envoie « TBP tile: overview »), le modèle recevrait une valeur jamais vue pour une variable dont il n'a rien appris. *Consigner son existence* : c'est une hypothèse sur le flux de production. On sait que l'entraînement ne contenait que des vignettes rapprochées. Si le flux réel en contient d'autres, la séance 5 (surveillance de dérive) doit pouvoir le détecter, et seule cette trace le permet.

## 1.5 — Distribution de la cible

### Mesure 5

| Relevé | Valeur |
|---|---|
| Lésions `target = 1` | 393 |
| Lésions `target = 0` | 400 666 |
| Taux de positifs | 0,0980 % |
| Rapport « une maligne pour N bénignes » | 1 pour **1 020** |

**Question 1.5** — Le classifieur « toujours bénin » atteint une exactitude de 400 666 / 401 059 = **99,90 %**, sans détecter une seule maligne (rappel 0). Sur une classe aussi rare, l'exactitude mesure surtout la proportion de la classe majoritaire : elle est inutilisable comme critère de choix. Il faut des métriques centrées sur la classe rare : rappel, précision, PR-AUC.
