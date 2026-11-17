# Mesures — Séance 5, optimiser

Soufiane Meskine, M2 YNOV Montpellier, 17/11/2026. Mon paquet S4 (`b44771c802585db7…`) est utilisé, pas le paquet de référence de l'annexe B.

**Conditions** : comme en S4, les outils (export, comparaison, rejeu, dérive) tournent dans un **conteneur Linux** (`Dockerfile.outils` : l'environnement d'entraînement de S4, avec Python 3.12.7, torch 2.14.1+cpu, onnx 1.23.2, onnxruntime 1.31.0, onnxscript 0.7.2, numpy 2.5.4, pillow 13.0.0, pandas 3.0.6), sur le portable Intel Core i7-10510U (amd64 natif). Les fichiers distribués sont utilisés tels quels, blancs remplis.

## Partie 1 — Point de départ

### Mesure 1 — le point de départ (recopié de `MESURES.md` de S4)

| Grandeur (S4) | Ma valeur |
|---|---|
| Empreinte de `modele.pt`, identique à `sha256_poids` | **Oui** : `b44771c802585db7969ba6e9dff0eb947ea639fb25f8402860224b56d339fd0a`, recalculée en début de séance |
| Taille de l'image `dermascan-api:2.0.0` | **1,67 Go** (`docker images`), 404 Mo compressés |
| Taille du fichier de modèle | **44,8 Mo** |
| Démarrage jusqu'au premier `/health` à 200 | **7,6 s** (7,3 s hors ligne) |
| Mémoire du conteneur au repos | **577,6 Mio** |
| Latence `/predict` p50 / p95, local | **27,6 / 43,2 ms** |
| Mesure 19 : p50 et p95 au palier le plus chargé sur B1, CPU du plan | 50 utilisateurs : **3 500 / 17 000 ms**, CPU du plan **98-100 %** (dès 10 utilisateurs) |
| Mesure 20 : part de `3D: white` dans mon manifeste et dans l'archive | **55,23 %** (manifeste), **52,73 %** (archive) |

**Question 1.1** — Avec 8 fils, chaque variante parallélise ses convolutions sur plusieurs cœurs, plus ou moins bien selon le moteur : celle qui en tire le plus de profit gagne, et l'écart mesuré dépend surtout de la qualité de cette parallélisation. Sur B1, il n'y a qu'**un** vCPU : ce bonus disparaît, et un moteur qui crée plusieurs fils se les dispute sur un seul cœur (la mesure 6 le montre : 8 fils sous `--cpus 1`, 5 fois plus lent). Le classement fait avec tous les cœurs pourrait donc s'inverser sur B1.

**Question 1.2** — Au premier appel, et plus jamais ensuite :
1. **Les initialisations paresseuses du moteur** : allocation des arènes mémoire, choix des noyaux de calcul selon le processeur (oneDNN pour PyTorch, noyaux MLAS d'ONNX Runtime), dernières optimisations du graphe.
2. **Les caches à froid** : les 44,8 Mo de poids sont amenés en mémoire, puis dans les caches du processeur (défauts de page, défauts de cache), et le prédicteur de branchement n'a encore rien appris.

Ces 20 appels mesureraient le démarrage du moteur, pas son régime de croisière.

## Partie 2 — Export ONNX

Blancs remplis dans `exporter_onnx.py` : `input_names=["entree"]` (le nom lu par `comparer.py` dans `s.run(None, {"entree": x})` ; `app.py` le lit dans la session) et `external_data=False` (un seul fichier, poids inclus).

### Mesure 2 — l'export

| Relevé | Ma valeur |
|---|---|
| Taille de `modele.onnx`, comparée à `modele.pt` | **44 774 284** octets contre 44 780 171 (44,8 Mo l'un et l'autre) : un seul fichier, aucun `.onnx.data` |
| Empreinte de `modele.onnx` (16 premiers caractères) | `c7d89deb11d3b32b` |
| Écart maximal de logit sur le lot de contrôle | **7,6e-06** (lot aléatoire de 4, seuil de l'assertion : 1e-4) |
| L'export relancé une seconde fois donne-t-il la même empreinte ? | **Oui** : `c7d89deb11d3b32b2959977e…` les deux fois (et une troisième fois, avant la quantization). L'export est déterministe |

L'export prend 150 à 170 s sur le portable, à cause de `torch.export` et des optimisations du graphe.

**Question 2.1** — Sans `reseau.eval()`, le réseau serait exporté en **mode entraînement** : les couches **BatchNorm** (`bn1` et les deux `bn` de chaque bloc de `layer1` à `layer4`, 20 couches en tout) normaliseraient chaque entrée avec les statistiques **du lot courant** au lieu des statistiques apprises (`running_mean`, `running_var`). Avec un lot de 1 en service, chaque image serait normalisée par elle-même, et la sortie ne voudrait plus rien dire. L'écart de logit l'aurait révélé, dès lors que la référence est calculée en mode évaluation : les mêmes images donneraient des logits très différents (bien au-delà de 1e-4), et la probabilité de contrôle ne serait plus 0,0663. ResNet18 n'a pas de Dropout ; ce sont les BatchNorm qui comptent.

**Question 2.2** — `onnx.checker.check_model` vérifie que le fichier est un **graphe ONNX valide** : opérateurs connus de l'opset 18, types et formes cohérents, connexions bien formées. Il ne dit **rien du calcul** : un graphe parfaitement valide peut calculer autre chose (BatchNorm en mode entraînement, mauvaise normalisation, poids mal chargés). L'assertion qui suit vérifie l'**équivalence numérique** : sur 4 entrées, ONNX Runtime et PyTorch donnent le même logit, à 1e-4 près.

**Question 2.3** — Fixer `3 × 128 × 128`, c'est inscrire le contrat du modèle dans le fichier (il n'a appris qu'à cette taille). Cela permet aussi à ONNX Runtime de planifier la mémoire et de simplifier le graphe à l'avance. Une image de 300 px est **redimensionnée à 128 par l'API** (`resize((t, t), BILINEAR)`) avant d'atteindre le modèle : le service l'accepte, et le réseau ne voit jamais 300 px. Un tenseur de 300 px envoyé directement à la session serait refusé (`InvalidArgument`, dimension incompatible).

## Partie 3 — Quantization et trois variantes

### Mesure 3 — les trois variantes (`comparer.py`, 1 fil, 20 + 300 appels, 1 058 vignettes de validation, seuil 0,000499)

| Variante | Taille (Mo) | p50 (ms) | p95 (ms) | Proba de contrôle | Rappel au seuil | Alertes | ROC-AUC | Écart max de proba | Décisions changées |
|---|---|---|---|---|---|---|---|---|---|
| PyTorch | 44,8 | 542,0 | 1 279,3 | 0,066290 | 0,8983 | 307 | 0,8993 | 0 | 0 |
| ONNX | 44,8 | **157,1** | **404,3** | 0,066290 | 0,8983 | 307 | 0,8993 | **3e-06** | **0** |
| ONNX int8 | **11,3** | 175,8 | 413,3 | **0,099081** | 0,9153 | 308 | 0,8994 | **0,23** | **39** |

Latences mesurées l'après-midi, sur un portable visiblement plus lent qu'à midi (S4 : 25 ms avec 4 fils). Elles comparent les variantes entre elles, dans les mêmes conditions, et ne valent pas comme latences absolues.

### Mesure 4 — ce que l'int8 change (`analyse_variantes.py`)

| Relevé | Ma valeur |
|---|---|
| Décisions passées en `a_examiner` / passées en `surveillance` | **20** / **19** |
| Malignes parmi les décisions changées | **1** (`ISIC_1480614`, qui passe de `surveillance` à `a_examiner`) |
| Rapport des probabilités int8 / PyTorch : médiane, minimum, maximum | **0,997**, **0,252**, **4,185** (moyenne 1,076, écart-type 0,43) |

Le rapport ONNX float32 / PyTorch, lui, reste entre 0,99998 et 1,00002.

**Question 3.1** — Oui : `comparer.py` mesure un rappel de **0,8983** (53 / 59) pour PyTorch, contre **0,9153** dans le meta. La maligne responsable est **`ISIC_0521019`**, la même qu'à la question 4.1 de S4. Sa probabilité recalculée par `comparer.py` vaut le seuil moins **3,6 × 10⁻¹⁰** (moins 1,5 × 10⁻⁹ avec ONNX) : elle est, par construction, pile sur le seuil (`precision_recall_curve` prend les scores des lésions comme seuils), et le moindre écart de calcul (décodage de l'image, ordre des opérations, aller-retour par un CSV) la fait passer d'un côté ou de l'autre. En S4 c'était l'arrondi du CSV, ici c'est le recalcul de la probabilité à partir de l'image. Conclusion : on ne juge pas une variante sur le **rappel**, qui saute d'une maligne pour un écart de 10⁻¹⁰. On la juge sur les **décisions changées**, lésion par lésion, contre une référence calculée **dans les mêmes conditions** (ici, PyTorch passé dans `comparer.py`). ONNX float32 change 0 décision ; l'int8 en change 39.

**Question 3.2** — Sur mon poste, oui : ONNX float32 est **3,5 fois plus rapide** que PyTorch sur un fil (p50 157 contre 542 ms). Cela ne prouve rien pour B1. Le vCPU de B1 est un autre processeur (Xeon ou EPYC de centre de données), avec un autre jeu d'instructions (AVX-512, VNNI ou non), et ONNX Runtime comme PyTorch choisissent leurs noyaux à l'exécution, selon le processeur ; sur un Mac ARM, l'image amd64 serait même **émulée**. Indice de cet effet : la même image donne 0,066290 sur le portable et 0,066289 sur B1. Le gain qui reste acquis même si la latence n'avait pas bougé concerne ce qu'il faut installer : **plus de PyTorch** pour exécuter le modèle. L'image passe de 1,67 Go à 419 Mo, la mémoire au repos de 578 à 157 Mio, et les dépendances (et leurs CVE) fondent : zéro CVE (mesure 5).

**Question 3.3** — Mes critères, figés à 15:05 avant toute mesure : écart de probabilité au plus 1e-5, rappel d'au moins 0,88, **0** décision changée.
- **ONNX float32** : écart 3e-6, 0 décision changée, rappel égal à celui de PyTorch → **même modèle**, accepté.
- **ONNX int8** : écart 0,23 (23 000 fois la tolérance), **39 décisions changées**. Son rappel (0,9153) dépasse le minimum, mais cela ne suffit pas : il est **refusé**. Ce n'est plus le modèle 2.0.0, c'est un nouveau modèle, qu'il faudrait valider comme tel. Il ne fait d'ailleurs pas gagner de temps (p50 176 contre 157 ms) : sa seule vertu serait la taille.

| Décision de déploiement | Ma valeur |
|---|---|
| Variante déployée | **ONNX float32** (`modele.onnx`, sha256 `c7d89deb11d3b32b…`) |
| Version du modèle servi | **`2.1.0`** : le calcul est celui de 2.0.0 (même `sha256_poids`, 0 décision changée), mais le service change de moteur et son contrat s'enrichit de quatre champs facultatifs, compatibles avec les postes S4. C'est donc une version **mineure** |

**Question 3.4** — Avant de servir à des patients une variante qui change des décisions :
1. **Revalider la performance clinique** de la variante sur un jeu indépendant : rappel et précision au seuil, et, si besoin, **re-choisir le seuil** sur cette variante, puisque ses probabilités ne sont plus celles qui ont fixé 0,000499.
2. **La traiter comme un nouveau modèle dans la documentation et le suivi** : nouvelle version majeure, model card mise à jour (performances, décisions changées), nouvelle référence de surveillance, et revue humaine des cas qui basculent, surtout les malignes.

Aujourd'hui, j'ai fait **partiellement** le premier point : la comparaison des décisions sur les 1 058 vignettes de validation de S4. Ces vignettes ont déjà servi à choisir le seuil : ce n'est donc pas une validation indépendante.

## Partie 4 — Une image sans PyTorch, et un journal

**Question 4.1** — Le diff de `app.py` S4 → S5 compte 116 lignes, sur quatre points :
1. **Moteur** : `torchvision` et `torch.load` sont remplacés par une `onnxruntime.InferenceSession` sur `modele.onnx`, réglée à `ORT_THREADS` fils (1 par défaut) ; le nom de l'entrée est lu dans la session.
2. **Covariables** : quatre champs de formulaire **facultatifs** (`age_approx`, `sex`, `anatom_site_general`, `tbp_tile_type`), contrôlés contre le domaine de `train-metadata.csv`. L'âge n'est jamais gardé brut, mais en tranche de 10 ans. Une valeur hors domaine donne 400, un champ absent est accepté.
3. **Journal** : une ligne JSON par appel sur la sortie standard, au format de S3 (horodatage, `request_id`, version, digest, `patient_ref` = sha256(sel:id) sur 16 caractères, probabilité, seuil, décision, covariables, latence d'inférence, code HTTP, version du schéma d'entrée).
4. **`/model/info`** ajoute `format: onnx`, `fichier_servi`, `sha256_fichier_servi` (l'empreinte du fichier réellement chargé) et `covariables_acceptees`.

**Question 4.2**
- **Contre l'option 1 (surveiller l'API tabulaire de S2)** : c'est un autre modèle, sur un autre flux. Ses entrées ne disent rien de ce que reçoit le CNN servi, et une dérive du centre partenaire qui n'enverrait que des images n'y apparaîtrait jamais.
- **Contre l'option 2 (statistique de l'image)** : une luminance moyenne mélange tout (peau, lésion, appareil, éclairage). Elle n'a pas d'équivalent dans les métadonnées d'entraînement, et elle ne nomme pas la cause : on ne pourrait pas dire « éclairage polarisé », ni voir une dérive d'âge ou de site.
- **Faiblesse de l'option 3** : ces valeurs sont **déclarées par le poste de consultation**, pas mesurées par le service. Si le poste les omet, la surveillance devient aveugle (seul le taux d'absence le signale). S'il ment, par exemple s'il envoie `3D: white` par défaut alors que l'appareil fait du polarisé, la dérive est **invisible**, et le PSI rassure à tort.

**Question 4.3** — Une modalité **inconnue** (`UV`) est une **violation du contrat** : un poste mal configuré ou un nouvel appareil. L'accepter créerait une modalité absente de la référence, que le PSI compterait avec un plancher de 1e-4 : il exploserait, et déclencherait une fausse alerte. Pire, la modalité se mélangerait silencieusement aux autres dans le tableau de bord. Le 400 fait remonter l'erreur tout de suite, à celui qui peut la corriger. Une modalité **absente** est le cas normal d'un poste S4, qui doit continuer de fonctionner (contrat compatible) : elle est journalisée à `null`, suivie à part (`taux_absent`), et le PSI est calculé sur les seules valeurs présentes. Elle ne fausse donc pas les proportions.

**Question 4.4**
1. **Partie 4.3, et 5.3** : la sortie standard est **déjà collectée** par App Service et routée vers Log Analytics par un simple paramètre de diagnostic, sans une ligne de code ni une dépendance. Un SDK ajouterait un client réseau dans le processus, une clé de connexion à gérer comme un secret, et un point de panne de plus sur le chemin de `/predict`.
2. **Zéro CVE** : le SDK Application Insights (OpenTelemetry, azure-core, requests, et leurs dépendances) ajouterait plusieurs dizaines de paquets à l'image. Chacun est une source de CVE future. L'image 2.1.0 passe la porte avec **0 C / 0 H / 0 M / 0 L** sur 107 paquets : chaque paquet évité est une CVE que l'on n'aura pas à justifier.

### 4.2 — Contexte de construction

`api-s5/` : `Dockerfile`, `requirements.txt` et `app.py` distribués, `.dockerignore` de S4 + `**/*.pt`, `model/modele.onnx` (la variante float32), et `model/modele_meta.json` avec `version = "2.1.0"`, `variante = "onnx_fp32"`.

Le Dockerfile distribué repart de la base **Wolfi** (`cgr.dev/chainguard/wolfi-base`, figée par digest) et retire `pip` dans le même `RUN`, comme le Dockerfile de référence de la classe. Mon Dockerfile de S2/S4 était sur Debian (`python:3.12.7-slim-bookworm`) : le diff avec mon S4 dépasse donc le seul `MODEL_PATH` (base, `apk`, retrait de `pip`, `adduser` sans `chown -R`). C'est ce changement de base qui fait passer la porte zéro CVE, ce que l'exception de S4 avait annoncé.

**Question 4.5** — `docker history dermascan-api:2.0.0` : la couche `RUN useradd … && chown -R appuser:appuser /app` pèse **44,9 Mo**, soit exactement le modèle. Un `chown` modifie les métadonnées de chaque fichier, et le système de fichiers en couches **recopie** tout fichier modifié dans la nouvelle couche : placé après `COPY model/`, `chown -R` duplique `modele.pt` (ou `modele.onnx`) dans l'image. Son absence ne casse rien : les fichiers copiés appartiennent à root, mais ils sont **lisibles par tous** (droits 644), et l'API ne fait que **lire** le modèle et le meta. Elle n'écrit rien dans `/app` : son journal va sur la sortie standard. En S5, la couche `adduser` ne pèse que 41 ko.

**Question 4.6** — Dans un `.dockerignore`, `*.pt` ne correspond qu'aux fichiers **à la racine** du contexte : les motifs suivent `filepath.Match` de Go, où `*` ne traverse pas les `/`. `model/modele.pt` entrerait dans l'image. `**/*.pt` correspond à toute profondeur. De même, `*.csv` seul laisserait entrer `model/manifeste_echantillon.csv` (la liste des `isic_id` et des `patient_id` de l'entraînement) et tout `sorties/*.csv`.

### Mesure 5 — l'image S5

| Relevé | Ma valeur |
|---|---|
| Code retour de `docker scout cves --exit-code`, et décompte C / H / M / L | **0**, **0 C / 0 H / 0 M / 0 L** (« No vulnerable package detected », 107 paquets, base `chainguard/wolfi-base:latest` à 0 CVE ; `captures/scout_cves_s5.txt`) |
| Durée de construction | **382 s** (`--pull`, téléchargement d'onnxruntime, numpy et Pillow) |
| `probabilite_maligne` de l'image de contrôle servie par le conteneur | **0,06629** (0,066290 avant l'arrondi d'affichage ; sur B1 : 0,066289) |
| Probabilité de contrôle de la même variante dans la mesure 3, et écart | **0,066290** ; écart **< 1e-6** |
| `sha256_fichier_servi` de `/model/info`, égal à l'empreinte de la variante | **Oui** : `c7d89deb11d3b32b…`, en local comme sur Azure (`captures/model_info_*_s5.json`) |
| Ligne de journal complète d'un appel avec covariables (recopiée) | ci-dessous |
| Le `patient_ref` journalisé contient-il `IP_0000001` en clair ? | **Non** (`ddfef2e438aaa835`, sha256(sel:IP_0000001) sur 16 caractères ; recherche de `IP_0000001` dans `docker logs` : aucune occurrence) |

```json
{"ts": "2026-11-17T15:23:56.541Z", "request_id": "072d4c6a-0769-4af2-9961-d43c872181c1", "model_version": "2.1.0", "image_digest": null, "patient_ref": "ddfef2e438aaa835", "probabilite_maligne": 0.06629, "seuil_applique": 0.0004990625942336154, "rappel_cible": 0.9, "decision": "a_examiner", "covariables": {"age_tranche": "60-69", "sex": "male", "anatom_site_general": null, "tbp_tile_type": "3D: white"}, "inference_ms": 595.8, "http_status": 200, "input_schema_version": "2.0", "env": "local"}
```

En local, `image_digest` vaut `null` : la variable `IMAGE_DIGEST` n'est posée que sur Azure, où la ligne porte bien `sha256:234640972e555596…`. L'appel avec `tbp_tile_type=UV` est refusé : **400**, `{"error":"covariable invalide","detail":"tbp_tile_type inconnu : 'UV'"}`. Un appel sans aucune covariable (un poste S4) reçoit 200.

### Mesure 6 — S4 contre S5, sur mon poste

| Grandeur | S4 | S5 |
|---|---|---|
| Taille de l'image (`docker images` ; Docker Scout) | 1,67 Go ; 404 Mo | **419 Mo ; 125 Mo** |
| Taille du fichier de modèle | 44,8 Mo (`.pt`) | 44,8 Mo (`.onnx` float32) |
| Démarrage jusqu'au premier `/health` à 200 (hors ligne) | 7,3 s | **32,2 s** |
| Mémoire au repos | 577,6 Mio (2 workers) | **156,7 Mio** (1 worker) |
| Latence `/predict` p50 / p95, 50 appels | 27,6 / 43,2 ms (à midi, PyTorch sur 4 fils) | 224,0 / 404,0 ms (l'après-midi, ONNX sur 1 fil) |
| Latence p50 / p95 sous `--cpus 1`, `ORT_THREADS` par défaut (1) | — (même mesure sur l'image S4 : **680,3 / 2 039,8 ms**) | **196,1 / 759,4 ms** |
| Latence p50 / p95 sous `--cpus 1`, `ORT_THREADS=8` | — | **1 057,7 / 1 940,2 ms** |
| Architecture du poste | amd64 natif | amd64 natif |

Lecture honnête : la ligne « sans limite » n'est **pas comparable**. La mesure S4 a été faite à midi, avec PyTorch sur 4 fils ; la mesure S5 l'après-midi, avec ONNX volontairement sur 1 fil, sur un portable visiblement ralenti (la même étape PyTorch à 1 fil coûtait 542 ms dans `comparer.py`). La comparaison juste est celle **à ressources égales, sous `--cpus 1`**, mesurée dans la même minute : **680 ms (S4) contre 196 ms (S5)**, soit 3,5 fois plus rapide, comme dans la mesure 3. Le démarrage hors ligne, plus lent (32 s), a lui aussi été mesuré l'après-midi, sur la même machine chargée. Sur B1, le premier 200 est arrivé **48 s après le restart, contre 345 s en S4** (mesure 10).

**Question 4.7** — Sous `--cpus 1`, le conteneur n'a droit qu'à un cœur de temps de calcul, mais il **voit** les 8 processeurs logiques du portable. Avec `ORT_THREADS=8`, ONNX Runtime découpe chaque convolution en 8 morceaux, confiés à 8 fils qui se disputent un seul cœur : le quota CFS est consommé en quelques millisecondes, puis tout le conteneur est **bridé** jusqu'à la période suivante. S'y ajoutent les changements de contexte et les attentes aux barrières de synchronisation : **5,4 fois plus lent** (1 058 contre 196 ms). `app.py` fixe donc **un fil par défaut**, car un moteur qui se règle sur le nombre de cœurs visibles se trompe dès qu'un quota limite le conteneur. Ce réglage compte partout où un conteneur tourne sous quota : sur **B1** (un vCPU), sur **Azure Container Instances** (annexe B de S3, où l'on alloue 1 vCPU par conteneur), et au **projet**, sous Kubernetes, où les `limits: cpu` jouent exactement le rôle de `--cpus`.

## Partie 5.4 — Le plan tient-il, maintenant ?

Mêmes paliers qu'en S4 (`locustfile_s4.py` inchangé, image de contrôle en multipart, 3 minutes, montée à 5 par seconde), sur le B1 `plan-dermascan-s5-sm26`, juste après le rejeu de la dérive.

### Mesure 11 — S4 contre S5 sur B1, mêmes paliers

| Palier | S4 : débit, p50, p95 (mesure 19) | S5 : débit, p50, p95 | S5 : CPU max du plan |
|---|---|---|---|
| 1 (10 utilisateurs) | 2,93 req/s, **1 400 ms**, **3 500 ms** (CPU 98-100 %) | 4,70 req/s (3,82 `/predict`), **130 ms**, **250 ms**, 0 échec | **26 %** |
| 2 (50 utilisateurs) | 5,98 req/s, **3 500 ms**, **17 000 ms** (CPU 98-100 %) | **18,0 req/s** (14,2 `/predict`), **540 ms**, **2 500 ms**, 0 échec | **96 %** |

Mémoire du plan : 73 à 78 % pendant toute la séance (contre 80 à 88 % sous charge en S4).

**Question 5.7** — Oui, l'engagement de S3 tient à nouveau : « jusqu'à **10** utilisateurs, 95 % des prédictions en moins de **530 ms**, moins de 1 % d'échecs ». À 10 utilisateurs, le p95 de `/predict` est de **250 ms**, avec 0 échec sur 677 prédictions et le CPU à 26 %. À 50, il ne tient pas (p95 2 500 ms, CPU à 96 %) : comme en S3, le plan sature entre 10 et 50 utilisateurs, mais à un débit trois fois supérieur (14,2 prédictions par seconde contre 4,5 en S4). **Tout le gain revient au moteur**, puisque la variante int8 n'a pas été retenue. La mesure 6 l'attribue : à un seul processeur, ONNX Runtime fait la même inférence en 196 ms contre 680 ms pour PyTorch, avec 3,7 fois moins de mémoire, et l'image démarre sur B1 en 48 s au lieu de 345 s. L'int8 n'aurait rien ajouté en latence (mesure 3) ; il aurait seulement divisé la taille du fichier par quatre, au prix de 39 décisions changées.
