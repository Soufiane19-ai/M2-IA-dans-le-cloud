# Surveillance — Séance 5

Soufiane Meskine, M2 YNOV Montpellier, 17/11/2026. Seuils, fenêtre et leviers fixés à 15:05, avant toute mesure (`JOURNAL.md`) : PSI, alerte **0,25**, surveillance **0,10**, fenêtre de **200** inférences, covariable prioritaire `tbp_tile_type`, leviers `eclairage` puis `age`.

## 5.1 — La distribution de référence

`python derive.py reference model/manifeste_echantillon.csv donnees/train-metadata.csv > reference_covariables.json`

### Mesure 7 — la référence

| Covariable | Modalités et proportions | Taux d'absence |
|---|---|---|
| `tbp_tile_type` | `3D: white` **52,90 %**, `3D: XP` **47,10 %** | 0 % |
| `age_tranche` (les trois plus fréquentes) | `60-69` 34,45 %, `50-59` 23,44 %, `70-79` 17,31 % (puis 40-49 11,86 %, 30-39 6,37 %, 80-89 5,04 %, 20-29 1,52 %) | 0,71 % |
| `anatom_site_general` (les deux plus fréquentes) | `posterior torso` 30,75 %, `lower extremity` 26,09 % (puis anterior torso 20,93 %, upper extremity 18,33 %, head/neck 3,89 %) | 1,75 % |
| `sex` | `male` 70,71 %, `female` 29,29 % | 1,58 % |
| Nombre de vignettes de la référence | **4 236** (jeu `entrainement` du manifeste de S4) | — |

**Question 5.1** — Ma mesure 20 donnait 55,23 % de `3D: white` sur le **manifeste entier** (5 294 vignettes) ; la référence n'en compte que **52,90 %**, car elle ne garde que le **jeu d'entraînement** (4 236 vignettes) : les 1 058 vignettes de validation, choisies par patient, sont plus souvent en lumière blanche. Le bon choix est le jeu d'entraînement, parce que la question posée par la surveillance est « le flux ressemble-t-il à **ce que le modèle a appris** ? ». La validation n'a rien appris au modèle, et l'**archive** (217 477 vignettes, dont 99,9 % de négatifs jamais vus) décrit une population que le réseau n'a pas rencontrée telle quelle. Elle est d'ailleurs très proche : 52,73 % de lumière blanche.

**Question 5.2** — Flux composé comme le `train-metadata.csv` complet de S2 (mesure 20 : 28,71 % `3D: white`, 71,29 % `3D: XP`) :

PSI = (0,2871 − 0,5290) × ln(0,2871 / 0,5290) + (0,7129 − 0,4710) × ln(0,7129 / 0,4710)
= (−0,2419) × (−0,6111) + (0,2419) × (0,4146) = 0,1478 + 0,1003 = **0,248**

C'est **juste sous mon seuil d'alerte de 0,25**, et au-dessus de mon seuil de surveillance de 0,10. Un flux qui serait passé de 47 % à 71 % d'éclairage polarisé, soit la composition réelle du jeu complet d'ISIC, **n'aurait pas déclenché l'alerte**. Le seuil usuel de 0,25 est calibré pour des variables à beaucoup de modalités. Sur une variable binaire, il faut un déplacement énorme pour l'atteindre (ici, près de 25 points). Pour la covariable prioritaire, il faudrait donc soit un seuil propre plus bas (0,15 par exemple), soit traiter le dépassement du seuil de surveillance comme une alerte. Je garde 0,25 pour cette séance, puisqu'il était décidé avant, mais c'est la leçon à reporter au projet.

## 5.2 — Répétition locale : flux conforme, puis dérive

Conteneur `dermascan-api:2.1.0` relancé à journal vierge, sel aléatoire. `rejouer_flux.py` est exécuté dans le conteneur d'outils, vers `http://host.docker.internal:8000`. Puis `docker logs` → `journal_local.jsonl` → `derive.py mesurer reference_covariables.json journal_local.jsonl 200 0.25`.

- Conforme : 400 appels, `{200: 400}`, `a_examiner` 99 (24,8 %).
- Dérive `eclairage` (uniquement `3D: XP`) : 400 appels, `{200: 400}`, `a_examiner` 85 (21,2 %).

### Mesure 8 — la dérive provoquée, en local (levier `eclairage`)

| Covariable | PSI max en flux conforme | PSI de la dernière fenêtre | Délai d'alerte (inférences après le début de la dérive) |
|---|---|---|---|
| `tbp_tile_type` | 0,0052 | **4,9333** | **82** |
| `age_tranche` | 0,1146 | 0,1224 | aucune alerte |
| `anatom_site_general` | 0,0585 | 0,0366 | aucune alerte |
| `sex` | 0,0294 | 0,0012 | aucune alerte |
| Taux de `a_examiner` : flux conforme / flux dérivé | **24,75 % / 21,25 %** | | |

La dernière fenêtre ne contient que des vignettes `3D: XP` : PSI = (1 − 0,471) × ln(1 / 0,471) + (10⁻⁴ − 0,529) × ln(10⁻⁴ / 0,529) = 0,398 + 4,535 = 4,933, ce qui confirme le calcul du script.

### Mesure 9 — second levier

Conteneur redémarré (journal vierge), même flux conforme, puis dérive `age` (`age_approx >= 70`) : 400 appels, `{200: 399, ConnectTimeout: 1}`, `a_examiner` 121 (30,3 %). Journal : `journal_local_age.jsonl`.

| Relevé | Ma valeur |
|---|---|
| Levier | **`age`** (patients de 70 ans et plus) |
| Covariable qui alerte, et délai | **`age_tranche`**, **52** inférences après le début de la dérive (PSI de la dernière fenêtre : 7,11) |
| Autre covariable qui bouge sans alerter, et son PSI | **`sex`** : PSI **0,111** sur la dernière fenêtre (0,029 au plus en flux conforme), au-dessus du seuil de surveillance. Chez les plus de 70 ans de l'archive, la part des hommes change |
| Taux de `a_examiner` : flux conforme / flux dérivé | **24,75 % / 30,33 %** |

**Question 5.3**
- **Éclairage** : le taux de `a_examiner` passe de 24,8 % à 21,2 %. Sur une fenêtre de 200 appels, l'écart-type d'une proportion de 25 % vaut environ 3 points : un tableau de bord qui ne suivrait que la sortie **n'aurait rien vu**. Le service continue de répondre 200, avec des probabilités d'allure normale, alors que le PSI de l'entrée vaut **4,9**, vingt fois le seuil d'alerte.
- **Âge** : la sortie bouge davantage (24,8 % → 30,3 %), dans le sens attendu (les lésions des personnes âgées sont plus souvent suspectes), mais l'écart reste à la limite du bruit d'une fenêtre. Seule l'entrée (PSI 7,1) dit **pourquoi**.

Il faut surveiller **les entrées et la sortie**. Les entrées détectent tôt et nomment la cause : quelle population a changé. La sortie dit si le changement a un **effet** sur les décisions, et elle capte ce que les covariables ne voient pas (une dérive de l'image elle-même, des covariables omises ou fausses).

**Question 5.4** — Oui : **`age_tranche`** a atteint **0,1146** pendant le flux conforme, au-dessus de mon seuil de surveillance de 0,10. Ce n'est **pas une dérive**, puisque le flux est tiré uniformément dans l'archive : c'est du **bruit d'échantillonnage**. Avec **7 modalités** (plus l'absence) dans une fenêtre de seulement **200** inférences, les tranches rares (`20-29` à 1,5 %, soit 3 appels attendus par fenêtre ; `80-89` à 5 %) fluctuent fortement d'une fenêtre à l'autre. Chaque modalité contribue au PSI par un terme toujours positif, et le PSI d'une variable à k modalités a un biais de l'ordre de (k − 1) / n sous l'hypothèse nulle. L'éclairage (2 modalités) ne dépasse jamais 0,005. Plus de modalités ou une fenêtre plus petite font monter ce plancher de bruit.

**Question 5.5** — Avec une fenêtre de **100** au lieu de 200 : le **délai d'alerte serait divisé par deux** (environ 46 inférences au lieu de 92), mais le bruit d'échantillonnage du flux conforme doublerait environ. `age_tranche` dépasserait régulièrement 0,10 et pourrait approcher 0,25, d'où des **fausses alertes**. Le compromis : une fenêtre courte détecte plus vite mais crie plus souvent au loup, une fenêtre longue est fiable mais tardive.

Délai théorique pour l'éclairage : une fenêtre qui contient une fraction f de vignettes de dérive (100 % `3D: XP`) a pour composition `XP` = 0,471 + f × 0,529. Le PSI atteint **0,25 pour f ≈ 0,46** (calcul : `f = 0,46` donne 0,251). Il faut donc **46 % de la fenêtre**, soit **92 inférences** sur 200. Le seuil de surveillance de 0,10 serait franchi à f ≈ 0,30, soit 60 inférences. Mesuré : 82 en local et 97 sur Azure, autour de la valeur théorique, à l'aléa de composition de la fenêtre conforme près.

## 5.3 — Sur Azure : déployer, brancher Log Analytics, rejouer, tracer

Image `acrdermascansm26.azurecr.io/dermascan-api:2.1.0` poussée en 49 s, digest `sha256:234640972e55559668f437f997bef1a9da0fe103d54e0fb7f86baebc0edf250b`. Le registre contient désormais **1.0.0, 2.0.0 et 2.1.0**.

Groupe `rg-dermascan-s5-sm26` (étiquettes `projet=dermascan seance=s5 a_detruire=2026-11-17`), plan B1, application `dermascan-api-s5-sm26`, identité managée avec `AcrPull` sur le registre, `IMAGE_DIGEST` et `INFERENCE_LOG_SALT` en réglages. Le sel est généré par le script et n'est jamais écrit dans un journal. Premier 200 **48 s** après le restart (codes `000 200`), contre 345 s en S4.

Espace `law-dermascan-s5-sm26` (rétention **30 jours**, le minimum de l'offre par Go) et paramètre de diagnostic `diag-dermascan-s5` avec les catégories **`AppServiceConsoleLogs`** et `AppServiceHTTPLogs`. Le conteneur a été recyclé **50 s** après le paramètre de diagnostic (hostname `8add04121a0c` → `857995426f91`) ; aucun appel n'a été envoyé avant ce changement.

Rejeu à débit fixe (1 req/s) : 600 appels conformes de 16:16:34 à 16:27:48 UTC (`{200: 600}`, `a_examiner` 26,0 %), puis 600 appels de dérive `eclairage` à partir de **16:27:48 UTC** (17:27:48 heure de Paris).

> **Incident pendant le rejeu.** Le Wi-Fi du poste a été coupé pendant environ une heure, au milieu de la phase de dérive. Résultat : **355 appels réussis et 245 perdus** (`ConnectionError`), en deux tronçons, de 16:27 à 16:35 UTC puis de 17:45 à 17:47 UTC. `rejouer_flux.py` a continué sans s'arrêter, comme prévu par son `try/except`. 355 appels dérivés restent plus que la fenêtre de 200 : la détection est mesurable. Mais la phase de dérive n'a pas couvert plusieurs fenêtres de 5 minutes consécutives, comme le voulait l'énoncé.

Tableau de bord : les requêtes 1 à 4 (`requetes.kql`, proportions de la requête 3 remplacées par les miennes : 0,529037 et 0,470963, seuil 0,25) ont été exécutées dans l'espace. Je n'ai **pas trouvé l'action « Épingler »** dans la nouvelle interface Journaux du portail : elle n'est ni dans « Partager », ni dans « Enregistrer », ni dans « … ». Les captures sont donc celles des trois graphiques dans l'éditeur de requêtes (`captures/requete2_composition_eclairage.png`, `requete3_psi_eclairage.png`, `requete4_sortie_modele.png`). Une ressource `Microsoft.Portal/dashboards` a bien été créée pendant les essais, dans le groupe de séance, mais sans les tuiles. Les valeurs des requêtes 3 et 4 sont aussi exportées en texte dans `logs/sortie_s5_azure.log`. Sur la capture de la requête 3, l'échelle est écrasée par la série `appels` ; les valeurs du PSI sont dans le tableau ci-dessous.

Requête 3, PSI de l'éclairage par fenêtre de 5 minutes (UTC) :

| Fenêtre | PSI | Appels avec `tbp_tile_type` | Contenu |
|---|---|---|---|
| 16:10 | 4,28 | 1 | appel témoin seul (`3D: white`) |
| 16:15 | 0,0018 | 140 | conforme |
| 16:20 | 0,0001 | 300 | conforme |
| 16:25 | 0,0443 | 224 | conforme, puis début de la dérive à 16:27:48 |
| **16:30** | **4,9333** | 226 | dérive |
| 17:45 | 4,9333 | 65 | dérive (après la coupure) |

### Mesure 10 — la surveillance en ligne

| Relevé | Ma valeur |
|---|---|
| Délai entre un appel et son apparition dans Log Analytics | **≈ 4 min 47 s** (appel témoin `temoin-s5-0001` à 16:11:47 UTC, trouvé par la requête au 7e passage, 287 s plus tard ; requêtes toutes les 30 à 40 s) |
| Nombre de lignes exportées / nombre d'appels envoyés | Rejeu : **956 / 956** appels réussis (600 conformes + 355 dérivés + le témoin), tous présents. 245 appels de dérive n'ont jamais atteint le service (coupure Wi-Fi). L'export de 3 505 lignes contient aussi 2 549 des 3 217 prédictions de Locust : les dernières n'étaient pas encore ingérées au moment de l'export (18:55 heure de Paris, une minute après la charge) |
| PSI de l'éclairage par fenêtre de 5 min, phase conforme (min – max) | **0,0001 – 0,0018** (fenêtres entièrement conformes), 0,044 pour la fenêtre 16:25, qui contient le début de la dérive |
| Première fenêtre de 5 min au-dessus du seuil d'alerte, et heure de début de la dérive | Fenêtre **16:30 UTC** (PSI 4,93) ; dérive commencée à **16:27:48 UTC** |
| Délai d'alerte de `derive.py` sur le journal Azure (inférences) | **97** (`max en flux conforme` 0,0303) |
| Capture du tableau de bord (requêtes 2, 3, 4) dans `captures/` | Graphiques des requêtes 2, 3 et 4 dans l'éditeur Log Analytics (épinglage introuvable, voir ci-dessus) |

**Question 5.6** — Entre le premier patient « dérivé » et l'humain qui voit l'alerte, le délai total additionne :
1. **Le délai statistique** : il faut que la fenêtre se remplisse assez de cas dérivés pour franchir le seuil. C'est environ 92 inférences pour l'éclairage (question 5.5), soit plusieurs minutes, voire des heures à faible trafic.
2. **Le délai d'ingestion** : la ligne de journal passe de la sortie standard à App Service, puis à Log Analytics. Ici, environ 5 minutes.
3. **Le délai d'agrégation** : la requête 3 travaille par fenêtres de 5 minutes. Une alerte n'apparaît qu'une fois la fenêtre close et requêtée, jusqu'à 5 minutes de plus.
4. **Le délai humain** : quelqu'un doit regarder le tableau de bord. Sans alerte automatique, ce délai est illimité.

Sans rien changer au seuil, je peux réduire le **délai humain**, avec une **règle d'alerte Azure Monitor** qui évalue la requête 3 toutes les 5 minutes et envoie un courriel (annexe C). C'est le terme le plus long et le plus incertain. On peut aussi raccourcir le pas d'agrégation, de 5 à 1 minute.

## Nettoyage — Mesure 12

`nettoyage_s5.ps1` (journal `logs/nettoyage_s5.log`), lancé à 19:14 heure de Paris. L'archive des logs App Service est sauvegardée, l'attribution `AcrPull` supprimée, l'espace Log Analytics **supprimé définitivement** (`--force`, sans corbeille de 14 jours), le groupe détruit (le nom est vérifié par `-notlike 'rg-dermascan-s5-*'`).

| Contrôle | Mon observation |
|---|---|
| Nombre et types de ressources du groupe avant destruction | **4** : `plan-dermascan-s5-sm26` (`Microsoft.Web/serverFarms`), `dermascan-api-s5-sm26` (`Microsoft.Web/sites`), `law-dermascan-s5-sm26` (`Microsoft.OperationalInsights/workspaces`), et un tableau de bord partagé (`Microsoft.Portal/dashboards`, créé pendant les essais d'épinglage) |
| `az group exists` sur le groupe de séance | `true` de 19:15:33 à 19:16:26, puis **`false`** à 19:16:45 (≈ 75 s après la demande) |
| Le groupe du registre est-il toujours là ? Tags du dépôt `dermascan-api` | **Oui** (`az group exists` → `true`, `acrdermascansm26` en `Succeeded`, aucune attribution restante) ; tags **`1.0.0`, `2.0.0`, `2.1.0`** |
| Le tableau de bord partagé survit-il à la destruction du groupe ? Ses graphiques affichent-ils encore quelque chose ? | **Non** : il avait été créé **dans** le groupe de séance, et il a disparu avec lui (la liste des `Microsoft.Portal/dashboards` de l'abonnement est vide après le nettoyage). Il ne contenait de toute façon aucune tuile |
| Crédit restant, et écart avec la séance 4 | **84 € sur 90 €**, coûts de novembre **2,64 €** (page Education, 19:30 ; `captures/credit_education_s5.png`). Fin de S4 : 84 € sur 90 €, 2,59 € en novembre. L'écart affiché n'est que de **0,05 €** : la facturation d'Azure a plusieurs heures de retard, et environ 2 h 10 de plan B1 (≈ 0,03 €), plus l'ingestion de quelques Mo dans Log Analytics, restent à venir |

En local : aucun conteneur de la séance ne reste (`docker ps -a`), et l'environnement Locust est supprimé. Les images `dermascan-api:1.0.0`, `2.0.0` et `2.1.0` sont gardées pour le projet (pas de `docker system prune -a`).

**Question 6.1** — Un tableau de bord épinglé **hors** du groupe de séance survit à sa destruction, mais ses tuiles sont des requêtes **vers un espace Log Analytics qui n'existe plus** : elles affichent une erreur (ressource introuvable) ou rien du tout. Le tableau de bord ne stocke pas les données, seulement les requêtes et la cible. Pour que la surveillance survive aux séances, il faudrait garder :
1. **un espace Log Analytics permanent**, dans un groupe durable (comme le registre : `rg-dermascan-supervision-sm26`, jamais détruit), vers lequel chaque nouvelle Web App envoie ses journaux par son paramètre de diagnostic ;
2. **les requêtes versionnées** (`requetes.kql` dans le dépôt, ou un pack de requêtes ou un classeur Azure Monitor dans ce même groupe), et la **référence** (`reference_covariables.json`), qui est la vraie mémoire de la surveillance.

Avec une durée de rétention choisie en conscience : c'est elle qui fixe, à terme, ce qu'on peut encore auditer (S3, partie 6).
