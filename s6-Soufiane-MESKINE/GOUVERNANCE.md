# Séance 6 — Gouverner : AI Act, RGPD, traçabilité (2.1 à 2.5)

Soufiane Meskine · 20/11/2026.

> **Réserve.** Le fichier du projet (`ProjetFilRouge_MLOps_Sujet.md`) n'était pas dans le dossier de la séance. Les usages de DEEP-VOICE et d'Eedi ci-dessous sont déduits des jeux publics de même nom :
> - **DEEP-VOICE** : voix réelles et voix converties par IA (RVC) de 8 personnalités, caractéristiques acoustiques par fenêtre d'une seconde ;
> - **Eedi** : questions de mathématiques à choix multiple, où chaque mauvaise réponse est reliée à une « misconception » (erreur de raisonnement).
>
> Ces deux lignes sont à confronter au sujet du projet dès que je l'ai.

## 2.1 — Classer selon l'AI Act

Références : règlement (UE) 2024/1689.

| Sujet | Usage du service | Niveau proposé | Article ou annexe invoqué | Ce qui ferait changer de niveau |
|---|---|---|---|---|
| ISIC approfondi | Trier les lésions photographiées pour signaler au dermatologue celles à examiner en priorité. Le médecin décide. | **Haut risque** | Art. 6(1) et annexe I, section A : le logiciel est un **dispositif médical** (règlement (UE) 2017/745, règle 11 : un logiciel qui fournit une information servant à une décision diagnostique est au moins de classe IIa), donc soumis à une évaluation de conformité par un organisme notifié. Obligations des art. 9 à 15 : gestion des risques, données, documentation, **journalisation (art. 12)**, contrôle humain (art. 14). | **Sortir** de la catégorie : un usage purement pédagogique ou de recherche, sans finalité médicale, n'est pas un dispositif médical. **Durcir** : un usage direct par le patient (auto-dépistage sans dermatologue) ferait monter la classe du dispositif médical et retirerait le contrôle humain sur lequel repose la conformité. |
| DEEP-VOICE | Détecter si un enregistrement de voix est authentique ou synthétique (deepfake), en aide à la vérification de contenus. | **Risque minimal** (pas de catégorie de l'annexe III) | Art. 6(2) et annexe III : la détection de deepfake n'y figure pas en elle-même. L'art. 50 vise ceux qui **produisent** des contenus synthétiques, pas ceux qui les détectent. | **Haut risque** si les **autorités répressives** l'utilisent pour évaluer la fiabilité d'une preuve (annexe III, point 6 c), ou s'il sert à l'asile et au contrôle aux frontières (point 7). Si le système **identifie le locuteur**, il relève de l'identification biométrique (annexe III, point 1), voire de l'art. 5 en temps réel dans l'espace public. |
| Eedi | Diagnostiquer l'erreur de raisonnement d'un élève à partir de sa mauvaise réponse, pour orienter l'enseignant. | **Haut risque** | Annexe III, point 3 b : des systèmes destinés à **évaluer les acquis d'apprentissage, y compris lorsqu'ils servent à orienter le processus d'apprentissage**. | **Abaisser** : si le système sert seulement à **étiqueter les questions** pour les auteurs, sans jamais évaluer un élève, l'art. 6(3) permet de plaider une tâche préparatoire ou procédurale, donc pas de haut risque. **Confirmer** : s'il alimente une note, une orientation ou une admission (point 3 a et c). La reconnaissance d'émotions des élèves serait **interdite** (art. 5(1) f). |

**Question 2.1 (ISIC approfondi, le sujet qui m'attire)**
DermaScan approfondi est un système d'IA **à haut risque**.
Le classement ne vient pas de la technique (un réseau de convolution), il vient de l'**usage** : le logiciel fournit à un dermatologue une information qui oriente une décision diagnostique. Il est donc un dispositif médical au sens du règlement 2017/745, de classe IIa au moins, et l'art. 6(1) avec l'annexe I le range en haut risque.
Ce niveau impose ce que la séance construit : un journal des inférences (art. 12), une traçabilité du modèle servi jusqu'aux données (art. 10 et 11), un contrôle humain (art. 14) et une gestion des risques documentée (art. 9).
L'usage qui le ferait changer : utilisé seulement pour la recherche ou l'enseignement, sans finalité médicale, il sortirait du dispositif médical et du haut risque. Mis entre les mains du patient seul, sans dermatologue, il resterait à haut risque mais perdrait le contrôle humain qui fonde notre conformité. Ce serait un usage que la model card exclut déjà.

## 2.2 — Ce que vous n'avez pas le droit de journaliser

Ligne de journal de S3 (`JOURNALISATION_INFERENCES.md`, 6.2) :
```json
{"ts":"2026-10-26T10:05:27.412Z","request_id":"6f1c2e9a-…","model_version":"1.0.0","image_digest":"sha256:cae2b635…006b","patient_ref":"3fa94c0d1b7e52a8","praticien_ref":"b81e07c94d2a6f35","lesion_id":"ISIC_0015670","probabilite_maligne":0.7509,"seuil_applique":0.34747330294391954,"seuil_source":"env:SEUIL","rappel_vise":0.9,"decision":"a_examiner","inference_ms":7,"http_status":200,"input_schema_version":"1"}
```

| Champ | Conservé ? | Transformation | Durée de conservation | Besoin nommé qui la justifie |
|---|---|---|---|---|
| `ts` | Oui | Aucune (UTC, à la milliseconde) | 90 jours en ligne, puis 10 ans en archive chiffrée et immuable | Reconstituer un incident et instruire une réclamation : la responsabilité médicale se prescrit par 10 ans (CSP art. L1142-28) |
| `request_id` | Oui | Aucune (UUID repris du poste ou généré) | Comme la ligne | Relier une réclamation du dossier à la ligne exacte |
| `model_version` | Oui | Aucune, mais **changer de contenu** : identifiant du registre (voir question 2.5) | Comme la ligne | Dire quel modèle a produit la réponse (AI Act art. 12) |
| `image_digest` | Oui | Aucune (digest, pas tag) | Comme la ligne | Dire quel code et quelle image ont tourné. C'est le digest de l'**image Docker**, pas celui d'une photo de patient |
| `patient_ref` | Oui | Pseudonymisé : SHA-256 de (sel secret + `patient_id`), 16 caractères hexadécimaux. Sel dans Key Vault, versionné | 90 jours en ligne, 10 ans en archive, puis **destruction du sel** de la période, ce qui rend l'archive anonyme | Retrouver toutes les inférences d'un patient en cas de réclamation ou de droit d'accès (RGPD art. 15) |
| `probabilite_maligne` | Oui | Arrondie à 4 décimales | Comme la ligne | Expliquer la décision par rapport au seuil et la recalculer sous un autre seuil. C'est une donnée de santé **inférée** (art. 9) |
| `decision` | Oui | Aucune (`a_examiner` / `surveillance`) | Comme la ligne | C'est ce que le praticien a vu, donc ce qui est contesté |
| `covariables` | **Non**, pas dans le journal d'inférence | Retirées de la ligne. Dans un **journal de dérive séparé**, sans aucun identifiant : valeurs arrondies, âge par pas de 5 ans, date sans l'heure | Journal de dérive : 13 mois, puis histogrammes mensuels agrégés | Surveiller la dérive (S5). Ce besoin n'exige pas de savoir à quel patient appartiennent les valeurs |

`praticien_ref` (pseudonymisé avec un sel distinct), `seuil_applique` et `seuil_source` restent dans la ligne pour les mêmes raisons d'audit. L'adresse IP, l'image, les jetons et le sel ne sont **jamais** journalisés.

**Question 2.2** — Non. Un hachage ne pseudonymise qu'un **identifiant**. L'image, elle, reste une donnée de santé, identifiante par elle-même (grains de beauté, cicatrices, tatouages). Son hachage n'en serait qu'une empreinte, qui permettrait de relier la ligne à la photo détenue ailleurs, donc une donnée personnelle, et qui ne servirait à rien d'autre : le moindre réencodage change l'empreinte.
Il est donc interdit de journaliser l'image elle-même, ses pixels, une miniature, son empreinte ou un vecteur qui en est extrait. On journalise seulement la décision, avec `lesion_id` pour retrouver l'image dans le dossier du centre.

**Question 2.3** — Avec des données réelles, chaque ligne du journal devient un **traitement de données de santé** (RGPD art. 9). Il faut alors une base légale (art. 9.2.h, prise en charge médicale), une analyse d'impact (AIPD), une inscription au registre des traitements, l'information des patients et un hébergement certifié HDS en France.
Le journal doit être chiffré, avec un accès nominatif et tracé. Le sel reste dans Key Vault avec une rotation datée, et la rétention est **appliquée par la plateforme** (Log Analytics, stockage), pas seulement dans le code. Aucune ligne ne doit se retrouver dans Git, une capture ou un poste personnel.
Les métriques de dérive passent par le journal agrégé sans identifiant. C'est le brouillon de la page H3.

## 2.3 — Une ligne de journal mène au commit

Parcours fait à l'envers, de la ligne de S3 jusqu'au code, avec le suivi de la partie 1.

| Maillon | Identifiant qui mène au suivant | Où il est écrit | Présent aujourd'hui ? |
|---|---|---|---|
| Ligne de journal | `image_digest` (`sha256:cae2b635…006b`) et `model_version` (`1.0.0`) | Journal applicatif (logs App Service, puis Log Analytics en S5) | **En archive seulement** : l'App Service de S3 est détruit. Les lignes subsistent dans `s3-…/logs/logs_s3.zip` (IP masquée) |
| Image | Le digest mène à l'image. L'image devrait porter la version du registre (label `org.opencontainers.image.version` ou `modele_meta.json` embarqué) | Registre ACR `acrdermascansm26` (tags 1.0.0, 2.0.0, 2.1.0) | **Oui** pour l'image. **Rompu** vers le registre : l'image 1.0.0 ne porte ni `run_id` ni version `dermascan-tabulaire vN` |
| Version de modèle au registre | `run_id` de la version, et son tag `sha256_modele` | `poste/suivi/mlflow.db`, table `model_versions` (alias `production` = v2, `repli` = v1) | **Oui** (registre de la séance 6) |
| Run | Tag `sha256_manifeste` (`e3da1f52…`), paramètre `graine` | `poste/suivi/mlflow.db` (runs, tags), artefacts dans `poste/suivi/artefacts/` | **Oui**, vérifié par `verifier_chaine.py` (maillons 2 et 3) |
| Manifeste de données | `sha256` du CSV (`536e8208…`) et `commit` | `poste/donnees/manifeste.json` | **Oui**, vérifié (maillon 4) |
| Commit du code | Le hash du commit Git | Champ `commit` du manifeste, et tag `commit` du run | **Non** : `hors-git` |

**Question 2.4** — Le maillon rompu est le **dernier**, du manifeste vers le commit du code. `preparer.py` a tourné hors d'un dépôt Git, donc rien ne relie les données et les découpages à une version du code.
Le geste de la partie 3 qui le répare : créer le dépôt (`git init`), **commiter les scripts avant de les lancer**, puis relancer `preparer.py` depuis le dépôt. Le manifeste et chaque run porteront alors un vrai hash de commit.

**Question 2.5** — Il faut écrire la version du registre **dans le paquet au moment de la promotion** (`modele_meta.json` : `registre: "dermascan-tabulaire"`, `version: 2`, `run_id`, `sha256_modele`), et que l'API journalise `model_version = "dermascan-tabulaire@v2"` et `sha256_modele` **lus dans le paquet**.
La jointure ligne de journal → registre se fait alors directement sur `sha256_modele`, que le registre garde déjà en tag de chaque version.
