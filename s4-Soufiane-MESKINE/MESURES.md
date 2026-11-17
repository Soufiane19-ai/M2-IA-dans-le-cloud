# Mesures — Séance 4

Soufiane Meskine, M2 YNOV Montpellier, 17/11/2026. Les mesures 1 à 10 sont dans `JOURNAL.md`.

## Partie 4 — Évaluation et recalibration

Tout est recalculé à partir de `sorties/predictions_validation.csv` et de `model/modele_meta.json` (`analyse_partie4.py`).

### 4.1 — Mesure 11 : la matrice au seuil

Seuil choisi par `seuil_pour_rappel` (séance 2, inchangée) sur la validation, pour un rappel d'au moins **0,90**. La décision est `probabilite_maligne >= meta["seuil"]`, le seuil servi par l'API.

|  | Prédit `a_examiner` | Prédit `surveillance` |
|---|---|---|
| **Malin** | VP = **53** | FN = **6** |
| **Bénin** | FP = **254** | VN = **745** |

| Contrôle | Ma valeur |
|---|---|
| Somme des quatre cases, comparée au nombre de vignettes de validation | 53 + 6 + 254 + 745 = **1 058**, soit toutes les vignettes de validation |
| Ma matrice est-elle identique à `matrice_confusion_validation` du meta ? | **Non, d'une lésion** : le meta indique VP 54 / FN 5, et j'obtiens VP 53 / FN 6. FP et VN sont identiques |

**Question 4.1** — La lésion la plus proche du seuil est **`ISIC_0521019`, une maligne**. Sa `probabilite_maligne` relue dans le CSV vaut 0,000499062594233615**4** moins 1,5 × 10⁻¹⁷ : c'est **exactement le seuil**, au dernier bit près. Ce n'est pas un hasard. `precision_recall_curve` ne prend comme seuils candidats que les **scores des lésions elles-mêmes** ; le seuil retenu est donc le score de la maligne qui fait franchir le rappel de 0,90, et cette maligne est, par construction, pile sur le seuil, retenue par l'inégalité `>=`. L'aller-retour par un fichier texte réécrit chaque probabilité en décimal puis la relit : la dernière décimale peut être arrondie d'un ulp. Ici, elle est arrondie **vers le bas**, et la maligne passe sous le seuil, en surveillance. Une seule lésion, mais c'est une maligne manquée. Il faut comparer avec une tolérance, ou garder le seuil un ulp sous le score ; et surtout, ne jamais juger une variante sur le rappel en limite de seuil, mais sur les décisions changées (point repris en séance 5).

### 4.2 — Mesure 12 : métriques au seuil, à partir de ma matrice

| Métrique | Formule | Ma valeur |
|---|---|---|
| Rappel | VP / (VP + FN) | 53 / 59 = **0,898** (meta : 0,915, avec 54 VP) |
| Précision en validation | VP / (VP + FP) | 53 / 307 = **0,173** |
| Taux de faux positifs | FP / (FP + VN) | 254 / 999 = **0,254** |
| Part des lésions envoyées en examen | (VP + FP) / N | 307 / 1 058 = **29,0 %** |

Tableau de seuils, sur `proba_brute` (59 malignes en validation) :

| Seuil sur `proba_brute` | VP | FP | Rappel | Précision |
|---|---|---|---|---|
| 0,5 | 24 | 21 | 0,407 | 0,533 |
| 0,1 | 45 | 88 | 0,763 | 0,338 |
| 0,05 | 47 | 148 | 0,797 | 0,241 |
| `seuil_brut` du meta (0,021228) | 53 | 254 | 0,898 | 0,173 |
| 0,01 | 55 | 402 | 0,932 | 0,120 |

**Question 4.2** — Non. À 0,5, le modèle n'envoie en examen que 24 malignes sur 59 : **35 malignes partent en surveillance**, soit un rappel de 0,41, à comparer aux 0,90 visés. 0,5 n'a aucun statut particulier : ce serait la frontière « plus probable que non » pour un modèle **calibré** sur la **vraie** prévalence avec des coûts d'erreur **égaux**. Or ce réseau a appris à 5,55 % de prévalence, ses probabilités ne sont pas calibrées, et rater une maligne coûte bien plus qu'un examen inutile. Le seuil se choisit sur l'objectif clinique (le rappel), pas par convention.

### 4.3 — Mesure 13 : recalibration

```python
beta = 5000 / 217183
z = math.log(meta["seuil_brut"] / (1 - meta["seuil_brut"]))
print(beta, math.log(beta), 1 / (1 + math.exp(-(z + math.log(beta)))))
```

| Grandeur | Mon calcul | Valeur du meta |
|---|---|---|
| β | 5 000 / 217 183 = **0,023022** | `taux_negatifs` : 0,023022059737640606 |
| ln β | **−3,7713** | `correction_logit` : −3,7713024036859 |
| Seuil brut | — | `seuil_brut` : 0,021228004568039496 |
| Seuil recalibré σ(logit(seuil brut) + ln β) | **0,0004990626** | `seuil` : 0,0004990625942336154 |
| Décisions de validation changées par la recalibration | **0** (`proba_brute >= seuil_brut` et `probabilite_maligne >= seuil` donnent les mêmes 1 058 décisions) | — |
| Précision projetée sur le flux réel | 0,898 × 0,00135 / (0,898 × 0,00135 + 0,254 × 0,99865) = **0,00476** | `precision_projetee_prevalence_reelle` : 0,00485 (avec le rappel de 0,915 du meta) |
| Lésions examinées par maligne trouvée | 1 / 0,00476 ≈ **210** | `lesions_examinees_par_maligne_reelle` : **206** |
| Même grandeur pour le modèle tabulaire de S2 | **198** (`MESURES.md` de S2, au même rappel visé de 0,90) | — |

**Question 4.3**
- **Pour le dermatologue**, qui lit `probabilite_maligne` : sans recalibration, la réponse affichée « 0,066 » pour l'image de contrôle aurait été σ(logit), soit **0,75**, un chiffre appris à 5,5 % de prévalence, quarante fois trop pessimiste. Recalibrée, la probabilité dit le risque **dans le flux réel** : environ 6,6 %, pour une lésion déjà parmi les plus suspectes. Le chiffre affiché a un sens clinique.
- **Pour l'analyste de la séance 5**, qui compare la distribution des probabilités servies à celle de l'entraînement : la recalibration fixe une **échelle unique et documentée**. Toute la référence est dans le meta (`correction_logit`, prévalences) : il compare des probabilités sur la même échelle, et un changement de la prévalence du flux servi deviendra visible comme un déplacement de cette distribution, au lieu d'être confondu avec l'artefact de l'échantillonnage.
- **Ce qu'elle ne change pas** : les décisions. La transformation est croissante et le seuil est transformé de la même façon.

**Question 4.4** — Sur la validation :
1. **API qui sert `proba_brute` et applique le seuil recalibré (0,0005)** : **92,0 %** des lésions sont envoyées en examen, avec un rappel de 0,983. Le service devient inutile (il n'élimine plus rien), et il noie les malignes dans le volume.
2. **API qui sert la probabilité recalibrée et applique le seuil brut (0,0212)** : **4,3 %** des lésions sont envoyées en examen, avec un rappel de **0,424**. **58 % des malignes partent en surveillance.**

La **seconde** erreur est la plus dangereuse pour un patient. Elle est discrète : peu d'alertes, un service qui semble « sobre », alors qu'il manque une maligne sur deux. La première se voit tout de suite, puisque tout le monde est envoyé en examen.

**Question 4.5** — Pondérer les positifs d'un facteur w multiplie aussi les cotes apprises par w : il faudrait ajouter **−ln w** au logit, soit `correction_logit = ln β − ln w`.

### 4.4 — Mesure 14 : PR-AUC ramenées à une même prévalence

```python
w = np.where(y == 1, 1.0, 1 / beta)        # poids des negatifs : 1/beta = 43,44
average_precision_score(y, p, sample_weight=w)
```

| | PR-AUC | Hasard (prévalence) |
|---|---|---|
| S4, validation sous-échantillonnée (meta) | **0,480** | 0,0558 (59 / 1 058) |
| S4, négatifs repondérés par 1/β | **0,0437** | 0,00136 |
| S2, flux réel (`MESURES.md` de S2) | **0,0551** | 0,00135 |

**Question 4.6** — La PR-AUC est construite sur la **précision**, VP / (VP + FP). À rappel donné, multiplier le nombre de négatifs par 43 multiplie les faux positifs par 43, et la précision s'effondre : la PR-AUC dépend donc directement de la proportion de négatifs. La ROC-AUC compare le taux de vrais positifs (calculé parmi les seuls positifs) au taux de faux positifs (calculé parmi les seuls négatifs) : chaque taux est conditionnel à sa classe, et la prévalence s'annule. Vérifié : ROC-AUC 0,8993 sans pondération, 0,8993 avec.

Conclusion honnête : à la même prévalence, le CNN (0,044, soit environ 32 fois le hasard) ne fait **pas mieux** que le modèle tabulaire de S2 (0,055, soit 41 fois le hasard), alors que la PR-AUC brute de 0,48 laissait croire l'inverse. Mais les deux validations ne portent ni sur les mêmes lésions (archive Permissive contre jeu complet), ni sur le même nombre de positifs (59 contre 110). Avec 59 positifs, l'incertitude est de plusieurs points, et mon CNN est entraîné en mode dégradé (5 000 négatifs, sans GPU). On ne peut conclure ni que l'image fait mieux, ni qu'elle fait moins bien. Pour trancher, il faudrait comparer les deux modèles **sur les mêmes lésions de validation**.

## Partie 5 — Une seule pièce changée dans la chaîne

### 5.1 — Copier l'API de S2, changer une ligne

`api-s4/` : `Dockerfile` et `.dockerignore` de S2, `app.py` et `requirements.txt` distribués, `model/modele.pt` et `model/modele_meta.json`.

`diff` du Dockerfile S2 → S4 : **deux lignes**, et non une seule. Mon Dockerfile de S2 copiait le modèle par son nom de fichier (`COPY model/modele.joblib ./model/`), et non le dossier `model/`. Il faut donc changer `MODEL_PATH=model/modele.joblib` en `MODEL_PATH=model/modele.pt`, **et** `COPY model/modele.joblib ./model/` en `COPY model/modele.pt model/modele_meta.json ./model/`. La base, l'ordre des couches, l'utilisateur 10001 et le `CMD` gunicorn de S2 restent inchangés. Mon `.dockerignore` de S2 excluait `*.json`, ce qui aurait écarté `modele_meta.json` : j'y ai ajouté l'exception `!model/modele_meta.json`, ainsi que `**/*.csv` et `**/*.zip` pour que le manifeste et l'archive ne puissent jamais entrer dans l'image.

**Question 5.1** — Les quatre points du diff de `app.py` :
1. **Chargement** : `joblib.load` d'un pipeline scikit-learn est remplacé par la construction d'un `resnet18(weights=None)`, à tête `Linear(512, 1)`, dans lequel on charge `modele.pt`. Les paramètres (seuil, normalisation, correction) viennent de `modele_meta.json`, posé à côté.
2. **Entrée de `/predict`** : un objet JSON de 40 variables est remplacé par un fichier image en multipart (champ `image`), converti en RGB, redimensionné à 128 px (bilinéaire) et normalisé.
3. **Correction de prior** : la probabilité servie est σ(logit + `correction_logit`), et non la sortie brute du modèle.
4. **`/model/info`** expose l'architecture, la taille d'entrée, l'échantillonnage, les deux prévalences, `sha256_poids` et la date d'entraînement, à la place des 40 colonnes attendues.

Ce qui ne change pas : les **routes** (`/health`, `/model/info`, `/predict`), les **codes** (200, 400 pour une requête invalide, 503 sans modèle), et les **clés de la réponse de `/predict`** (`probabilite_maligne`, `seuil`, `decision` à valeur `a_examiner` / `surveillance`, `version_modele`, `rappel_cible`). Seul le corps de `/health` s'enrichit : `service`, `hostname`, `uptime_seconds`. Cette stabilité compte, car les postes de consultation (et la supervision de S3) lisent ces clés : un client qui sait lire la réponse 1.0.0 lit la réponse 2.0.0 sans modification. Seule la façon d'**envoyer** la lésion change, ce qui justifie le passage en version majeure.

**Question 5.2**
- `resnet18(weights=None)` : au démarrage du conteneur, on construit l'**architecture vide**, sans télécharger les poids ImageNet (environ 45 Mo depuis `download.pytorch.org`), qui seraient de toute façon écrasés par `load_state_dict`. Le conteneur démarre donc sans réseau (vérifié, mesure 16) et ne dépend d'aucun service extérieur.
- `torch.load(..., weights_only=True)` : un `.pt` est un fichier *pickle*, et le dé-sérialiser peut **exécuter du code arbitraire** caché dans le fichier. `weights_only=True` n'accepte que des tenseurs et des types simples. Un `modele.pt` piégé (substitué dans le registre ou dans le paquet) ne peut pas prendre la main sur le conteneur.

**Question 5.3**
1. **Taille et coût** : le base64 grossit l'image d'un tiers, et l'API devrait recevoir le JSON entier en mémoire puis le décoder. Le multipart transporte les octets bruts, que Flask peut lire en flux.
2. **Contrat et outillage** : un formulaire multipart est le standard d'envoi de fichier (navigateur, `curl -F`, client HTTP du poste), qui porte le nom et le type du fichier, et que Locust envoie tel quel. Le JSON base64 imposerait un encodage maison des deux côtés, avec ses erreurs (sauts de ligne, préfixe `data:`).

### 5.2 — Mesure 15 : construction et scan

`docker build --no-cache --pull --platform linux/amd64 --provenance=false -t dermascan-api:2.0.0 api-s4`

| Relevé | Ma valeur |
|---|---|
| Durée de la construction à froid | **123,7 s** (`--no-cache --pull`). Le `pip install` télécharge la roue `torch 2.14.1+cpu` de 196 Mo |
| Taille de l'image S4 (`docker images`) | **1,67 Go** (contenu décompressé ; 404 Mo compressés selon `docker image inspect` et Docker Scout) |
| Taille de l'image S2, relevée par la même commande | **651 Mo** (`dermascan-api:1.0.0`, retirée du registre pour la comparaison) |
| Résultat de `docker scout cves` : C / H / M / L, et code retour | **9 C / 66 H / 72 M / 61 L** (et 11 non classées), **219 vulnérabilités sur 27 paquets** ; **code retour 2** (`captures/scout_cves_s4.txt`). Toutes sont dans les paquets Debian 12 de la base `python:3.12.7-slim-bookworm` (perl 5C/8H, openssl 4C/18H, gnutls, krb5, glibc, sqlite…), plus `pip 24.2` (5 M, 1 L). **Aucune** dans torch, torchvision, numpy, Pillow, Flask ou gunicorn |
| Exceptions écrites, le cas échéant | **Oui, une exception globale**, écrite ci-dessous |

Premier essai du scan : code 1, « Log in with your Docker ID ». `docker scout` exige une connexion à Docker Hub, que j'ai faite (`docker login`) avant de relancer.

**Exception écrite (mesure 15).** L'image 2.0.0 ne passe pas la porte zéro CVE. Je la pousse quand même, sous les conditions suivantes :
1. **Origine** : 100 % des vulnérabilités viennent de la **base Debian** figée en S1 (`python:3.12.7-slim-bookworm`, tag publié il y a deux ans) et de `pip`, que mon Dockerfile de S2 ne retire pas. Aucune ne vient du code ni des dépendances d'inférence. Le scan indique que la même base rafraîchie tomberait à 0 C / 2 H / 7 M / 28 L : rafraîchir ne suffit donc pas à atteindre zéro, et il faudra changer de base (Wolfi ou distroless) et retirer `pip` dans le même `RUN`.
2. **Exposition** : le conteneur ne termine pas le TLS (c'est le frontal App Service qui le fait, donc les failles d'openssl et de gnutls ne sont pas sur le chemin des requêtes), n'exécute jamais `perl`, `apt` ni `dpkg`, et tourne en utilisateur non root 10001.
3. **Durée** : le déploiement est une **recette éphémère**, détruite en fin de séance (partie 7), sans données réelles de patients.
4. **Correction** : programmée en **séance 5**, qui reconstruit l'image sans PyTorch et repasse la porte. Cette exception ne vaut pas pour la mise en production.

### 5.3 — Mesure 16 : démarrage hors ligne et concordance

| Relevé | Ma valeur |
|---|---|
| Délai jusqu'au premier `/health` à 200, sous `--network none` | **7,3 s** (conteneur sans aucune interface réseau : `{"none": {...}}`) |
| Corps de `/health` | `{"hostname":"1c8d1e9eabdc","model_loaded":true,"service":"isic-vignettes-api","status":"ok","uptime_seconds":0.9}` |
| `probabilite_maligne` et `decision` servies pour l'image de contrôle | **0,066289**, **`a_examiner`** (`ISIC_0104229`, seuil 0,000499 ; `captures/predict_local.json`) |
| `controle.probabilite_maligne` du meta, et écart absolu | **0,06629** ; écart **1 × 10⁻⁶**, sous la tolérance de 10⁻⁵. Le meta arrondit à 6 décimales (0,066289**5**…) |
| Codes HTTP : sans champ `image` / avec un fichier qui n'est pas une image | **400** / **400** (`"image illisible"`, `UnidentifiedImageError`) |

L'entraînement a tourné en `linux/amd64` (conteneur sur un processeur Intel), comme l'image : même architecture, même roue torch.

**Question 5.4** — Avec un autre filtre (BICUBIC, LANCZOS, ou le redimensionnement de torchvision), les 128 × 128 pixels ne seraient pas les mêmes que ceux vus à l'entraînement. Le réseau calculerait une probabilité légèrement différente pour chaque image, **sans aucune erreur ni avertissement** : l'API répondrait 200, avec des chiffres plausibles mais décalés, et des décisions qui basculeraient près du seuil. La mesure 16 est le seul garde-fou : elle compare, sur la même image, la probabilité servie par le conteneur à celle calculée à l'entraînement, à 10⁻⁵ près. Un écart de prétraitement s'y voit immédiatement, alors qu'aucun test fonctionnel (codes, clés de réponse) ne le détecterait.

### 5.4 — Mesure 17 : mesures comparatives S2 / S4

Les mesures S2 ont été refaites aujourd'hui sur la même machine, dans les mêmes conditions (image 1.0.0 retirée du registre, `mesurer_s2.ps1`), sauf la durée de construction, reprise de S2.

| Grandeur | S2 | S4 |
|---|---|---|
| Taille de l'image (`docker images`) | 651 Mo | **1,67 Go** |
| Taille du fichier de modèle | 9,5 Ko | **44,8 Mo** |
| Durée de construction à froid | 646,4 s (S2, réseau lent ce jour-là) | **123,7 s** |
| Démarrage jusqu'au premier `/health` à 200 | 4,4 s | **7,6 s** (7,3 s hors ligne) |
| Mémoire du conteneur au repos (`docker stats`) | 240,1 Mio | **577,6 Mio** |
| Latence `/predict` p50 / p95, local, 50 appels | 14,2 / 24,6 ms | **27,6 / 43,2 ms** |
| Latence du réseau seul, lot de 1 (mesure 9) | — | 25,3 / 29,9 ms |
| Architecture du poste | amd64 natif (Intel Core i7-10510U, Docker Desktop WSL2) | amd64 natif (idem) |

Les deux images lancent gunicorn avec **2 workers** (le `CMD` de S2, conservé) : la mémoire au repos compte deux copies du réseau, d'où 578 Mio.

**Question 5.5** — Le p50 local est de 27,6 ms : un worker synchrone peut servir au mieux 3 600 / 0,0276 ≈ **130 000 lésions par heure**, en enchaînant les requêtes sans pause. C'est un **plafond optimiste** pour B1 :
1. Ce p50 a été obtenu avec PyTorch sur **4 cœurs** physiques du portable ; B1 n'a qu'**un** vCPU, partagé entre les 2 workers, gunicorn et la plateforme, donc chaque inférence y coûtera plusieurs fois plus de temps.
2. En local, il n'y a ni le réseau, ni le frontal HTTPS d'Azure, ni la concurrence entre requêtes qui attendent le même processeur.
3. Mesurée en régime établi, avec une seule requête à la fois, cette valeur ignore les pics, où le p95 et la file d'attente dominent (S3 : CPU à 100 % dès 50 utilisateurs, avec un modèle bien plus léger).

### 5.5 — Mesures 18 et 19 : le service en ligne

Scénario `locustfile_s4.py` : celui de S3, avec l'image de contrôle (`ISIC_0104229.jpg`) lue une seule fois et envoyée en multipart.

| Décision | Ma valeur |
|---|---|
| `wait_time` | `between(1, 3)`, celui de S3 |
| Poids de la tâche `GET /health` | 1, contre 8 pour `/predict` (et 1 pour `/model/info`), comme en S3 |
| Utilisateurs des paliers 1 et 2 | **10** et **50** (les paliers 1 et 2 de S3), 3 minutes chacun, montée à 5 par seconde |

Comme en S3, chaque utilisateur ouvre d'abord sa connexion par un `GET /health` compté à part (`0. ouverture connexion TLS`). Cet après-midi, l'ouverture TLS ne coûtait plus que 0,07 s (`curl` : `tls=0.069`) : la mesure a été faite **hors du réseau de l'école**.

Déploiement : routine de S3 dans `rg-dermascan-s4-sm26` (étiquettes `seance=s4`, `a_detruire=2026-11-17`), plan Linux **B1** `plan-dermascan-s4-sm26`, application `dermascan-api-s4-sm26`, identité managée avec le rôle `AcrPull` sur le registre seul, `acrUseManagedIdentityCreds=true`, `WEBSITES_PORT=8000`, `PORT=8000`, `MODEL_VERSION=2.0.0`, **`WEBSITES_CONTAINER_START_TIME_LIMIT=600`**.

#### Mesure 18 — le service S4 en ligne

| Relevé | Ma valeur |
|---|---|
| Durée du `docker push`, et taille annoncée | **65,7 s** ; image de **404 Mo** compressés (digest `sha256:ec4a45b98aa6cdd6832da0f022faf46fab15929db9600324d9923b1397bbb40e`, `linux/amd64`). Les couches de la base, partagées avec 1.0.0, étaient déjà dans le registre |
| Tags présents dans le dépôt `dermascan-api` | **`1.0.0`** et **`2.0.0`** |
| Durée entre le restart et le premier 200 sur `/health` | **345 s** (codes `000 000 000 000 200`, délai client de 60 s). Le CPU du plan est resté à 98-100 % pendant tout le démarrage : chargement de PyTorch et du réseau sur un seul vCPU |
| `probabilite_maligne` et `decision` servies sur Azure pour l'image de contrôle | **0,066289**, **`a_examiner`** : identiques au local et au meta (`captures/predict_azure.json`) |
| `version` et `version_deployee` de `/model/info` | **`2.0.0`** et **`2.0.0`** (`captures/model_info_azure.json`) |

#### Mesure 19 — charge sur le service S4, comparée à S3

Lignes `POST /predict` des CSV (`palier_s4_1_stats.csv`, `palier_s4_2_stats.csv`) ; débit de la ligne `Aggregated`.

| Palier | Utilisateurs | Débit (req/s) | p50 (ms) | p95 (ms) | p99 (ms) | Échecs (%) |
|---|---|---|---|---|---|---|
| 1 | 10 | 2,93 (dont 2,33 `/predict`) | **1 400** | **3 500** | 4 100 | 0 (0 / 374) |
| 2 | 50 | 5,98 (dont 4,45 `/predict`) | **3 500** | **17 000** | 20 000 | 0 (0 / 1 059) |
| S3, palier 1 (10 utilisateurs) | 10 | 4,16 (dont 3,26 `/predict`) | 83 | 530 | 1 500 | 0 |
| S3, palier 2 (50 utilisateurs) | 50 | 12,15 (dont 9,54 `/predict`) | 680 | 4 300 | 8 200 | 0,52 |

Côté plateforme : **CPU du plan à 98-100 % de 11:50 à 12:01 UTC**, c'est-à-dire du démarrage jusqu'à la fin du palier 2, et mémoire du plan à 80-88 % pendant la charge ; `HttpResponseTime` moyen de 1,3 à 1,5 s au palier 1, de 3,2 à 16,5 s au palier 2 ; **aucune** réponse 5xx.

**Question 5.6** — À 10 utilisateurs, le p50 de `/predict` passe de **83 ms (S3)** à **1 400 ms (S4)**, soit environ 17 fois plus, et le débit plafonne à 4,5 prédictions par seconde au palier 2, contre 9,5 en S3. Le relevé de la mesure 17 qui l'explique est la **latence d'inférence** : 27,6 ms de p50 en local, contre 14,2 ms en S2, mais obtenue sur **4 cœurs**. Sur le vCPU unique du B1, chaque passage du ResNet18 coûte plusieurs centaines de millisecondes, et les requêtes s'y mettent en file : le CPU du plan est à 100 % **dès 10 utilisateurs**, alors qu'en S3 il ne saturait qu'à 50. La mémoire au repos (578 Mio, contre 240 Mio) pèse aussi sur un plan de 1,75 Go, à 80-88 %.

L'engagement de service de S3 (« jusqu'à 10 utilisateurs simultanés, 95 % des prédictions en moins de 530 ms, moins de 1 % d'échecs ») **ne tient plus** : avec le nouveau modèle, sur le même plan, le p95 à 10 utilisateurs est de **3 500 ms**, presque sept fois la promesse, même si aucun échec n'a été compté. Il faudrait un plan avec plus de vCPU, ou un modèle plus léger à servir : c'est l'objet de la séance 5 (ONNX, quantization).

## Partie 7 — Nettoyage et extinction

`nettoyage_s4.ps1` (journal `logs/nettoyage_s4.log`), lancé à 14:44. L'archive des logs App Service est sauvegardée (`logs/logs_s4.zip`). L'attribution `AcrPull` est supprimée **avant** le groupe, tant que l'identité existe ; seul le groupe `rg-dermascan-s4-sm26` est détruit, et les deux images restent dans le registre.

#### Mesure 21 — contrôles de fin de séance

| Contrôle | Mon observation |
|---|---|
| Ressources listées dans `$RG` avant destruction | **2** : `plan-dermascan-s4-sm26` (`Microsoft.Web/serverFarms`) et `dermascan-api-s4-sm26` (`Microsoft.Web/sites`) |
| `az group exists --name "$RG"` | `true` à 14:47:15 et 14:47:45, puis **`false`** à 14:48:16 (≈ 80 s après la demande) |
| `az group exists --name "$RG_REGISTRE"` | **`true`** : `az group list` ne montre plus que `rg-dermascan-registre-sm26`, qui contient `acrdermascansm26` (`Succeeded`) |
| Tags présents dans le registre après nettoyage | **`1.0.0`** et **`2.0.0`** (attributions sur le registre : aucune) |
| Point de reprise supprimé du Drive, session Colab terminée | **Sans objet** : entraînement local (annexe B), aucun Drive ni Colab utilisé. Le point de reprise local `sorties/reprise.pt` est supprimé par `entrainer.py` en fin d'entraînement (absent du dossier `sorties/`) |
| Crédit restant, relevé dans Cost Management, et écart avec S3 | **84 € sur 90 €** de crédit (le plafond est passé de 88 € à 90 €), coûts de **novembre 2,59 €**, 323 jours avant expiration (page Education, 14:58 ; `captures/credit_education_s4.png`). Fin de S3 : 87 € sur 88 €. L'écart, **3 €**, couvre l'ensemble de novembre (registre Basic tout le mois, et environ 2 h de plan B1 aujourd'hui) ; la facturation du jour peut encore arriver avec quelques heures de retard |

En local : le conteneur `dermascan-api-s4` est supprimé ; les images `dermascan-api:2.0.0` (pour S5) et `dermascan-api:1.0.0` sont conservées, ainsi que l'environnement d'entraînement `dermascan-entrainement:s4`.

**Question 7.1** — En séance 3, l'abonnement ne contenait que deux groupes, et `$RG` venait d'être posé par le même script. Aujourd'hui, après quatre séances, on manipule plusieurs groupes aux noms voisins (`rg-dermascan-s3-…`, `rg-dermascan-s4-…`) dans des terminaux et des scripts successifs, et surtout un groupe **qu'il ne faut jamais détruire** : `rg-dermascan-registre-sm26`, qui porte le registre et les images 1.0.0 et 2.0.0 dont dépend la séance 5. Une variable `$RG` écrasée par un vieux shell, ou par une session restée ouverte depuis la séance 1 où `RG` désignait le registre, suffirait à lancer `az group delete --yes` sur le mauvais groupe, de façon irréversible. La garde `case` refuse tout nom qui ne commence pas par `rg-dermascan-s4-` ; dans `nettoyage_s4.ps1`, le nom du groupe est écrit en dur dans le script, ce qui joue le même rôle.
