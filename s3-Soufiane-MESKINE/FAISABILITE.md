# Faisabilité et choix de la cible — Séance 3

Soufiane Meskine, Master 2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. Séance réalisée le 26/10/2026 (heure de Paris, UTC+1), abonnement **Azure for Students**, Azure CLI exécutée sous PowerShell (Windows).

## Tableau de décisions

| Décision | Contrainte | Ma valeur |
|---|---|---|
| Suffixe personnel | identique à S1 | `sm26` |
| Région Azure | une seule, la même partout | `francecentral` |
| Nom du groupe de ressources | préfixé `rg-dermascan-s3-` | `rg-dermascan-s3-sm26` |
| Nom du registre ACR existant | celui de S1 | `acrdermascansm26` (groupe `rg-dermascan-registre-sm26`) |
| Dépôt et tag de l'image S2 | ce qui est réellement dans le registre | `dermascan-api:1.0.0` (seul tag du dépôt) |
| Nom du plan de service | préfixé `plan-dermascan-` | `plan-dermascan-sm26` (Linux, SKU **B1**) |
| Nom de l'application web | unique sur Azure | `app-dermascan-sm26` → `https://app-dermascan-sm26.azurewebsites.net` |

Étiquettes du groupe : `projet=dermascan seance=s3 proprietaire=soufiane.meskine a_detruire=2026-10-26`.

**Question 0.1** — Le nom unique devient un sous-domaine public et prévisible (`<nom>.azurewebsites.net`), énumérable par un attaquant (dictionnaire `dermascan-*`, DNS, journaux de transparence des certificats). Contrairement au registre, qui exige une authentification pour tout pull, l'application répond **anonymement** à Internet : il suffit de deviner le nom pour appeler `/predict` et lire `/model/info`, qui livre les 40 colonnes du modèle.

## Partie 1.2 — Mesure 1 : sondes de faisabilité

Sonde lancée à 10:43:48, décision à 10:51:19.

| Sonde | Commande source | Mon relevé |
|---|---|---|
| Régions autorisées par la politique | `az policy assignment list` | `norwayeast`, `francecentral`, `switzerlandnorth`, `polandcentral`, `belgiumcentral` (politique « Allowed resource deployment regions » active) |
| `Microsoft.Web` | `az provider show` | `NotRegistered` → enregistré avec `az provider register --wait` → `Registered` (≈ 2 min, 10:44:56 → 10:46:55) |
| `Microsoft.ContainerInstance` | `az provider show` | `NotRegistered` → enregistré → `Registered` (≈ 2 min, 10:47:07 → 10:48:59) |
| `Microsoft.ContainerRegistry` | `az provider show` | `Registered` (déjà enregistré en S1) |
| Création du plan App Service Linux | `az appservice plan create` | **succès** : `plan-dermascan-sm26`, SKU `B1`, état **`Ready`** |
| Code d'erreur exact, le cas échéant | sortie de la commande | aucun (seul avertissement : `Creating App Service Plan 'plan-dermascan-sm26' (Linux, SKU: B1).`) |
| Durée totale de la sonde | chronomètre | **451 s** (7 min 31 s), dont ≈ 4 min d'enregistrement des deux fournisseurs |

Les deux fournisseurs non enregistrés auraient produit `MissingSubscriptionRegistration` à la création : les sonder d'abord a évité de confondre ce cas avec un manque de droits.

## Partie 1.3 — Mesure 2 : cible retenue

| Élément de la décision | Ma réponse |
|---|---|
| Cible retenue | **A — App Service for Containers** |
| Fait déclencheur | Création réelle du plan Linux B1 réussie, état `Ready` relu par `az appservice plan show`, sans aucun message d'erreur ni de quota, dans une région autorisée par la politique (`francecentral`) |
| Heure de la décision | **10:51:19** (8 min après le début de la sonde, sous la limite de 20 min) |
| Ce que cette cible ne permettra pas de montrer aujourd'hui | La mise à l'échelle horizontale mesurée (une seule instance B1 ; aucun deuxième palier avec 2 instances, faute de temps et de crédit), le comportement d'ACI sans frontal (panne sans 503, sondes livenessProbe) et le passage du sel en `--secure-environment-variables`. Le frontal d'App Service masque aussi certaines erreurs du conteneur derrière un 503 ou un 502 générique |

**Question 1.1**

| Cible | Modèle de service | Ce que je ne gère pas | Ce qui reste à ma charge |
|---|---|---|---|
| App Service for Containers | **PaaS** (conteneur sur plateforme managée) | Machines et OS hôtes, runtime de conteneurs, frontal HTTPS avec certificat TLS, répartition de charge, sonde de santé et redémarrage, collecte des logs et des métriques, mises à l'échelle en un réglage | L'image (OS de base, dépendances, CVE), le code et le modèle, la configuration (ports, variables, secrets), le choix du SKU et du nombre d'instances, les droits (identité, rôle) |
| Azure Container Instances | **PaaS / CaaS** de plus bas niveau | Les machines et l'OS hôte, l'orchestrateur du conteneur, l'IP publique | En plus de ce qui précède : pas de frontal ni de TLS (HTTP direct), pas de mise à l'échelle automatique (instances créées à la main), sonde à décrire en YAML, identifiants de registre à fournir (pas d'identité managée pour le pull) |
| Docker sur mon poste | **Aucun service cloud : je suis l'hébergeur** (équivalent d'un IaaS que j'aurais acheté) | Rien | Tout : matériel, OS, Docker, réseau, exposition, redémarrages, logs, disponibilité. Pas d'URL publique |

**Question 1.2** — Prix de détail Azure (API publique `prices.azure.com`, relevée le 26/10/2026) : **Azure App Service Basic Plan – Linux, B1, France Central = 0,0158 € par heure**, soit **0,0158 × 730 h ≈ 11,53 € par mois** en fonctionnement continu (pour comparaison, le même B1 sous Windows coûte 0,0827 €/h, cinq fois plus).

Crédit restant relevé avant la séance (fin de S2, page Education du portail) : **87 €**. 87 € / 0,0158 €/h ≈ 5 506 h, soit **≈ 229 jours** de fonctionnement continu d'un seul plan B1, si rien d'autre n'était facturé. Ce chiffre est confortable pour un plan, mais il fond vite : le plan facture à l'heure **même sans trafic**, le registre continue de facturer son stockage, et un passage en P1v3 ou 3 instances pour tenir une charge diviserait cette durée par 5 à 10. Surtout, un crédit épuisé fait basculer l'abonnement sur l'offre Starter, qui interdit `Microsoft.ContainerRegistry` : le registre, donc l'image des séances suivantes, serait perdu. D'où le nettoyage obligatoire en fin de séance.
