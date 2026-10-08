# Séance 1 — Réponses partie 0 et partie 1

## Tableau de décisions

| Décision | Valeur |
|---|---|
| Suffixe personnel | `sm26` |
| Région Azure | `francecentral` |
| Nom du groupe de ressources | `rg-dermascan-registre-sm26` |
| Nom du registre ACR | `acrdermascansm26` (minuscules et chiffres, vérifié avec `az acr check-name`) |
| Nom de l'image | `dermascan-health` |
| Tag de version initial | `0.1.0` |
| Image de base Python | `python:3.12.7-slim-bookworm` |
| Répertoire de travail dans l'image | `/app` |
| Port d'écoute de l'application | `8000` |
| uid de l'utilisateur d'exécution | `10001` |

**Question 0.1** — L'unicité globale trahit que chaque registre est exposé publiquement sous un nom DNS propre (`<nom>.azurecr.io`) : le nom du registre est un sous-domaine d'un espace de noms partagé par tous les clients Azure.

---

## 1.1 — Les trois modèles de service

| Modèle | Ce que le fournisseur gère à votre place | Ce qui reste à votre charge | Exemple Azure |
|---|---|---|---|
| IaaS | Le matériel, le réseau physique, la couche de virtualisation | Le système d'exploitation, les mises à jour, le runtime, l'application, les données | Azure Virtual Machines |
| PaaS | En plus de l'IaaS : le système d'exploitation, ses correctifs, le runtime et l'infrastructure de mise à l'échelle | Le code de l'application, sa configuration (dont le choix de version du runtime et les règles de mise à l'échelle), les données | Azure App Service |
| SaaS | L'application entière, son exploitation, ses mises à jour et sa disponibilité | Les données saisies, la gestion des utilisateurs et des droits, le paramétrage fonctionnel | Microsoft 365 |

## 1.2 — Où s'arrête votre responsabilité

| Couche | Dernier modèle où c'est à vous |
|---|---|
| Correctifs de sécurité du système d'exploitation | IaaS |
| Version du runtime Python | PaaS |
| Code de l'application | PaaS |
| Dimensionnement du nombre d'instances | PaaS |
| Vos données métier | SaaS |

**Question 1.1** — Les données métier restent à notre charge dans les trois modèles. Quel que soit le modèle, DermaScan reste responsable de traitement au sens du RGPD : choix de la région d'hébergement, contrat de sous-traitance avec le fournisseur, minimisation et sécurité des données. Pour des données de santé (catégorie particulière, art. 9), il faut en plus un hébergeur certifié HDS en France.

## 1.3 — Les cinq caractéristiques NIST

| Caractéristique NIST | Traduction opérationnelle |
|---|---|
| Libre-service à la demande | Je crée une ressource sans ouvrir de ticket ni attendre l'accord d'un humain. |
| Accès réseau large | J'administre et j'utilise mes ressources par le réseau standard (portail web, CLI, API HTTPS), depuis n'importe quel poste. |
| Mise en commun des ressources | Mes ressources tournent sur des machines partagées avec d'autres clients : je choisis une région, jamais un serveur physique. |
| Élasticité rapide | J'augmente ou je réduis la capacité en quelques minutes, voire automatiquement, sans acheter de matériel. |
| Service mesuré | Chaque ressource est comptée et facturée à l'usage ou à la réservation, et je vois ce coût dans Cost Management. |

**Question 1.2** — Le service mesuré : tout ce qui existe est compté et facturé, qu'il soit utilisé ou non. Une ressource oubliée continue donc de consommer le crédit, d'où le nettoyage obligatoire.

## 1.4 — Exploration du portail Azure

### Mesure 1 — relevé d'exploration (à relever dans le portail)

| # | Observation | Réponse |
|---|---|---|
| 1 | Nombre de champs obligatoires à la création d'un Container Registry | **6** : Abonnement, Groupe de ressources, Nom du registre, Emplacement, Étendue d'étiquette du nom de domaine, Plan de tarification (onglet « Informations de base », capture `captures/creation_acr_champs.png`). Valeurs proposées par défaut : East US et plan Standard, d'où l'intérêt de fixer explicitement région et SKU |
| 2 | Identifiant et état de l'abonnement | `38afe200-d678-45cc-9d39-ecf7f8de0cc8`, Azure for Students, état `Enabled` (actif) |
| 3 | Nombre de groupes de ressources existants | 0 avant la séance (le premier `az group create` du TP a créé le seul groupe de l'abonnement) |
| 4 | Crédit restant à la date du jour | 88 $US sur 88 $US (06/10/2026), expiration le 06/10/2027 |
| 5 | Quota limitant pour dix VM | _à relever_ (typiquement « Total Regional vCPUs » et le quota de vCPU par famille de VM, faibles sur un compte étudiant) |
| 6 | Rôle de l'onglet Étiquettes | Associer des paires clé/valeur à une ressource pour l'imputer à un projet, un propriétaire ou une date de fin, et la filtrer dans les coûts. |

### Classement

| Service Azure | Modèle |
|---|---|
| Azure Virtual Machines | IaaS |
| Azure App Service | PaaS |
| Azure Container Registry | PaaS |
| Azure Machine Learning (espace de travail managé) | PaaS |
| Microsoft 365 | SaaS |

**Question 1.3**

- **Deux groupes à la fois ?** Non. Une ressource appartient à exactement un groupe de ressources ; on peut la déplacer, pas la partager.
- **Suppression d'un groupe ?** Toutes les ressources qu'il contient sont supprimées avec lui, de façon irréversible.
- **La région du groupe contraint-elle celle des ressources ?** Non. Elle indique où sont stockées les métadonnées du groupe (sa description et son historique de déploiement). Si cette région est indisponible, on ne peut plus modifier le groupe, même si ses ressources sont ailleurs.
