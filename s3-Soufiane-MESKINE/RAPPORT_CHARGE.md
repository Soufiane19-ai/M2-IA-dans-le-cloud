# Rapport de charge — API DermaScan sur App Service B1

Soufiane Meskine, M2 YNOV Montpellier, 26/10/2026. Cible : `https://app-dermascan-sm26.azurewebsites.net`, une instance **B1** (1 vCPU, 1,75 Go), France Central, image `dermascan-api:1.0.0` lancée par gunicorn en `--workers 2 --threads 4 --worker-class gthread`. Locust **2.47.0** (Python 3.14.8), exécuté sur mon portable Windows depuis le réseau Wi-Fi de l'établissement.

Pièces jointes, non retouchées : `palier1_stats.csv` … `palier4_stats.csv`, `palier1.html` … `palier4.html`, ainsi que les `*_failures.csv` et `*_stats_history.csv` produits par Locust. Captures : `captures/locust_palier2.png`, `captures/locust_palier4.png`.

## 5.1 — Scénario (`locustfile.py`)

| Décision | Ma valeur |
|---|---|
| Temps de réflexion | `between(1, 3)` secondes |
| Poids de `/predict`, `/health`, `/model/info` | **8, 1, 1** (80 % / 10 % / 10 %) |
| Variables perturbées et amplitude | `age_approx` ± {0, 5, 10} ans, borné à 25–85 ; facteur commun *f* tiré dans [0,8 ; 1,2] appliqué à `clin_size_long_diam_mm` (× *f*, borné à 2,39–10,95 mm), `tbp_lv_perimeterMM` (× *f*, 6,39–35,95 mm) et `tbp_lv_areaMM2` (× *f*², 2,14–50,2 mm²). Les bornes sont les 1er et 99e percentiles de `train-metadata.csv` (S2) : la lésion grossit ou rétrécit de façon cohérente et reste dans le domaine du modèle |

`charge.json` (la lésion réelle de S2, 40 variables) est lu **une fois** au chargement du module. `/predict` est appelé avec `catch_response=True` : succès si et seulement si le code est 200. Contrôle avant le premier palier : une charge perturbée renvoie **200** (`{"decision":"a_examiner","probabilite_maligne":0.699456,…}`).

**Ajout imposé par le réseau.** Chaque utilisateur Locust ouvre d'abord sa connexion par un `GET /health` nommé à part, `0. ouverture connexion TLS` (méthode `on_start`). Sur ce réseau, ouvrir une connexion HTTPS coûte ≈ 19 s (voir « Honnêteté de la mesure ») ; la session Locust la garde ensuite ouverte (keep-alive). Sans cette ligne séparée, les 19 s de chaque utilisateur se mélangeraient aux temps de `/predict`.

**Question 5.1**
- **`/predict` = 8** : c'est le geste métier. Un dermatologue soumet les lésions d'un patient les unes après les autres, et un examen corporel total en produit des dizaines à des centaines.
- **`/health` = 1** : le poste de consultation vérifie que le service répond, à l'ouverture de l'application et de temps en temps, pas avant chaque lésion.
- **`/model/info` = 1** : la version du modèle et ses colonnes s'affichent dans l'interface (traçabilité) au début d'une session ; c'est une lecture rare. Les deux GET restent présents pour ne pas mesurer un service qui ne ferait que prédire.

## 5.2 — Paliers et Mesure 13

Quatre paliers de 3 minutes, sans interface : `locust -f locustfile.py --host "$APP_URL" --users N --spawn-rate R --run-time 3m --headless --csv paliern --html paliern.html`.

| Palier | `--users` | `--spawn-rate` | Fichiers produits |
|---|---|---|---|
| 1 | 10 | 2 | `palier1_stats.csv`, `palier1.html` |
| 2 | 50 | 5 | `palier2_*` |
| 3 | 150 | 10 | `palier3_*` |
| 4 | 300 | 20 | `palier4_*` |

**Mesure 13** — ligne `Aggregated` de chaque `paliern_stats.csv` (elle inclut la ligne « ouverture connexion TLS »).

| Palier | Utilisateurs | Débit (req/s) | p50 (ms) | p95 (ms) | p99 (ms) | Taux d'échec (%) | Échecs les plus fréquents |
|---|---|---|---|---|---|---|---|
| 1 | 10 | 4,16 | 77 | 540 | 19 000 | 0,00 (0 / 729) | aucun |
| 2 | 50 | 12,15 | 640 | 6 200 | 36 000 | 0,52 (11 / 2 127) | `502 Bad Gateway` : 10 sur `POST /predict`, 1 sur `GET /health` |
| 3 | 150 | 15,08 | 1 800 | 20 000 | 127 000 | 0,19 (5 / 2 677) | `502 Bad Gateway` : 5 sur `POST /predict` |
| 4 | 300 | 9,66 | 4 700 | 56 000 | 135 000 | 0,47 (8 / 1 692) | `502 Bad Gateway` : 7 sur `POST /predict`, 1 sur `GET /health` |

Les p99 agrégés (19 à 135 s) sont ceux des **ouvertures de connexion TLS**, pas des prédictions. La ligne `POST /predict` des mêmes fichiers donne la latence du geste métier, connexion déjà ouverte :

| Palier | Requêtes `/predict` | Débit `/predict` (req/s) | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Ouverture TLS, médiane (s) | Utilisateurs ayant réellement ouvert leur connexion |
|---|---|---|---|---|---|---|---|---|
| 1 | 572 | 3,26 | 83 | 530 | 1 500 | 2 776 | 19 | 10 / 10 |
| 2 | 1 670 | 9,54 | 680 | 4 300 | 8 200 | 9 640 | 36 | 50 / 50 |
| 3 | 2 003 | 11,28 | 1 800 | 6 800 | 10 000 | 12 648 | 89 | **137 / 150** |
| 4 | 1 249 | 7,13 | 4 300 | 12 000 | 15 000 | 16 615 | 93 | **128 / 300** |

Débit en régime établi (dernière minute de chaque palier, `*_stats_history.csv`) : 4,5 ; **17,5** ; **18,7** ; 10,7 req/s.

Les rapports HTML ont été générés à la fermeture de Locust et comptent quelques requêtes de plus que les CSV (2 140 contre 2 127 au palier 2) : sous Windows, l'écrivain CSV de Locust 2.47 s'est arrêté sur `ValueError: I/O operation on closed file` à la fermeture, quelques secondes avant la fin. Les valeurs du tableau sont celles des CSV, comme demandé.

**Mesure 14 — ligne de base réseau**

`curl -s -o NUL -w "%{time_connect}" "$APP_URL/health"` répété 20 fois à 16:16 (`logs/mesure14.txt`), avec en plus `time_appconnect` (fin de la poignée de main TLS).

| Ligne de base | Ma valeur |
|---|---|
| Temps d'établissement de connexion, médiane sur 20 mesures | **108,4 ms** (min 63,2 ; max 187,3 ms). Ce temps inclut la résolution DNS ; la connexion TCP seule prend quelques ms. La poignée de main TLS qui suit prend **19,16 s** en médiane (18,85 à 19,28 s) |
| Part que cela représente dans mon p50 du palier 1 | **0 % en pratique** : les requêtes du palier réutilisent la connexion ouverte par `on_start`, donc le p50 de 77 ms ne contient aucun établissement de connexion. Si chaque requête ouvrait sa propre connexion, `time_connect` seul pèserait 108 / 77 = **141 %** du p50, et avec le TLS du réseau de l'école la requête durerait ≈ 250 fois le p50 : c'est exactement ce que mesuraient les curl des parties 2 à 4 |

Il reste un aller-retour réseau dans chaque requête (quelques ms vers Paris d'après la part TCP de `time_connect`), négligeable devant les 77 ms du p50.

## Honnêteté de la mesure : ce qui n'appartient pas au service

1. **L'ouverture de connexion TLS (≈ 19 s), entièrement imputable au réseau de l'établissement.** Mesuré par `curl -w` (`logs/diag_s3.log`) : résolution DNS 0,04 à 0,13 s, connexion TCP + 0,005 s, **poignée de main TLS 19 s**, réponse 0,03 s. La même requête en HTTP simple prend 0,17 s, et une requête sur une connexion déjà ouverte 24 à 58 ms. Curl, Python et PowerShell subissent le même délai, et désactiver la vérification de révocation du certificat ne change rien : c'est l'équipement réseau entre le poste et Azure (inspection TLS probable) qui retient chaque nouvelle connexion. Côté serveur, la plateforme mesure 52 ms de temps de réponse moyen au même moment.
2. **Cet équipement limite aussi la charge que je peux produire.** Il traite les ouvertures de connexion à la file : aux paliers 3 et 4, les utilisateurs ont attendu jusqu'à **159 s** pour ouvrir leur connexion. Au palier 4, seuls **128 des 300 utilisateurs** ont envoyé ne serait-ce qu'une requête : ce palier n'a **pas** mesuré 300 utilisateurs simultanés, mais au plus 128. Au palier 3, 137 sur 150.
3. **Une fois les connexions ouvertes, la dégradation est bien celle du serveur.** Le temps de réponse mesuré **par la plateforme** (`HttpResponseTime`, par minute) passe de 0,05 à 0,15 s au palier 1, à 2 s au palier 2, puis 2,9 à 5,0 s au palier 4 ; dans le même temps, le CPU du plan monte jusqu'à 98-100 %. Les p95 et p99 de `/predict` ci-dessus sont donc, à quelques dizaines de millisecondes près, ceux du service.

## 5.3 — Critère de rupture et Mesure 15

Les quatre paliers ont été enchaînés par un script, avant que j'aie formalisé ce critère. Je l'ai donc fixé à partir de l'usage, pas de l'allure des courbes, et je le tiens même s'il est sévère. Il porte sur `POST /predict`, le geste du praticien, pour ne pas mesurer le réseau de l'école :

| Élément du critère | Mon choix | Justification en une ligne |
|---|---|---|
| Seuil de taux d'échec jugé inacceptable | **1 %** | Au-delà, un dermatologue qui soumet 100 lésions par patient voit au moins une erreur par patient : il doit ressoumettre, et peut en oublier une |
| Seuil de p95 jugé inacceptable | **5 fois** le p95 du palier 1 (5 × 530 ms = 2,65 s) | Au-delà de 2 à 3 s, la réponse n'est plus « immédiate » pendant la consultation : le praticien attend à l'écran une lésion sur vingt |
| Le point de rupture est atteint quand | **l'un des deux critères** | Une erreur ou une attente excessive suffit à dégrader la consultation |

| Conclusion | Ma réponse |
|---|---|
| Palier où le critère est franchi pour la première fois | **Palier 2 (50 utilisateurs)** : p95 de `/predict` = 4 300 ms > 2 650 ms. Le taux d'échec (0,6 % sur `/predict`) reste, lui, sous 1 % à tous les paliers |
| Nombre d'utilisateurs simultanés supporté, borné entre deux paliers | **Entre 10 et 50** |
| Débit maximal observé avant dégradation | **4,2 req/s** (palier 1, 3,3 prédictions/s). Le plafond de débit du service, atteint une fois dégradé, est d'environ **18 à 21 req/s** (paliers 2 et 3, dernière minute) : au-delà, le débit n'augmente plus, il baisse (10,7 req/s au palier 4) |
| Ressource qui sature en premier | **Le CPU du plan** (moyennes par minute) : 25-28 % au palier 1, jusqu'à 73 % en fin de palier 2, 44-98 % au palier 3 et 43-**100 %** au palier 4 ; la mémoire reste stable à 77-80 % du palier 1 au palier 3 (dernier point relevé) |
| Ce que valait `Http5xx` au palier le plus chargé | **12** réponses 5xx côté plateforme sur les 4 minutes du palier 4 (11:37-11:40 UTC : 4, 0, 1, 7) ; Locust a compté **8** `502 Bad Gateway`. Sur toute l'heure de la charge : 25 réponses 5xx pour 7 082 requêtes |

Les `502 Bad Gateway` viennent du frontal d'App Service, qui n'a pas obtenu de réponse valide du conteneur. Les logs du conteneur n'ont pas été archivés après la charge, donc leur cause exacte n'est pas établie (hypothèses : connexions du frontal réinitialisées par des workers occupés, ou recyclage de worker). Ce sont des refus de service, pas des erreurs du modèle : aucune réponse 400 ou 500 de l'API n'a été comptée.

**Question 5.2** — Au palier le plus chargé, `/predict` a un p50 de 4,3 s et un p99 de 15 s, soit un rapport de 3,5 : la latence typique est déjà mauvaise et la queue est longue. Ce n'est pas un problème de quelques requêtes isolées (un écart faible avec un p50 élevé signalerait un serveur uniformément lent), mais une **file d'attente** sur un CPU saturé : chaque requête attend celles qui la précèdent. En consultation, le praticien subit ce p99 sur **1 % des lésions**, soit environ **une lésion par patient** d'un examen corporel total d'une centaine de lésions, et il attend au moins 4 s sur une lésion sur deux.

**Question 5.3** — « **Jusqu'à 10 utilisateurs simultanés, 95 % des prédictions sont rendues en moins de 530 ms, avec moins de 1 % d'échecs** (0 échec sur 572 prédictions mesurées) », hors ouverture de la connexion, sur une instance B1. Cet engagement s'appuie sur le palier 1, le seul qui respecte mon critère.

**Question 5.4** — Les deux options : **mise à l'échelle verticale (scale up)**, passer le plan sur un SKU plus puissant (B2/B3, ou P1v3) avec plus de vCPU, et augmenter en conséquence le nombre de workers gunicorn ; **mise à l'échelle horizontale (scale out)**, augmenter le nombre d'instances du plan (`az appservice plan update --number-of-workers 2`), le frontal répartissant les requêtes entre elles. Je testerais d'abord le **scale out** : la ressource saturée est le CPU d'une instance mono-processeur, et doubler les instances double le CPU disponible pour une charge doublée, sans changer l'image ni la configuration de gunicorn. Il apporte en plus une redondance (une instance tombe, l'autre sert) et se teste en un réglage, sur le B1 lui-même (3 instances au plus). À ne pas oublier : chaque instance est facturée, donc le coût double.

**Question 5.5** — Recharger le modèle à chaque requête ajouterait à **chaque** `/predict` la lecture du fichier joblib et la reconstruction du pipeline scikit-learn, donc une latence fixe. Le premier effet visible serait sur le **p50** (et tous les percentiles) de `/predict` dès le palier 1, puisque toutes les requêtes paient ce coût, pas seulement quelques-unes. Le débit des paliers non saturés ne bougerait presque pas, car dans un test à utilisateurs fermés il est fixé par la cadence des utilisateurs : chacun envoie une requête puis attend 1 à 3 s, soit au palier 1 environ 10 / (2 s + latence) ≈ 4,5 req/s, que la réponse prenne 0,1 s ou 0,3 s. Le débit ne baisse que lorsque le CPU sature. En revanche, le point de rupture arriverait plus tôt, puisque chaque requête consommerait plus de CPU.
