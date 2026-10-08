# Séance 1 — Mesures et réponses (parties 2 à 6)

Soufiane Meskine · suffixe `sm26` · région `francecentral` · poste Windows x64 (Docker Desktop)

> Valeurs relevées dans `logs/sortie_tp.log` et `logs/sortie_acr.log`. Les durées de build (mesures 5 et 7) viennent du premier passage, à cache vide.
>
> **Incident tracé :** au premier `az acr create`, Azure a répondu `MissingSubscriptionRegistration`, car le fournisseur `Microsoft.ContainerRegistry` n'était pas enregistré sur l'abonnement. Corrigé par `az provider register --namespace Microsoft.ContainerRegistry --wait` (74,5 s), puis il a fallu attendre la propagation DNS du nom `acrdermascansm26.azurecr.io`.

## Partie 2 — Environnement

### Mesure 2 — identité du compte Azure

| Élément | Valeur |
|---|---|
| Identifiant de l'abonnement | `38afe200-d678-45cc-9d39-ecf7f8de0cc8` |
| Nom / état de l'abonnement | Azure for Students, `Enabled` |
| Locataire (tenant) | `ynov.com` (`38e72bba-3c22-4382-9323-ac1612931297`) |

**Question 2.1** — `az account list-locations` renvoie **109** régions pour mon abonnement. Ce chiffre compte aussi les régions logiques (par exemple `europe`, `global`) et des régions où l'offre étudiante ne peut pas forcément créer de ressources : le sous-ensemble réellement utilisable est plus petit (politique d'emplacements autorisés de l'offre). En entreprise, pour des données industrielles européennes, deux critères imposent la région : la **résidence des données** (RGPD, contrats clients, souveraineté : rester dans l'UE, voire en France, et pour des données de santé chez un hébergeur certifié HDS) et la **latence** vers les sites et utilisateurs qui consomment le service. La disponibilité des services nécessaires dans la région (GPU, zones de disponibilité) et le prix, qui varie d'une région à l'autre, pèsent aussi.

### Mesure 3 — état du groupe de ressources

| Élément | Valeur |
|---|---|
| `ProvisioningState` | `Succeeded` |

**Question 2.2** — Non : un groupe de ressources est un conteneur logique gratuit. Observé : coûts d'octobre à 0,00 $US et crédit intact (88 $US sur 88 $US).

### Mesure 4 — environnement Docker

| Élément | Commande | Valeur |
|---|---|---|
| Version du client Docker | `docker version` | 28.5.1 |
| Version du démon | `docker version` | 28.5.1 |
| Architecture | `docker info` | `x86_64` (= amd64) : pas de reconstruction nécessaire pour Azure |
| Nombre d'images déjà présentes | `docker info` | 2 (avant le TP) |
| Mémoire allouée au démon | `docker info` | 8 177 180 672 octets ≈ 7,6 Gio |

## Partie 3 — Conteneurisation

**Question 3.1** — Dans un conteneur, `127.0.0.1` est le loopback de l'espace réseau du conteneur lui-même : le trafic publié par `-p` arrive sur l'interface réseau du conteneur, et seule une écoute sur `0.0.0.0` (toutes les interfaces) l'accepte.

**Question 3.2** — Oui. `EXPOSE` est purement déclaratif (documentation et métadonnée de l'image) ; c'est `-p` qui crée la redirection de port. Vérifié : une image dont le seul port déclaré est 9999 répond quand même sur `-p 8009:8000` (section « Q3.2 » du journal).

**Question 3.3** — Sans `.dockerignore`, les 400 Mo de `.venv/` sont envoyés au démon comme contexte de build à chaque construction, ce qui ralentit chaque build avant même la première instruction. Et avec un `COPY . ./` (le Dockerfile naïf), le `.venv/` est copié dans l'image : elle grossit de 400 Mo d'un environnement Windows inutilisable sous Linux, et toute modification de ce dossier invalide le cache.

### Mesure 5 — premier build

| Mesure | Valeur |
|---|---|
| Durée du premier build (cache vide) | 17,1 s |
| Taille de l'image | 192 Mo sur disque (`docker images`), 46,8 Mo de contenu compressé (`docker image inspect`, champ `Size`) |
| Nombre de couches (`docker history`) | 19 lignes, dont 9 issues de notre Dockerfile et 10 de l'image de base |
| Couche la plus lourde et son instruction | 85,2 Mo : système de fichiers Debian bookworm de l'image de base (`debuerreotype`). Couche la plus lourde de notre Dockerfile : `RUN pip install`, 5,64 Mo |
| Taille de l'image de base seule | ≈ 139,8 Mo (somme des couches de base dans `docker history` : 85,2 + 9,59 + 45 + 0,016 Mo). `docker images python` est resté vide : avec BuildKit et le magasin containerd, l'image de base n'est pas étiquetée localement |

**Question 3.4** — Part de l'image de base = 139,8 Mo / (139,8 + 5,7) Mo ≈ **96 %** (calcul sur les couches de `docker history` ; nos couches ajoutent ≈ 5,7 Mo, dont 5,64 Mo pour Flask et ses dépendances). L'essentiel du poids vient de l'image de base, pas de notre code ni de Flask.

### Mesure 6 — sonde `/health`

| Mesure | Valeur |
|---|---|
| Code HTTP | `200 OK` |
| `hostname` | `03aadc74eebc` |
| `version` | `0.1.0` |
| `status` | `ok` |

**Question 3.5** — Le `hostname` est l'identifiant court (12 caractères) du conteneur, attribué par Docker à sa création. Après `docker rm -f` puis `docker run`, il change (`03aadc74eebc` → `b0532dc93a12`). Un conteneur est donc jetable et sans identité stable : on ne doit jamais s'appuyer sur son nom d'hôte ni sur son état local, et tout ce qui doit durer vit hors du conteneur.

**Question 3.6** — Oui, le second conteneur répond `"version": "0.1.0-bis"` sans aucune reconstruction. L'image est un artefact immuable, identique d'un environnement à l'autre ; la configuration est injectée au lancement par variables d'environnement. On promeut donc le même artefact en test puis en production, en ne changeant que sa configuration.

### Mesure 7 — ordre des instructions et cache

| Scénario | Durée du build | Étapes `CACHED` | `pip install` rejoué ? |
|---|---|---|---|
| A — bon ordre, après modification d'`app.py` | 2,2 s | 3 (WORKDIR, COPY requirements, RUN pip install) | Non |
| B — mauvais ordre, après modification d'`app.py` | 6,9 s | 1 (WORKDIR seulement) | Oui |
| Écart A/B | +4,7 s (×3,1) | 2 étapes de moins en cache | pip rejoué uniquement en B |

**Question 3.7** — Docker réutilise une couche si l'instruction est identique et, pour `COPY`/`ADD`, si la somme de contrôle des fichiers copiés n'a pas changé, à condition que la couche parente soit elle-même réutilisée. Dès qu'une couche est invalidée, toutes les couches suivantes sont reconstruites, même si leur instruction n'a pas changé, car leur parent est différent. Avec `COPY . ./` avant `pip install`, toute modification du code invalide la copie, donc l'installation des dépendances est rejouée. En copiant `requirements.txt` seul d'abord, l'installation reste en cache tant que la liste des dépendances ne bouge pas.

**Question 3.8** — Avec Flask seul, l'écart mesuré est de 4,7 s par itération, soit 94 s (≈ 1,6 min) sur 20 itérations. Avec scikit-learn, pandas et numpy (plusieurs centaines de Mo de roues à télécharger et décompresser), un `pip install` dure plutôt de l'ordre de la minute ou plus. Le mauvais ordre coûterait alors environ 20 × 1 à 2 min, soit 20 à 40 minutes perdues par jour, plus la bande passante et la pression sur le cache disque.

### Mesure 8 — utilisateur non root

| Contrôle | Attendu | Observation |
|---|---|---|
| `id` dans le conteneur | uid non nul | `uid=10001(appuser) gid=10001(appuser)` |
| `.Config.User` de l'image | non vide | `10001` |
| Écriture dans `/etc` | refusée | `touch: cannot touch '/etc/preuve_root': Permission denied` |

**Question 3.9** — En root, l'attaquant peut modifier tout le système de fichiers du conteneur (binaires, configuration), installer des outils et lire tous les secrets présents. Surtout, root dans le conteneur est root sur l'hôte (sans remappage d'uid) : toute faille d'évasion ou mauvaise configuration (socket Docker monté, volume de l'hôte, `--privileged`) lui donne directement la machine. En `appuser`, chacune de ces étapes demande en plus une élévation de privilèges.

## Partie 4 — Azure Container Registry

### Mesure 9 — registre

| Élément | Valeur |
|---|---|
| `loginServer` | `acrdermascansm26.azurecr.io` |
| SKU | Basic |
| État d'approvisionnement | `Succeeded` |
| Coût mensuel annoncé | environ 5 USD/mois (≈ 0,167 USD/jour), à vérifier sur la page tarifaire Azure Container Registry |

**Question 4.1**

| SKU | Stockage inclus | Fonctionnalités |
|---|---|---|
| Basic | 10 Gio | Fonctions de base (push/pull, webhooks, authentification Entra ID), débit limité |
| Standard | 100 Gio | Même chose avec plus de débit et de webhooks |
| Premium | 500 Gio | En plus : géoréplication, Private Link / points de terminaison privés, zones de disponibilité, clés gérées par le client, débit maximal |

DermaScan devra passer en Premium dès qu'il faudra **retirer le registre d'Internet** (accès uniquement par point de terminaison privé dans un réseau virtuel, exigence probable pour une plateforme de santé), ou **géorépliquer** les images vers plusieurs régions où tournent des centres de dépistage.

**Question 4.2** — Après `az acr login`, `~/.docker/config.json` contient `"auths": {"acrdermascansm26.azurecr.io": {}}` et `"credsStore": "desktop"` (observé). Le jeton lui-même est rangé dans le gestionnaire d'identifiants ; sans magasin, il serait écrit directement en base64 (simple encodage, pas du chiffrement). C'est un secret : ce jeton permet de pousser, tirer, voire écraser des images avec mon identité. Commité, il donne à quiconque lit le dépôt accès au registre, et donc à ce qui part en production.

**Question 4.3** — (1) L'utilisateur administrateur est un compte unique et partagé, avec tous les droits : on ne sait plus qui a poussé quoi (aucune traçabilité individuelle) et on ne peut pas donner des droits plus fins (lecture seule pour la production, par exemple), contrairement aux rôles RBAC `AcrPull`/`AcrPush`. (2) Son mot de passe est statique, sans MFA ni expiration : il finit copié dans des scripts et des pipelines, sa rotation casse tous les clients, et le départ d'une personne impose de le changer partout, alors qu'une identité Entra ID se révoque individuellement.

### Mesure 10 — premier push

| Mesure | Valeur |
|---|---|
| Durée du push | 4,2 s |
| Nombre de couches poussées | 10 |
| IMAGE ID local et tagué identiques ? | Oui : `df2fa4f619a3` pour les deux, `docker tag` ne crée qu'un second nom |
| Digest | `sha256:df2fa4f619a350750c79527799f376b795d67ad0e9e5f33cb96cb45698d98451` |

**Question 4.4** — Le second push est quasi instantané (0,7 s contre 4,2 s) : Docker affiche `Layer already exists` pour chaque couche. Un registre stocke les couches par leur empreinte (adressage par contenu) : avant d'envoyer, le client demande si chaque digest existe déjà. Seules les couches nouvelles transitent, et des couches partagées (image de base) ne sont stockées qu'une fois.

**Point architecture** — Poste en amd64 : l'image est déjà construite pour l'architecture des hôtes Linux d'Azure, la reconstruction avec `--platform linux/amd64` n'est pas nécessaire.

**Vérification dans le registre (4.4)** — `az acr repository list` → `dermascan-health` ; `show-tags` → `0.1.0` ; `az acr manifest list-metadata` montre 3 manifestes : l'index `df2fa4f6…` (celui qui porte le tag), le manifeste `amd64` `f7cea7ea…` (46,8 Mo) et le manifeste d'attestation `6eb4c96c…` (architecture `unknown`, ajouté par BuildKit, ce n'est pas une erreur). Capture : `captures/portail_acr_tag.png`.

### Mesure 11 — image retéléchargée depuis ACR

| Mesure | Valeur |
|---|---|
| Durée du `docker run` avec téléchargement | 1,3 s |
| JSON identique à celui de 3.4 ? | Oui pour `status` (`ok`), `service` et `version` (`0.1.0`) ; seuls `hostname` et `uptime_seconds` diffèrent |
| `hostname` changé ? | Oui : `1183c4590566`, nouveau conteneur donc nouvel identifiant |

## Nettoyage

### Décision de fin de séance (tracée)

L'énoncé recommande de conserver le registre jusqu'à la séance 3. **J'ai choisi de le supprimer le 06/10/2026 au soir**, après les captures et la fiche d'identité, pour ne rien consommer sur le crédit entre les séances.

- **Ce qui disparaît :** le registre `acrdermascansm26` et l'image `dermascan-health:0.1.0` qu'il contenait (digest `sha256:df2fa4f6…`).
- **Ce qui reste :** le groupe `rg-dermascan-registre-sm26`, gratuit, avec ses étiquettes (`a_detruire = 2027-06-30`).
- **Comment c'est vérifié :** `az group list` n'affiche plus que `rg-dermascan-registre-sm26`, et `az resource list` ne renvoie aucune ressource.
- **Ce que ça coûte en contrepartie :** au début de la séance 2, il faut recréer le registre et republier l'image avec `suite_acr.ps1` (environ 5 minutes : reconstruction depuis le `Dockerfile` puis push). La nouvelle image aura un nouveau digest, sauf si la construction est reproductible au bit près.

### Mesure 12

| Contrôle | Observation |
|---|---|
| Espace libéré par `docker system prune` | 207,3 Mo |
| Ressources actives dans `$RG` | 1 (`acrdermascansm26`) au relevé de 16:53, puis **0** à 19:26 après la suppression du registre (`az resource list` vide) |
| SKU du registre et coût journalier | Basic, environ 0,167 USD/jour tant qu'il existait ; 0 USD/jour depuis sa suppression |
| Date de l'étiquette `a_detruire` | 2027-06-30 |
| Groupes de ressources m'appartenant | 1 : `rg-dermascan-registre-sm26`. Un groupe vide `rg-dermascan-registre-`, créé par erreur au premier essai (suffixe vide), a été vérifié vide (`az resource list`) puis supprimé |
| Crédit restant (Cost Management) | 88 $US sur 88 $US le 06/10/2026 à 18:15 (portail Education), coûts d'octobre : 0,00 $US. La consommation du registre (≈ 0,17 $/jour) n'apparaît pas encore, car la facturation remonte avec 24 à 48 h de décalage : c'est l'écart avec le relevé de la séance 2 qui la montrera. Expiration du crédit : 06/10/2027. Capture : `captures/credit_education.png` |

**Question 6.1** — Phrase que j'aurais écrite si j'avais conservé le registre, comme le recommande l'énoncé (je l'ai finalement supprimé ce soir, voir la décision ci-dessus) : « Le registre `acrdermascansm26` (groupe `rg-dermascan-registre-sm26`, SKU Basic, environ 0,17 USD/jour sur le crédit Azure for Students de Soufiane Meskine) reste volontairement actif : il héberge l'image `dermascan-health` consommée par les séances 2 à 4 et le projet fil rouge. Il peut être détruit par n'importe qui avec `az group delete` après le 2027-06-30, date de l'étiquette `a_detruire`, postérieure à la soutenance. »

**Question 6.2** — `--no-wait` rend la main dès que la demande est acceptée, pas quand elle a abouti. La suppression peut prendre plusieurs minutes, ou échouer (verrou, ressource dépendante), et les ressources continuent alors d'être facturées sans que je le sache. Je ne considère la suppression acquise que lorsque `az group exists --name "$RG"` renvoie `false`, interrogé en boucle ou relancé quelques minutes plus tard, et je recoupe le lendemain avec l'analyse des coûts.

### Contrôle d'extinction

| Contrôle | Fait |
|---|---|
| `az group list` ne montre qu'un groupe, celui du registre | ✅ `rg-dermascan-registre-sm26` seul |
| Aucun conteneur de la séance dans `docker ps -a` | ✅ liste vide |
| Docker Desktop quitté | ☐ |
| Machine éteinte | ☐ |
