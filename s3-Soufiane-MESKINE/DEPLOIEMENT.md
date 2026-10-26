# Déploiement de l'API d'inférence sur App Service — Séance 3

Soufiane Meskine, M2 YNOV Montpellier, 26/10/2026. Heures en heure de Paris (UTC+1), sauf mention « UTC ». Cible A (voir `FAISABILITE.md`).

> **Lecture des durées curl de ce document.** Depuis le réseau de l'établissement, **chaque nouvelle connexion HTTPS vers Azure met ≈ 19 s à s'établir** (poignée de main TLS ralentie entre le poste et Azure, mesurée en partie 5 : `tcp` ≈ 0,1 s, `tls` ≈ 19 s, `http://` sans TLS ≈ 0,17 s). Toutes les mesures « une commande curl = une connexion » ci-dessous contiennent donc ces 19 s, qui n'appartiennent pas au service. Le diagnostic complet est dans la question 2.4 et dans `RAPPORT_CHARGE.md`.

## Valeurs de configuration retenues (trace écrite)

| Réglage | Valeur | Origine |
|---|---|---|
| `SEUIL` (seuil de S2) | **`0.34747330294391954`** | `MESURES.md` de S2 : seuil pour un rappel visé de 0,90 sur le test (99 malignes sur 110 signalées) |
| Seuil abaissé testé en 3.3 | **`0.0347`** | ≈ dixième du seuil de S2 |
| `WEBSITES_PORT` / `PORT` | `8000` / `8000` | port d'écoute de gunicorn dans l'image |
| `MODEL_VERSION` | `1.0.0-azure` | volontairement différent du `1.0.0` du paquet, pour voir laquelle des deux sources l'API expose |
| `LOG_LEVEL` / `ENVIRONMENT` | `info` / `recette` | |
| `INFERENCE_LOG_SALT` | 16 octets aléatoires (32 caractères hexadécimaux) générés sur le poste | **valeur jamais écrite dans ce rendu ni dans les journaux du script** |

## Partie 2.1 — Mesure 3 : image exacte à déployer

| Relevé | Ma valeur |
|---|---|
| `loginServer` | `acrdermascansm26.azurecr.io` |
| Nom complet de l'image (`IMAGE_FULL`) | `acrdermascansm26.azurecr.io/dermascan-api:1.0.0` |
| Digest `sha256` du tag déployé | `sha256:cae2b6358fcfc65751d85a16536efb9ae660b5b26782e56f98fdcaedb310006b` |
| Architecture déclarée dans le manifeste | `amd64` (une seule ligne : image poussée avec `--provenance=false` en S2, pas d'index ni d'attestation) |
| Date de publication de ce tag | `2026-10-11T13:15:23Z` (manifeste de 149 399 328 octets) |

**Question 2.1** — Le tag est une étiquette mobile, le digest est l'empreinte du contenu. Si un camarade poussait demain une autre image sous `dermascan-api:1.0.0`, le prochain redémarrage (manuel, après un `appsettings set`, ou décidé par la plateforme) tirerait **silencieusement** la nouvelle image : même URL, même configuration, autre code ou autre modèle, sans aucune trace dans la configuration de l'application. Le digest relevé aujourd'hui sert alors deux fois : il **prouve** que l'image a changé (comparer avec le digest courant du tag) et il permet de **revenir exactement** à l'image d'aujourd'hui en déployant `acrdermascansm26.azurecr.io/dermascan-api@sha256:cae2b6…006b`. La vraie protection est de déployer directement par digest et de verrouiller le tag (`az acr repository update --write-enabled false`).

## Partie 2.2 — Mesure 4 : avant tout droit sur le registre

Application créée à 10:53:42 (70 s), `WEBSITES_PORT=8000` posé, observation 60 s plus tard.

| Relevé avant octroi des droits | Ma valeur |
|---|---|
| Code HTTP retourné | **503** |
| Durée de la réponse | **16,18 s** (dont l'ouverture de connexion TLS du réseau de l'école) |
| Contenu de la page renvoyée | Page HTML générique du frontal Azure, titre « 503 Service Unavailable », sans aucune mention du registre ni de l'image (capture `captures/mesure4_503_avant_droits.png`) |

La cause n'apparaît que dans les logs de la plateforme (lus en partie 4) : `LastError: ImagePullUnauthorizedFailure … Image pull failed with forbidden or unauthorized. Check registry credentials.` (`captures/incident_pull_log.txt`).

## Partie 2.3 — Mesure 5 : identité managée

| Relevé | Ma valeur |
|---|---|
| `principalId` de l'identité managée | `64e72498-4ff9-4af5-9902-05b14d522263` (identité affectée par le système) |
| Rôle accordé | **`AcrPull`** |
| Portée exacte du rôle | `/subscriptions/38afe200-d678-45cc-9d39-ecf7f8de0cc8/resourceGroups/rg-dermascan-registre-sm26/providers/Microsoft.ContainerRegistry/registries/acrdermascansm26` |
| Délai entre l'attribution du rôle et le premier pull réussi | **168 s** (rôle attribué à 11:00:42, `acrUseManagedIdentityCreds=true` à 11:01:04, restart à 11:01:29, premier 200 à 11:03:30) |

Contrôle `az role assignment list --scope "$ACR_ID"` : une ligne `Principal c52dbbe5-a6d9-4e68-aed1-e45a47b49c81`, `Role AcrPull`, portée du registre. Comme l'annonce l'énoncé, la colonne Principal affiche l'**identifiant d'application** de l'identité, pas son `principalId` ; la sortie JSON du geste 4 montre bien `principalId 64e72498-…` et `principalType ServicePrincipal`.

Note technique : sous PowerShell, le JSON du geste 5 (`--generic-configurations '{"acrUseManagedIdentityCreds": true}'`) est mal transmis à la CLI. J'ai posé la même propriété par `az resource update --ids "<id de l'app>/config/web" --set properties.acrUseManagedIdentityCreds=true`, relue ensuite à `true`.

**Question 2.2** — Le rôle plus large qui aurait aussi fonctionné est **`AcrPush`** : il permet de tirer, mais aussi de **pousser** des images. Une application compromise pourrait alors réécrire le tag qu'elle exécute elle-même, et le reste des dépôts du registre : attaque de la chaîne d'approvisionnement, persistante au prochain redémarrage. Le rôle encore plus large recommandé par facilité est **`Contributor`** (voire `Owner`) sur le registre ou sur son groupe : l'application pourrait modifier ou supprimer le registre, activer l'utilisateur administrateur et lire ses mots de passe, changer le SKU ou l'exposition réseau. Avec `Owner`, elle pourrait en plus s'attribuer ou attribuer à d'autres de nouveaux droits.

**Question 2.3** — Aucun second redémarrage n'a été nécessaire : le premier restart, lancé 47 s après l'attribution du rôle, a réussi son pull. Il a fallu **168 s** entre l'attribution du rôle et le premier 200, dont 101 s de démarrage du conteneur. La création de l'identité elle-même a pris 138 s. Pour un script automatisé : enchaîner « identité → rôle → `acrUseManagedIdentityCreds` → restart », puis sonder `/health` pendant au moins 5 min avant de conclure à une erreur, et relancer un restart une fois si les logs montrent encore `ImagePullUnauthorizedFailure`.

## Partie 2.4 — Mesure 6 : premier démarrage réussi

| Mesure du premier démarrage | Ma valeur |
|---|---|
| Durée entre le restart et le premier `200` sur `/health` | **101 s** (11:01:49 → 11:03:30) |
| Codes HTTP observés pendant l'attente, dans l'ordre | `000 000 200` (deux délais client de 30 s dépassés, puis 200) |
| Champ `model_loaded` de la réponse `/health` | `true` — réponse complète : `{"model_loaded":true,"status":"ok","version_modele":"1.0.0"}` (`captures/health_public.txt`) |
| Version de modèle retournée par `/model/info` | `1.0.0` |
| `probabilite_maligne` et `decision` retournés par `/predict` | `0.750853` et **`a_examiner`** (`captures/predict_public.txt`) |
| Le seuil appliqué par le service est-il celui de mon paquet S2 ? | **Oui** : `"seuil":0.34747330294391954`, identique au seuil de S2, `rappel_cible 0.9` |
| Durée de la première requête `/predict` | **19,32 s** |
| Durée de la cinquième requête `/predict` identique | **19,44 s** (série : 19,32 ; 19,58 ; 19,69 ; 19,24 ; 19,44 s) |

**Question 2.4** — L'écart entre la première et la cinquième requête est **nul** (± 0,4 s de bruit). Ce n'est donc pas un effet de démarrage à froid : c'est un coût fixe de ≈ 19 s payé à **chaque** requête, et ce même pour `/health` et pour une réponse 400, qui ne font aucune inférence. Deux hypothèses testables :

1. **Le serveur est bloqué** : l'image lance gunicorn avec des workers `sync` (`Using worker: sync` dans les logs), et l'annexe B décrit exactement ce symptôme (5 à 20 s par requête quand des connexions inactives du frontal bloquent les workers). *Test* : remplacer la commande de démarrage sans reconstruire l'image (`az webapp config set --startup-file "gunicorn --bind 0.0.0.0:8000 --workers 2 --threads 4 --worker-class gthread --access-logfile - app:app"`). *Résultat* : 36 essais après la correction, toujours 19,0 à 20,1 s. **Hypothèse écartée.** Les métriques de la plateforme le confirmaient déjà : `HttpResponseTime` moyen côté serveur = **52 ms**.
2. **Le temps se perd entre le poste et Azure** (réseau de l'établissement). *Test* : `curl -w` qui détaille les étapes (`diag_s3.log`). *Résultat* : DNS 0,06 s, TCP 0,07 s, **TLS 19,4 s**, puis réponse en 0,03 s ; la même requête en `http://` répond en 0,17 s ; trois requêtes sur la **même** connexion : 19,36 s puis 0,024 s, 0,058 s, 0,030 s ; `--ssl-no-revoke` et IPv4 forcé ne changent rien ; Python et PowerShell subissent le même délai. **Hypothèse confirmée** : chaque nouvelle connexion TLS coûte ≈ 19 s sur ce réseau (le DNS 10.0.150.254 indique un réseau d'établissement, probablement un équipement d'inspection TLS). La vraie latence d'une prédiction, connexion déjà ouverte, est de **≈ 25 à 80 ms**.

La correction gthread a été conservée pour la partie 5 : elle n'était pas la cause, mais elle permet à un worker de servir plusieurs connexions.

## Partie 3.1 — Configuration d'exécution

`az webapp config appsettings set … PORT=8000 MODEL_VERSION=1.0.0-azure LOG_LEVEL=info ENVIRONMENT=recette SEUIL=0.34747330294391954` : 7 réglages à ce stade (`WEBSITES_ENABLE_APP_SERVICE_STORAGE=false`, `WEBSITES_PORT=8000`, `PORT`, `MODEL_VERSION`, `LOG_LEVEL`, `ENVIRONMENT`, `SEUIL`), puis 8 avec le sel.

**Question 3.1** — Ils doivent porter la **même valeur**. `WEBSITES_PORT` est lu par **la plateforme** : c'est le port vers lequel le frontal route le trafic et sur lequel la sonde de démarrage frappe. `PORT` est lu par **mon code** (gunicorn se lie à `0.0.0.0:$PORT`). S'ils diffèrent, le conteneur démarre et écoute normalement, mais la plateforme frappe à une porte où personne ne répond : la sonde de démarrage échoue au bout de 230 s, le site est arrêté, le client ne voit rien d'utile. C'est ce que la partie 4.2 a vérifié : `Port mismatch detected: the container is listening on port 8000 but the platform is probing port 9999`.

## Partie 3.2 — Mesure 7 : visibilité du secret

| Contrôle | Mon observation |
|---|---|
| La valeur du sel est-elle masquée dans la sortie du CLI ? | **Non.** `az webapp config appsettings list --query "[?name=='INFERENCE_LOG_SALT']" --output table` affiche la valeur complète **en clair**. Le script a vérifié ce point sans recopier la valeur dans son journal |
| Est-elle visible dans le portail Azure, onglet Configuration ? | **Masquée par défaut.** Page *Variables d'environnement → Paramètres de l'application* : chaque ligne, `INFERENCE_LOG_SALT` comprise, affiche « Afficher une valeur » à la place de la valeur (`captures/mesure7_portail_variables.png`). Le masquage n'est qu'un affichage : un clic sur « Afficher une valeur » ou « Afficher les valeurs » révèle le sel en clair à toute personne qui a accès à l'application. On y voit aussi `WEBSITE_HTTPLOGGING_RETENTION_DAYS`, ajouté par `az webapp log config` |
| Est-elle lisible par un processus qui s'exécuterait dans le conteneur ? | **Oui.** Un réglage d'application est injecté comme variable d'environnement du conteneur : tout processus peut le lire avec `os.environ["INFERENCE_LOG_SALT"]`. La preuve expérimentale est faite en 3.3 avec `SEUIL` : changer un réglage a changé le seuil que le code lit dans son environnement. N'importe quelle dépendance compromise du conteneur peut donc lire le sel |

Toute personne ayant le rôle Contributor sur l'application (ou un accès au CLI de l'abonnement) lit donc le sel, en clair, en une commande.

**Question 3.2** — Le coffre-fort est **Azure Key Vault**. Je placerais le sel dans un coffre, j'accorderais à l'identité managée de l'application (celle de 2.3) le rôle **Key Vault Secrets User** sur ce seul secret, et je remplacerais la valeur du réglage par une **référence Key Vault** (`@Microsoft.KeyVault(SecretUri=…)`). Le secret disparaît alors complètement de la configuration de l'application (portail, CLI, exports ARM) : il ne reste qu'un pointeur, l'accès est journalisé par le coffre, et la rotation se fait au coffre, sans toucher à l'application ni manipuler aucun mot de passe.

## Partie 3.3 — Mesure 8 : sonde de santé et seuil

| Relevé après redémarrage | Ma valeur |
|---|---|
| Chemin de sonde enregistré | `/health` |
| Durée du redémarrage jusqu'au premier `200` | **100 s** (codes `000 000 200`) |
| Délai entre le `appsettings set` du seuil abaissé et l'apparition du nouveau seuil dans la réponse | **69 s** (seuil posé à 11:15:56, visible à 11:17:05 ; le retour au seuil de S2 a pris aussi 69 s) |
| Nombre total de réglages d'application | **8** |
| La valeur de `MODEL_VERSION` apparaît-elle dans la réponse de `/model/info` ? | **Non** : `/model/info` renvoie `1.0.0` (lu dans le paquet sérialisé), pas `1.0.0-azure`. L'API ne lit pas `MODEL_VERSION` |
| `probabilite_maligne`, avec mon seuil de S2 | `0.750853` (`charge.json`) ; `0.107934` (`charge_seuil.json`, une lésion bénigne du test de S2) |
| `seuil` et `decision` retournés, avec mon seuil de S2 | `0.34747330294391954` → `a_examiner` (`charge.json`) ; même seuil → **`surveillance`** (`charge_seuil.json`) |
| `probabilite_maligne`, avec le seuil abaissé | `0.750853` (`charge.json`) ; `0.107934` (`charge_seuil.json`) — **identiques** |
| `seuil` et `decision` retournés, avec le seuil abaissé | `0.0347` → `a_examiner` (`charge.json`) ; `0.0347` → **`a_examiner`** (`charge_seuil.json`) — capture `captures/predict_seuil_bas.txt` |

Avec `charge.json` (probabilité 0,75, au-dessus des deux seuils), la décision ne pouvait pas changer. J'ai donc ajouté une seconde charge réelle, `charge_seuil.json` (une lésion du test de S2 dont la probabilité tombe entre les deux seuils) : c'est elle qui montre le basculement `surveillance` → `a_examiner`.

**Question 3.3** — Je déploierais la **version 2**, en la gardant légère : test d'inférence sur l'entrée figée exécuté **une fois au démarrage**, et `/health` qui renvoie le résultat mis en cache, plus `model_loaded`. La version 1 introduit le risque d'une instance « vivante mais inutile » : si le modèle n'a pas pu être chargé (fichier absent, version de scikit-learn incompatible), le processus répond 200, la plateforme route le trafic vers elle, et chaque `/predict` échoue en 500, sans que rien ne la retire du service. Ma version actuelle renvoie déjà 503 si `model_loaded` est faux, ce qui couvre ce cas. Le risque de la version 2 non mise en cache : une sonde qui fait une vraie inférence sous charge peut dépasser son délai et faire retirer des instances saines au pire moment, en cascade.

**Question 3.4**
1. C'est le **service** qui a changé de comportement, pas le modèle : même image, même modèle, même probabilité (0,107934) ; seule la règle de décision appliquée par-dessus (le seuil, réglage externe) a changé.
2. Non, le service ne rend pas « les mêmes décisions » : il rend la même **prédiction** (probabilité) mais une **décision** différente. Un rapport d'audit qui écrit « le modèle a changé d'avis » est faux : le modèle n'a rien changé, c'est la configuration de production qui a déplacé le seuil.
3. La trace qui permet de le découvrir est le champ **`seuil_applique`** de chaque ligne du journal d'inférence (partie 6), complété par le **journal d'activité Azure** (`Microsoft.Web/sites/config/write`, avec l'auteur et l'heure du changement de réglage). On verrait le seuil passer de 0,3475 à une autre valeur à une heure donnée, et qui l'a fait.
4. C'est un **progrès**, à condition d'être tracé : on corrige en 69 s, sans reconstruire ni redéployer, un seuil qui doit de toute façon être recalibré par centre (prévalence différente). L'argument adverse est fort : un seuil de décision médicale modifiable sans revue, sans versionnement ni validation, revient à changer le comportement d'un dispositif médical par un simple réglage. Ma position : seuil externe, mais versionné (référence dans Key Vault ou dans une configuration revue), journalisé à chaque inférence et protégé par des droits restreints.

## Nettoyage — Mesures 16 et 17

Script `nettoyage_s3.ps1`, lancé à 16:37:30 après sauvegarde de tous les relevés (journal : `logs/nettoyage_s3.log`).

**Mesure 16 — inventaire avant destruction** (`az resource list --resource-group rg-dermascan-s3-sm26`, 16:39:23)

| Relevé avant destruction | Ma valeur |
|---|---|
| Nombre de ressources dans le groupe | **2** |
| Types de ressources listés | `Microsoft.Web/serverFarms` (`plan-dermascan-sm26`) et `Microsoft.Web/sites` (`app-dermascan-sm26`). L'identité managée n'apparaît pas comme ressource : elle est portée par l'application |
| Le registre ACR est-il dans ce groupe ou dans le groupe du registre ? | Dans **le groupe du registre** (`rg-dermascan-registre-sm26`), absent de cet inventaire |

Ordre suivi : attribution `AcrPull` listée (une ligne, Principal `c52dbbe5-…`) puis supprimée explicitement à 16:41:40 par `az role assignment delete --assignee-object-id 64e72498-… --scope <registre>`, **avant** le groupe ; puis `az group delete --name rg-dermascan-s3-sm26 --yes --no-wait` à 16:42:07 ; puis `.venv-locust` supprimé.

**Mesure 17 — contrôles de destruction**

| Contrôle de fin de séance | Mon observation |
|---|---|
| Le groupe `rg-dermascan-s3-sm26` apparaît-il encore ? | **Non** : `az group list` (16:44:10) ne liste plus que `rg-dermascan-registre-sm26` |
| Reste-t-il une attribution de rôle sur le registre ? | **Non** : `az role assignment list --scope <registre>` renvoie une liste vide à 16:43:39 |
| Le groupe du registre est-il, lui, toujours debout ? | **Oui** : `rg-dermascan-registre-sm26`, état `Succeeded`, avec `acrdermascansm26` (`Microsoft.ContainerRegistry/registries`, `Succeeded`) |
| `az group exists` renvoie | `true` à 16:42:27, puis **`false`** à 16:43:26 (≈ 80 s après la demande de suppression) |
| Crédit restant, relevé dans Cost Management | **87 € sur 88 €** ; coûts d'octobre **2,20 €** ; 345 jours avant expiration du crédit (06/10/2027). Page Education du portail, 16:48 (`captures/mesure17_credit_education.png`) |
| Écart avec le relevé de la séance précédente | Fin de S2 : 87 € disponibles, coûts d'octobre 2,15 €. Aujourd'hui : 87 €, 2,20 € → **+0,05 €** seulement. Le portail facture avec plusieurs heures de retard : les ≈ 6 h de plan B1 de la séance (≈ 6 × 0,0158 ≈ 0,10 €) ne sont probablement pas encore toutes comptées. Coût attendu de la séance : de l'ordre de 0,10 à 0,15 €, registre compris |

**Question 7.1** — Le registre vit dans **son propre groupe** (`rg-dermascan-registre-sm26`), séparé du groupe de séance (`rg-dermascan-s3-sm26`) qui contient le plan et l'application. `az group delete --name rg-dermascan-s3-sm26` détruit donc tout ce qui est facturé à l'heure, sans aucun risque pour le registre : la frontière de destruction est la frontière du groupe. Seule l'attribution de rôle, posée sur le registre, sort de ce périmètre : je l'ai supprimée explicitement avant le groupe. Si le registre avait été dans le même groupe que l'application, une seule commande l'aurait emporté avec l'image : il aurait fallu supprimer les ressources une par une (`az webapp delete`, `az appservice plan delete`), poser au préalable un **verrou** `CanNotDelete` sur le registre (`az lock create --lock-type CanNotDelete`), ou déplacer le registre dans un groupe à part avant le nettoyage (`az resource move`).
