# Journal d'incident et observabilité — Séance 3

Soufiane Meskine, M2 YNOV Montpellier, 26/10/2026. Heures de Paris (UTC+1) ; les lignes de log Azure sont en UTC (11:25 Paris = 10:25 UTC). Archive complète des logs : `logs/logs_s3.zip`.

## Partie 4.1 — Mesure 9 : ce que montre le flux de logs

Journalisation activée par `az webapp log config --docker-container-logging filesystem --application-logging filesystem --level information`, flux ouvert par `az webapp log tail`, puis trafic : un `GET /health`, un `GET /model/info` et un `POST /predict` avec `{"age_approx": 55}` (une variable sur quarante).

| Observation dans le flux de logs | Mon relevé |
|---|---|
| Le nom du conteneur apparaît-il en préfixe de chaque ligne ? | **Non.** Chaque ligne commence par un horodatage UTC, puis, selon le fichier, par la source `ContainerStream:` (sortie du conteneur) ou `ContainerStatus:` (plateforme). Le nom `app-dermascan-sm26` n'apparaît que dans les lignes d'état de la plateforme (`Container app-dermascan-sm26 successfully created and is running.`) |
| Retrouve-t-on la ligne d'accès de Gunicorn pour chaque requête ? | **Oui**, une par requête, y compris celles de la sonde : `169.254.130.1 - - [26/Oct/2026:10:21:21 +0000] "GET /model/info HTTP/1.1" 200 1158 "-" "curl/8.13.0"` ; la sonde apparaît avec l'agent `HealthCheck/1.0`. L'adresse source est celle du frontal interne (`169.254.130.1`), pas celle du poste client |
| Que journalise mon API sur un `/predict` incomplet ? | Uniquement la ligne d'accès : `169.254.130.1 - - [26/Oct/2026:10:21:41 +0000] "POST /predict HTTP/1.1" 400 204 "-" "curl/8.13.0"` (code 400, réponse de 204 octets). L'API n'écrit aucune ligne applicative |
| La liste des variables manquantes apparaît-elle dans les logs ? | **Non.** Elle n'existe que dans le corps de la réponse renvoyée au client : `{"error":"variables manquantes","manquantes":["sex","anatom_site_general",…],"nombre":39}` |
| Délai approximatif entre la requête et l'apparition de sa ligne | **≈ 4 s** (requête à 10:21:41 UTC, ligne reçue par `log tail` à 11:21:45 heure de Paris) |
| La charge utile complète du POST apparaît-elle dans les logs ? | **Non.** Ni la charge incomplète ni les 40 variables d'un `/predict` complet n'apparaissent : seule la ligne d'accès (méthode, chemin, code, taille) est écrite |

Autres lignes notables : `[INFO] Using worker: sync` (configuration de l'image S2) et `[ERROR] Control server error: [Errno 13] Permission denied: '/home/appuser'` à chaque démarrage. Gunicorn 26 essaie d'ouvrir un socket de contrôle dans le répertoire personnel de l'utilisateur non root 10001, qui n'existe pas dans l'image. L'erreur n'empêche pas le service de fonctionner, mais elle pollue les logs ; elle est à corriger dans le Dockerfile (créer le `HOME` de `appuser`).

## Partie 4.2 — Compte rendu d'incident : port de démarrage erroné (panne provoquée)

| Rubrique | Contenu |
|---|---|
| **Résumé** | Service DermaScan indisponible pendant **19 min 10 s** après un changement de configuration : la plateforme sondait le port 9999 alors que le conteneur écoutait sur le port 8000 |
| **Déclenchement** | 11:25:53 : `az webapp config appsettings set --settings WEBSITES_PORT=9999` puis `az webapp restart` (exercice volontaire) |
| **Symptôme côté client** | `curl -m 60 …/health` toutes les 90 s : 7 essais sur 7 en échec. 6 fois `code=000` (aucune réponse en 60 s) et une fois **`503` en 33,6 s** (11:31:01, juste après l'abandon de la sonde). Aucun message n'indique la cause |
| **Ligne de log fautive** (recopiée intégralement, `captures/incident_log.txt`) | `2026-10-26T10:30:53.9396722Z State: Starting, Action: WaitingForSiteWarmUpProbeSuccess, LastError: ContainerTimeout, LastErrorTimestamp: 10/26/2026 10:30:53, LastErrorDetails: Container did not respond to startup probe on port 9999 within the expected time limit of 230s. Port mismatch detected: the container is listening on port 8000 but the platform is probing port 9999. Set the WEBSITES_PORT app setting to match the port your application listens on. If your application needs more time to start, increase WEBSITES_CONTAINER_START_TIME_LIMIT. Please inspect your container logs for more details as this could indicate an issue with your application.` |
| **Cause** | `WEBSITES_PORT` (lu par la plateforme) = 9999 ≠ port d'écoute réel de gunicorn (`PORT`) = 8000. L'application, elle, allait bien : `[INFO] Listening at: http://0.0.0.0:8000 (1)` à 10:27:06 UTC |
| **Correction** | 11:43:23 : `appsettings set WEBSITES_PORT=8000`, **sans** redémarrage explicite (le changement de réglage recycle le conteneur) |
| **Retour au service** | Premier `200` à 11:45:03, soit **100 s** après la correction (codes `000 000 200`) |
| **Leçon** | Le code HTTP ne dit rien de la cause ; seule la ligne `LastErrorDetails` de la plateforme la nomme. Toute modification de port doit changer `WEBSITES_PORT` et `PORT` ensemble, et un déploiement doit lire les logs de la plateforme avant de conclure |

### Mesure 10 — diagnostic de la panne

| Élément du diagnostic | Mon relevé |
|---|---|
| Code HTTP vu par le client | `000` (délai de 60 s dépassé, aucune réponse) dans 6 essais sur 7 ; **`503`** une fois, à 11:31:01 |
| Délai avant la réponse d'erreur | 60 s sans réponse (limite du client) ; 33,6 s pour le 503, dont ≈ 19 s d'ouverture TLS propres au réseau de l'école |
| Ligne de log exacte qui nomme la cause | `LastError: ContainerTimeout … LastErrorDetails: Container did not respond to startup probe on port 9999 within the expected time limit of 230s. Port mismatch detected: the container is listening on port 8000 but the platform is probing port 9999. …` (intégralement ci-dessus) |
| Combien de fois la plateforme a-t-elle retenté avant d'abandonner ? | Elle **n'a pas abandonné** pendant les 16 min observées : **3 tentatives complètes** de démarrage (pull à 10:27:00, 10:32:08 et 10:38:10 UTC), chacune arrêtée par `Site startup probe failed after 230 seconds`, avec ≈ 1 à 2 min de pause entre deux. Elle relance indéfiniment, jusqu'à la correction |
| Le processus applicatif a-t-il démarré, oui ou non ? | **Oui**, à chaque tentative : `Starting gunicorn 26.2.0` puis `Listening at: http://0.0.0.0:8000 (1)` (10:27:06, 10:32:26, 10:38:15 UTC) |
| Temps écoulé entre le redémarrage et la ligne fautive | **5 min 00 s** (restart à 10:25:53 UTC, ligne à 10:30:53 UTC) : ≈ 70 s d'arrêt et de pull, puis les 230 s du délai de sonde |

### Mesure 11 — retour au service

| Élément | Mon relevé |
|---|---|
| Durée entre la correction et le premier `200` | **100 s** (correction à 11:43:23, codes `000` à 11:43:53, `000` à 11:44:34, `200` à 11:45:03) |
| A-t-il fallu un redémarrage explicite ? | **Non.** La plateforme a repris seule : `appsettings set` recycle le conteneur |

**Question 4.1**
1. **Du point de vue du client, rien ne distingue les deux cas** (ou presque) : une page 503 générique du frontal, ou pas de réponse du tout. La seule différence observée est le moment où l'on voit un `000` (délai dépassé) plutôt qu'un `503` selon l'état du cycle de démarrage, ce qui ne renseigne pas sur la cause.
2. **Dans les logs, une ligne discriminante pour chacun.** Avant le rôle : `LastError: ImagePullUnauthorizedFailure, … LastErrorDetails: Failed to pull image: acrdermascansm26.azurecr.io/dermascan-api:1.0.0. Image pull failed with forbidden or unauthorized. Check registry credentials.` (le conteneur n'a **jamais existé**). Pendant la panne : `LastError: ContainerTimeout, … Port mismatch detected: the container is listening on port 8000 but the platform is probing port 9999.` (le conteneur **tournait**, gunicorn écoutait, mais pas sur le bon port).
3. **Un code HTTP est un symptôme, pas un diagnostic.** Le 503 dit « le frontal n'a rien à qui transmettre », jamais pourquoi. Deux causes sans rapport (droit sur le registre, configuration du port) produisent le même code : il faut toujours remonter aux logs de la plateforme, et outiller la supervision sur `LastError`, pas sur le code seul.

## Partie 4.3 — Mesure 12 : métriques de la plateforme

`az monitor metrics list --resource "$APP_ID" --metric "Requests" "Http5xx" "HttpResponseTime" --interval PT1H`, lancé à 11:45:24 (fenêtre agrégée d'une heure, 10:45 → 11:45, avant le test de charge).

| Métrique | Mon relevé sur l'heure écoulée |
|---|---|
| Nombre total de requêtes | **43** |
| Nombre de réponses 5xx | **8** |
| Temps de réponse moyen | **52,3 ms** (`HttpResponseTime` 0,0523 s) |

Pour comparaison, la même commande relancée à 12:41:51 (fenêtre couvrant les quatre paliers de charge) : **7 082** requêtes, **25** réponses 5xx, temps de réponse moyen **1 869 ms**.

**Question 4.2** — Non. Ces métriques sont des **moyennes mesurées côté serveur** : la plateforme annonce 52 ms pendant que chaque client du réseau de l'école attendait 19 s, et une moyenne de 1,9 s sous charge cache un **p99** de 15 s sur `/predict` au palier 4 (partie 5). Le mot qui manque est **percentile** : « lent pour mes utilisateurs » se mesure au p95/p99 vu du client, pas à la moyenne vue du serveur.
