# Journal — Séance 4, modèle lourd (deep learning)

Soufiane Meskine, M2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. Séance réalisée le 17/11/2026 (heure de Paris).

> **Repli déclaré (annexe B).** L'entraînement n'a pas tourné sur Colab mais **sur mon poste, sans GPU, en mode dégradé** (`N_NEGATIFS=5000`). Motif : se connecter à Colab demande une connexion interactive à mon compte Google (et l'autorisation du montage Drive), que la séance, préparée et lancée par scripts, n'a pas pu faire. Comme `entrainer.py` importe le module Unix `resource`, il ne s'exécute pas sous Windows : je l'ai lancé dans un **conteneur Linux** (`python:3.12.7-slim-bookworm`, torch 2.14.1+cpu, `Dockerfile.entrainement`), sur le CPU du portable (Intel Core i7-10510U, 4 cœurs / 8 fils, 4 fils utilisés par PyTorch). Le code distribué est exécuté **sans aucune modification**.
>
> **Autre écart.** L'adresse de l'archive donnée par l'énoncé (`isic-challenge-data.s3.amazonaws.com/2024/…`) renvoie désormais une page HTML de 428 octets, « This file has moved ». J'ai téléchargé les mêmes fichiers depuis `https://isic-archive.s3.amazonaws.com/challenges/2024/`. La taille obtenue est bien celle qu'attend l'annexe A : 653 107 434 octets.

## Tableau de décisions (rempli avant la partie 1)

| Décision | Contrainte | Ma valeur |
|---|---|---|
| Nombre de négatifs tirés (`N_NEGATIFS`) | sans GPU : le mode dégradé | **5 000** |
| Graine de l'échantillonnage et du découpage | celle du code distribué | **42** (`donnees.GRAINE`) |
| Taille d'entrée du réseau | lue dans `donnees.py` | **128** px de côté (`TAILLE`) |
| Architecture | lue dans `entrainer.py` | **ResNet18** pré-entraîné ImageNet (`IMAGENET1K_V1`), tête remplacée par `Linear(512, 1)` : un logit |
| Époques backbone gelé / époques `layer4` dégelé | lues dans `entrainer.py` | **4 / 4** |
| Taux d'apprentissage phase gelée / dégelée | lus dans `entrainer.py` | **1e-3 / 1e-4** (AdamW, `weight_decay` 1e-4) |
| Taille de lot | lue dans `entrainer.py` | **64** |
| Part de validation | exprimée en plis | **1 pli sur 5** (`StratifiedGroupKFold(5)` par patient, pli 0), soit environ 20 % |
| Rappel visé pour le seuil de décision | à justifier par rapport à S2 | **0,90**, le même qu'en S2 : on compare deux modèles à exigence clinique égale (9 malignes sur 10 signalées) |
| Métrique de sélection de l'époque retenue | lue dans `entrainer.py` | **PR-AUC de validation** |
| Tag de l'image de la séance | version sémantique, comparée à S2 | **`2.0.0`** : version **majeure**, car le contrat d'entrée change de façon incompatible (40 variables en JSON en 1.0.0, une image en multipart en 2.0.0) |
| Groupe de ressources de la séance | préfixé `rg-dermascan-s4-` | **`rg-dermascan-s4-sm26`** |
| Registre ACR | celui de S1, jamais détruit | **`acrdermascansm26`** (groupe `rg-dermascan-registre-sm26`) |

**Question 0.1**
- **Ce que la graine garantit** : le même **échantillon** (`DataFrame.sample(random_state=42)`) et le même **découpage** (`StratifiedGroupKFold(random_state=42)`), donc le même manifeste, à l'octet près, d'une machine à l'autre. Elle garantit aussi la même initialisation de la tête (`torch.manual_seed`) et le même **ordre des lots et tirages d'augmentation** (un `torch.Generator` CPU semé à 42), pour une même version de PyTorch.
- **Ce qu'elle ne garantit pas** : les **poids finaux**. Sur GPU, les convolutions cuDNN choisissent des algorithmes non déterministes, et les sommes en virgule flottante ne s'additionnent pas dans le même ordre que sur un CPU à 4 fils ; ces écarts de 1e-7 s'amplifient sur des milliers de pas de gradient. Les métriques, le seuil et la probabilité de contrôle divergent donc.
- **Et dans ce TP, plus encore** : sur Colab avec GPU, le notebook fixe `N_NEGATIFS=20000`, contre 5 000 sans GPU. Les deux apprenants n'ont donc même pas le même échantillon, ni le même manifeste.

**Question 0.2** — Parce qu'avec 94 % de bénins en validation, l'exactitude récompense le modèle qui dit « bénin » : l'époque la plus « exacte » peut être celle qui détecte le moins de malignes, alors que la PR-AUC ne mesure que la façon dont les malignes sont classées en tête. Vérifié en 1.3 : le modèle constant « bénin » obtient déjà **94,42 %** d'exactitude sur la validation.

## Partie 1 — Données

Archive : `ISIC_2024_Permissive_Training_Input.zip` (653 107 434 octets, empreinte `9797a9292b605790…`), vérité terrain `ISIC_2024_Permissive_Training_GroundTruth.csv` (`d09075274e66e6b5…`), `train-metadata.csv.zip` de S2 (`52a14f322e0142d3…`), téléchargés en 356 s.

Le texte d'`ATTRIBUTION.txt`, lu dans le zip sans l'extraire, est recopié dans `MODEL_CARD.md`.

### Mesure 1 — l'archive et l'échantillon

| Relevé | Ma valeur |
|---|---|
| Vignettes dans l'archive Permissive | **217 477** |
| Positifs (malins) dans l'archive, et prévalence | **294**, soit **0,135 %** (217 183 négatifs) |
| Patients distincts dans l'archive | **634** |
| Vignettes de l'échantillon : positifs + négatifs | **5 294** = 294 + 5 000 |
| Prévalence de l'échantillon | **5,55 %** |
| Taille du tableau en mémoire (forme, type, Mo) | `(5294, 128, 128, 3)`, `uint8`, **260 Mo** |
| Taille d'origine des vignettes : médiane, min, max | **127 px**, min 87, max 215 (500 premières vignettes) |
| Durée de `python donnees.py`, premier puis second lancement | **22,2 s** puis **15,5 s** (avec le cache `.npy`). Ces deux durées incluent le démarrage du conteneur et la relecture du `train-metadata.csv.zip` de 93 Mo, qui dominent ; la lecture des 5 294 vignettes dans le zip n'ajoute que quelques secondes |

### Mesure 2 — ligne d'échantillonnage

| Effectif | Graine | Méthode | Prévalence d'entraînement | Empreinte du manifeste (16 premiers caractères) |
|---|---|---|---|---|
| 5 294 (294 positifs + 5 000 négatifs) | 42 | tous les positifs + négatifs tirés uniformément sans remise (`pandas.sample`), puis `StratifiedGroupKFold(5)` par patient, pli 0 en validation | 5,55 % (échantillon) | `64d2e25ddd474269` |

**Question 1.1**
1. **Recalibration** : la correction de la partie 4 est ln β, avec β = négatifs tirés / négatifs de l'archive. Avec un effectif fixe, β est un nombre exact, écrit dans le meta (5 000 / 217 183) et rejouable, et la prévalence d'entraînement (5,55 %) est fixée par construction, quel que soit l'état de l'archive.
2. **Reproductibilité** : si l'archive est mise à jour (nouvelles vignettes bénignes), « 20 % des bénignes » donnerait un autre effectif, donc un autre échantillon, une autre prévalence et un autre β, alors que le code n'a pas changé. Avec un effectif fixe, la taille, le coût d'entraînement et la prévalence restent constants ; le manifeste et son empreinte disent ensuite exactement quelles vignettes ont servi.

**Question 1.2** — Près de la moitié des images de `train-image.hdf5` sont sous licence **non commerciale** (CC-BY-NC). DermaScan est une entreprise qui compte **vendre** un service fondé sur ce modèle : entraîner sur ces images, puis l'exploiter commercialement, violerait la licence. La partie Permissive est en **CC-BY 4.0**, donc libre d'usage commercial, à la seule condition de citer la source (texte d'attribution dans la model card).

### Mesure 3 — exactitude du modèle constant « bénin »

| Population | Calcul | Exactitude |
|---|---|---|
| Flux réel (l'archive entière) | 217 183 / 217 477 | **99,865 %** |
| Échantillon d'entraînement | 5 000 / 5 294 | **94,45 %** |
| Jeu de validation | 999 / 1 058 | **94,42 %** |

**Question 1.3** — Ce qui fait bouger le plancher, c'est la **prévalence** : le modèle constant a une exactitude égale à la part de bénins, 99,87 % dans le flux contre 94,4 % dans l'échantillon, où l'on a gardé tous les positifs et seulement 2,3 % des négatifs. Toute métrique qui dépend de la proportion des classes (exactitude, précision, PR-AUC, lésions examinées par maligne) change de valeur quand on passe de l'échantillon au flux, **même si le modèle reste identique**. On ne peut donc comparer une métrique de l'échantillon à la même métrique du flux qu'après l'avoir ramenée à la même prévalence (partie 4.4).

## Partie 2 — Découpage et prétraitement

Expérience de fuite, écrite à la main (`analyses_s4.py`) : relecture du manifeste, `train_test_split(m, test_size=0.2, stratify=m.cible, random_state=42)`, puis comptage des patients présents des deux côtés.

### Mesure 4 — patients communs aux deux jeux

| Découpage | Vignettes en validation | Positifs en validation | Patients en validation | Patients communs |
|---|---|---|---|---|
| `decouper()` (par patient) | 1 058 | 59 | 109 | **0** |
| `train_test_split` ligne à ligne | 1 059 | 59 | 394 | **384** |

Avec un découpage ligne à ligne, 384 des 394 patients de validation ont aussi des lésions à l'entraînement.

**Question 2.1** — Un patient porte en moyenne **343 lésions** dans l'archive (médiane 228), prises par le même appareil, sous le même éclairage, sur la même peau. Découpé ligne à ligne, le réseau apprendrait à reconnaître **le patient** (teinte de peau, grain, éclairage de la cabine) plutôt que la lésion ; et comme les malignes se concentrent chez quelques patients, il apprendrait « ce patient-là a des malignes ». En validation, il retrouverait des lésions sœurs de celles qu'il a vues : la PR-AUC serait **surestimée** (trop optimiste), et s'effondrerait sur de nouveaux patients.

**Question 2.2** — Avec 294 positifs concentrés chez peu de patients, un `GroupShuffleSplit` tire des patients sans regarder la cible : le nombre de positifs en validation varie fortement d'un tirage à l'autre. En S2, il allait de **57 à 110** selon la graine. `StratifiedGroupKFold` respecte les groupes **et** équilibre la cible entre les plis : 59 positifs en validation, soit 20 % des 294, comme voulu.

### Mesure 5 — le lot d'entrée (`D.vers_tenseur(x[:64])`)

| Relevé | Ma valeur |
|---|---|
| Forme | `(64, 3, 128, 128)` |
| Type | `torch.float32` |
| Minimum et maximum | **−2,118** et **2,249** |
| Moyenne et écart-type | **0,531** et **0,648** (par canal : R 0,968, V 0,380, B 0,245) |

**Question 2.3** — Les poids pré-entraînés ont appris sur des images ImageNet normalisées avec ces statistiques : la première couche attend cette échelle. Les garder, c'est présenter au réseau des entrées dans le domaine numérique que ses filtres connaissent. La moyenne relevée n'est **pas** proche de 0 (0,53), surtout dans le rouge (+0,97 écart-type) : les vignettes sont nettement **plus claires et plus rouges** que la photo ImageNet moyenne. Ce sont des gros plans de peau, roses à brun, sans ciel ni végétation.

**Question 2.4** — Facteur de coût : (224 / 128)² = **3,06** fois plus de calcul par image, et par époque. L'agrandissement n'apporterait **aucune information** : les vignettes d'origine font 127 px de médiane, les passer en 224 revient à interpoler des pixels qui n'existent pas. Le seul bénéfice possible serait d'aligner l'échelle des motifs sur celle du pré-entraînement, ce qui ne justifie pas trois fois plus de calcul sur un CPU.

**Question 2.5** — Une lésion cutanée n'a **pas d'orientation canonique** : la cabine la photographie dans n'importe quel sens, et un grain de beauté tourné d'un quart de tour reste le même grain de beauté. Pour un chiffre manuscrit, l'orientation porte le sens (6 et 9, ou 2 et 5 retournés). Un `ColorJitter` serait une faute, car il détruirait le critère **C (Couleur)** de la règle ABCDE : la présence de plusieurs teintes, ou d'une couleur anormale, est un signe de malignité que l'augmentation brouillerait.

**Question 2.6** — La validation doit mesurer le modèle sur des images telles qu'il les recevra en service, de façon déterministe, pour que les époques soient comparables entre elles.

## Partie 3 — Entraînement (poste, mode dégradé)

**Question 3.1** — Comptage par `sum(p.numel() for p in reseau.parameters() if p.requires_grad)`.

| Phase | Couches qui apprennent | Paramètres entraînables | Part du total |
|---|---|---|---|
| Tête seule | `fc` | **513** | **0,005 %** |
| Dégel | `fc` + `layer4` | **8 394 241** | **75,1 %** |
| Total du réseau | — | **11 177 025** | 100 % |

**Question 3.2** — `requires_grad = False` arrête le **gradient** des poids, mais les couches **BatchNorm** ont aussi des tampons (`running_mean`, `running_var`) qui ne sont pas des paramètres. En mode `train()`, chaque passage avant les met à jour avec les statistiques du lot, gradient ou pas. Sans `mode_entrainement()`, qui remet tout le réseau en `eval()` puis seulement les blocs actifs en `train()`, les statistiques ImageNet du backbone « gelé » dériveraient vers celles des vignettes, sans aucun message d'erreur, et le réseau servi ne serait plus celui qu'on croit. Le vérificateur le contrôle en comparant les 122 tenseurs du backbone, tampons de BatchNorm compris, à ceux d'ImageNet : **OK**.

### Mesure 6 — conditions de l'entraînement

| Relevé | Ma valeur |
|---|---|
| Où | **Poste, sans GPU** : conteneur Linux sous Docker Desktop (Windows), Intel Core i7-10510U, 4 cœurs / 8 fils, PyTorch sur 4 fils |
| `N_NEGATIFS` effectivement utilisé | **5 000** |
| Vignettes d'entraînement et de validation (positifs) | 4 236 (235 positifs) et 1 058 (59 positifs) |
| Durée de chargement des données | **8,2 s** (8,9 s à la relance), cache `.npy` présent |

### Mesure 7 — la courbe d'entraînement (`sorties/historique.csv`)

| Époque | Phase | Durée (s) | Perte d'entraînement | PR-AUC | ROC-AUC | pAUC (rappel > 80 %) |
|---|---|---|---|---|---|---|
| 1 | tête | 75,6 | 0,2669 | 0,1541 | 0,5297 | 0,0116 |
| 2 | tête | 102,1 | 0,1941 | 0,2959 | 0,7922 | 0,0694 |
| 3 | tête | 69,9 | 0,1765 | 0,3329 | 0,8318 | 0,0883 |
| 4 | tête | 69,8 | 0,1716 | 0,3681 | 0,8568 | 0,1042 |
| 5 | dégel | 104,7 | 0,1806 | 0,4486 | 0,8783 | 0,1069 |
| 6 | dégel | 97,8 | 0,1276 | 0,3656 | 0,8179 | 0,0796 |
| 7 | dégel | 94,3 | 0,1071 | 0,4642 | 0,8847 | 0,1106 |
| 8 | dégel | 103,2 | 0,0891 | **0,4799** | 0,8993 | 0,1232 |

Époque retenue : **8** (meilleure PR-AUC). Durée totale enregistrée dans le meta : 660 s (relance seule) ; durée moyenne d'époque : 89,7 s ; pic de mémoire vive : 2 080 Mo. L'époque 2 (102 s) a été recalculée entièrement après la coupure.

**Question 3.3** — Oui, à l'**époque 6** : la perte d'entraînement baisse franchement (0,181 → 0,128), et la PR-AUC de validation recule de 0,449 à 0,366 (ROC-AUC 0,878 → 0,818), avant de remonter aux époques 7 et 8. Deux explications :
1. **Seulement 59 positifs en validation** : la PR-AUC est très bruitée, et le recul de quelques malignes dans le classement suffit à la faire chuter de huit points.
2. **Le dégel** : à l'époque 5, 8,4 millions de paramètres de `layer4` se mettent à apprendre, avec un nouvel optimiseur. Le réseau commence à ajuster les vignettes d'entraînement (sur-apprentissage passager) avant de se stabiliser avec un taux d'apprentissage dix fois plus faible.

La sélection sur la meilleure époque protège le modèle livré : si l'entraînement s'était arrêté à l'époque 6, c'est l'état de l'époque 5 qui aurait été livré, pas celui de la dernière époque.

### Mesure 8 — reprise après coupure

| Relevé | Ma valeur |
|---|---|
| Époque pendant laquelle j'ai interrompu | **2** : SIGINT (équivalent de Ctrl+C), envoyé à 12:02:41, 30 s après la fin de l'époque 1 |
| Ligne affichée au redémarrage | `reprise a l'epoque 2` |
| Époques recalculées en double | **0 époque complète** : seule l'époque 2 entamée (≈ 30 s de calcul) est refaite depuis son début. L'époque 1 n'est pas recalculée |
| Taille du point de reprise (`reprise.pt`) | **89 579 657 octets** (85,4 Mio), soit environ deux fois les poids (état courant + meilleur état), plus l'optimiseur et l'historique. Le fichier est supprimé en fin d'entraînement |

Trace : `sorties/entrainement_avant_coupure.txt` (époque 1, puis le `KeyboardInterrupt` en pleine époque 2) et `sorties/entrainement.txt` (la relance).

**Question 3.4**
- **Le meilleur état rencontré** sert à ce que la sélection sur la meilleure époque porte sur **toute** la course, y compris les époques faites avant la coupure. Sans lui, une meilleure époque antérieure à la coupure serait perdue.
- **L'état du générateur aléatoire** fait que la relance tire le même ordre de lots et les mêmes augmentations que l'aurait fait une course sans coupure. Sans lui, le générateur repartirait de la graine 42 : l'époque 2 rejouerait l'ordre et les augmentations de l'époque 1, et le modèle obtenu ne serait plus celui d'une course ininterrompue. Il serait toujours valide, mais pas reproductible.

### Mesure 9 — latence du réseau seul, lot de 1

| Dispositif | p50 (ms) | p95 (ms) |
|---|---|---|
| CPU (4 fils, conteneur sur le portable) | **25,3** | **29,9** |
| GPU | — (pas de GPU) | — |

**Question 3.5** — Non. Le GPU accélère l'entraînement parce qu'il traite des lots de 64 images en parallèle, en avant et en arrière, des milliers de fois. Une prédiction unitaire est un petit calcul (un passage avant sur une image de 128 px), où le coût fixe (copie vers la carte, lancement des noyaux) pèse autant que le calcul. Sur CPU, elle prend 25 ms. Le plan B1 de S3 n'a qu'**un** vCPU, contre 4 fils ici : il faut s'attendre à un multiple de ces 25 ms (de l'ordre de 50 à 100 ms), ce qui reste très acceptable pour une consultation. Servir ce modèle **n'exige pas de GPU** ; c'est la capacité du plan (un vCPU partagé entre les requêtes) qui posera problème sous charge, pas le matériel de calcul.

### Mesure 10 — vérification du paquet

| Relevé | Ma valeur |
|---|---|
| Nombre de contrôles OK / total, et verdict | **13 / 13**, **RENDU RECEVABLE** (`captures/verifier_s4.txt`) |
| Contrôles « SAUTE », le cas échéant | **Aucun** : les poids ImageNet étaient dans le cache (`TORCH_HOME`) et l'archive dans `donnees/` |
| `sha256` de `modele.pt` (16 premiers caractères), égalité avec `sha256_poids` | `b44771c802585db7`, **identique** à `sha256_poids` |
| Taille de `modele.pt` | **44 780 171 octets** (44,8 Mo) |
| `isic_id` et `probabilite_maligne` du bloc `controle` | `ISIC_0104229`, **0,06629** (recalculée par le vérificateur : 0,066289, écart < 1e-5) |

**Question 3.6**
1. **Un notebook se partage** : il circule sur le dépôt de classe, en lien Colab, avec ses sorties de cellules. Un secret Azure écrit dans une cellule, ou affiché par une commande, fuit avec lui, et il donnerait la main sur le registre (pousser ou écraser des images).
2. **Le paquet rend Colab inutile pour la publication** : poids, meta, manifeste et empreintes suffisent à reconstruire l'image sur le poste. C'est là qu'on prouve l'intégrité du paquet (vérificateur, `sha256`) avant de l'emballer, et le poste est déjà authentifié auprès d'Azure (`az login`, `az acr login`) sans qu'aucun secret ne soit copié ailleurs.
