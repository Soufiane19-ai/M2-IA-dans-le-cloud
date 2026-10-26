# Journalisation des inférences — Séance 3

Soufiane Meskine, M2 YNOV Montpellier, 26/10/2026.

Point de départ mesuré en partie 4.1 : l'API de S2 n'écrit **aucune** ligne applicative. Les logs ne contiennent que la ligne d'accès de gunicorn (méthode, chemin, code, taille, agent), sans la charge utile, sans la probabilité, sans le seuil. Aujourd'hui, une réclamation sur une décision de DermaScan serait donc **impossible à instruire** : on saurait qu'un `POST /predict` a reçu un 200 à telle heure, rien de plus. Ce document définit ce que l'API devrait écrire.

## 6.1 — Grille : que journaliser, que ne jamais journaliser

| Donnée | Journaliser ? | Forme | Justification |
|---|---|---|---|
| Horodatage de la requête, en UTC | Toujours | Brut | Sans ordre temporel, aucune reconstitution d'incident n'est possible |
| Identifiant de corrélation de la requête | Toujours | Brut, généré si absent | Seul moyen de relier une ligne de log à une réclamation client |
| Version du modèle et digest de l'image | Toujours | Brut | Répond à « quel modèle a produit cette réponse », question n° 1 d'un audit |
| Identifiant du patient (`patient_id`) | Toujours, **jamais en clair** | Pseudonymisé : `patient_ref` = SHA-256(sel + identifiant), 16 caractères hexadécimaux | Indispensable pour retrouver les inférences d'un patient lors d'une réclamation et regrouper ses lésions ; en clair, il ferait du journal un fichier de santé nominatif |
| Identifiant de la lésion (`isic_id`) | Toujours | Brut (identifiant d'image interne au centre, non nominatif) | Relie la décision à la lésion examinée, donc à l'image et au dossier ; sans lui on ne sait pas **quelle** lésion a été classée en surveillance |
| Âge et sexe (`age_approx`, `sex`) | **Jamais** dans le journal d'inférence | — (seulement en agrégé, dans le journal de dérive, voir 6.2) | Quasi-identifiants : croisés avec `patient_ref`, le site et la date, ils facilitent la réidentification ; ils sont déjà dans le dossier médical, inutile de les dupliquer |
| Site anatomique (`anatom_site_general`) | **Jamais** dans le journal d'inférence | — (agrégé, journal de dérive) | Même raison : quasi-identifiant et donnée de santé ; retrouvable par `isic_id` dans le dossier si besoin |
| Valeurs brutes des variables morphologiques (`tbp_lv_*`) | **Jamais** dans le journal d'inférence | — (arrondies et sans identifiant, journal de dérive) | 35 valeurs par ligne, données de santé, qui feraient du journal une copie du dossier ; utiles seulement pour la dérive, qui n'a pas besoin de savoir à quel patient elles appartiennent |
| Probabilité maligne prédite | Toujours | Nombre à 4 décimales | Cœur de l'audit : seule elle permet de dire si la décision était proche du seuil, et de recalculer la décision sous un autre seuil |
| Seuil appliqué et rappel visé | Toujours | Brut (valeur effective + source) | Une décision sans son seuil n'est pas explicable : c'est la question « quel seuil était appliqué ce jour-là ? » |
| Décision rendue (`a_examiner` / `surveillance`) | Toujours | Brut | C'est ce que le praticien a vu, donc ce qui est contesté |
| Latence d'inférence | Toujours | Millisecondes, entier | Supervision de la performance et preuve qu'une réponse a bien été rendue dans les délais |
| Code HTTP et message d'erreur éventuel | Toujours | Code brut ; message **réduit au type d'erreur** et aux **noms** de variables manquantes, jamais à leurs valeurs | Diagnostic des appels refusés ; un message d'erreur qui recopierait la charge reviendrait à journaliser la charge |
| Adresse IP source de l'appel | **Jamais** dans le journal d'inférence | — (reste dans le journal d'accès de la plateforme, durée courte) | Donnée personnelle sans utilité pour l'audit d'une décision ; de toute façon, App Service ne la donne pas au conteneur (`169.254.130.1`) |
| Identité du praticien ayant déclenché l'appel | Toujours | Pseudonymisée (`praticien_ref`, même transformation, sel distinct) | Une réclamation demande qui a vu la décision ; l'identité nominative se retrouve via l'annuaire du centre, pas dans le journal |
| Jeton d'authentification ou clé d'API | **Jamais** | — | C'est un secret : journalisé, il permet de se faire passer pour le poste ; au plus l'identifiant (non secret) de la clé utilisée |
| Sel de pseudonymisation `INFERENCE_LOG_SALT` | **Jamais** | — | S'il fuit avec le journal, la pseudonymisation de 1 042 identifiants se renverse par force brute en quelques secondes |

**Question 6.1**
1. **Variables `tbp_lv_*` seules, sans aucun identifiant : ni l'un ni l'autre**, tant qu'aucun moyen raisonnable ne permet de remonter à une personne (considérant 26 du RGPD). Ce sont des mesures d'une tache de peau, qui deviennent anonymes une fois détachées de tout contexte. La réserve : un vecteur de 35 mesures précises est quasi unique, et peut redevenir identifiant pour qui possède la base de la cabine.
2. **Les mêmes, associées à `patient_id` : article 9.** `patient_id` rend la personne identifiable (pseudonymisée, donc toujours une donnée personnelle, considérant 26), et la description d'une lésion cutanée examinée dans un dépistage du cancer est une donnée concernant la santé (art. 4.15). Avec jusqu'à 9 184 lésions pour un même patient, on obtient une véritable cartographie de sa peau.
3. **Les mêmes, associées à `age_approx`, `sex` et `anatom_site_general`, sans `patient_id` : article 9**, dès lors qu'une réidentification est raisonnablement possible, ce qui est le cas dans un centre donné (voir 6.2). Ces trois variables ne sont pas identifiantes isolément, mais leur croisement avec des mesures précises de la lésion isole souvent une seule personne, et l'objet du traitement reste la santé.
4. **Probabilité maligne associée à un patient identifiable : article 9.** Qu'elle soit **produite** par DermaScan et non collectée ne change rien à la qualification : une donnée inférée sur une personne identifiable est une donnée personnelle, et une estimation de risque de cancer est une donnée concernant la santé. Cela ajoute même des obligations : DermaScan est responsable de son exactitude, la personne peut y accéder, et une décision automatisée produisant des effets significatifs relève de l'article 22. Le dermatologue dans la boucle est ce qui nous en sépare.

**Question 6.2** — À mon estimation, **trois à quatre variables croisées** suffisent dans un centre donné : âge approché (par pas de 5 ans), sexe, site anatomique et taille de la lésion au millimètre isolent rapidement une seule personne parmi quelques centaines de patients, et les jeunes ou les grands âges sont uniques dès deux variables. La mesure qu'il faudrait calculer est le **k-anonymat** : pour chaque combinaison de quasi-identifiants, la taille de la plus petite classe d'équivalence (nombre de patients qui partagent exactement ces valeurs). Un patient seul dans sa classe (k = 1) est réidentifiable. On la complète par la **l-diversité** (diversité des valeurs sensibles dans une classe) ou par la proportion d'enregistrements uniques.

**Question 6.3** — Si le journal fuyait, voici ce que l'attaquant tirerait de chaque ligne marquée « Toujours » :

| Ligne « Toujours » | Ce que l'attaquant en tire |
|---|---|
| Horodatage UTC | Rythme d'activité du centre |
| Identifiant de corrélation | Rien d'exploitable seul |
| Version du modèle, digest | Version à cibler, sans plus |
| `patient_ref` pseudonymisé | Regroupement des lésions d'un même patient, **sans son identité** tant que le sel ne fuit pas |
| `isic_id` | Rien hors du centre ; avec le système d'information du centre, l'image de la lésion |
| Seuil, rappel visé | Paramètre du produit (concurrence) |
| Décision | Liste des lésions jugées suspectes |
| Latence | Capacité du service |
| Code HTTP, type d'erreur | Points faibles de l'API |
| `praticien_ref` | Activité par praticien, pseudonyme |

Aucune ligne ne lui donne un avantage sérieux **tant que le sel est ailleurs** : c'est pour cela que le sel, les jetons et les variables cliniques sont marqués « Jamais ».

**Cas de la probabilité maligne.** Une fuite de prédiction n'est **pas moins grave** qu'une fuite de diagnostic, et elle est d'une autre nature. Moins précise, elle peut être fausse : un faux positif à 0,75 étiquette une personne saine comme « suspecte de mélanome », sans le correctif clinique qui suit (biopsie, avis du dermatologue). Une fois rattachée à une personne, c'est une information de santé stigmatisante, qui intéresse un assureur ou un employeur. Le pseudonymat de `patient_ref` est ici la seule barrière : ce qui protège vraiment, c'est l'absence du sel dans le journal.

## 6.2 — Format de ligne et pseudonymisation

Une ligne JSON par inférence (JSON Lines), écrite sur la sortie standard et collectée par la plateforme :

```json
{"ts":"2026-10-26T10:05:27.412Z","request_id":"6f1c2e9a-3b47-4d1e-9a51-0c2f7d8e4b13","model_version":"1.0.0","image_digest":"sha256:cae2b6358fcfc65751d85a16536efb9ae660b5b26782e56f98fdcaedb310006b","patient_ref":"3fa94c0d1b7e52a8","praticien_ref":"b81e07c94d2a6f35","lesion_id":"ISIC_0015670","probabilite_maligne":0.7509,"seuil_applique":0.34747330294391954,"seuil_source":"env:SEUIL","rappel_vise":0.9,"decision":"a_examiner","inference_ms":7,"http_status":200,"input_schema_version":"1"}
```

| Champ | Forme | Ma décision |
|---|---|---|
| `ts` | horodatage UTC ISO 8601 à la milliseconde | Imposé |
| `request_id` | UUID | Repris de l'en-tête `X-Request-ID` envoyé par le poste de consultation s'il existe (il est alors aussi dans le dossier, ce qui relie réclamation et log) ; sinon **UUID v4 généré par l'API**, et renvoyé dans l'en-tête de réponse pour que le poste puisse le conserver |
| `model_version` | `1.0.0` | Lue dans le **paquet sérialisé**, pas dans l'environnement : la partie 3 a montré que `MODEL_VERSION=1.0.0-azure` (environnement) et `1.0.0` (paquet) peuvent diverger ; seul le paquet dit ce qui a réellement prédit |
| `image_digest` | `sha256:…` | Le **digest**, pas le tag : un tag est mobile (question 2.1), seul le digest identifie le code et le modèle exécutés. Injecté au déploiement dans une variable d'environnement (`IMAGE_DIGEST`) par le pipeline qui déploie par digest |
| `patient_ref` | 16 caractères hexadécimaux | Pseudonymisation décrite ci-dessous ; l'identifiant arrive hors charge utile, dans l'en-tête `X-Patient-Ref` |
| `probabilite_maligne` | **4 décimales** | 4 décimales suffisent pour situer une décision par rapport au seuil (0,3475) et pour construire des histogrammes de dérive fins ; garder plus n'apporte rien et facilite le rapprochement ligne à ligne. Arrondir à 1 ou 2 décimales ferait perdre la distribution des petites probabilités, où vivent 99,9 % des lésions (prévalence 0,1 %), et rendrait toute analyse de dérive de la sortie aveugle |
| `seuil_applique` | flottant complet | Le seuil **effectivement appliqué**, avec sa source dans `seuil_source` : `env:SEUIL` (réglage d'application, peut changer sans redéploiement, 3.3) ou `paquet` (valeur figée à l'entraînement). Les deux ne disent pas la même chose : le paquet dit ce qui a été validé, l'environnement ce qui a été appliqué ; un écart entre les deux est exactement ce qu'un audit cherche |
| `decision` | `a_examiner` ou `surveillance` | Vocabulaire de la séance 2, inchangé : jamais « bénin » ni « malin », le modèle trie, il ne diagnostique pas |
| `inference_ms` | entier | Le temps de `predict_proba` seul (pipeline de prétraitement inclus), chronométré par `time.perf_counter()` autour de l'appel du modèle ; ni la validation de la charge, ni le réseau, ni la file de gunicorn, qui se lisent dans les métriques de la plateforme |
| `http_status` | `200`, `400`… | — |
| `input_schema_version` | `"1"` | À incrémenter dès que le contrat d'entrée change : ajout, retrait ou renommage d'une des 40 variables, changement d'unité ou d'encodage d'une modalité, nouvelle catégorie attendue. Un nouveau modèle entraîné sur les mêmes 40 variables ne l'incrémente pas |

**Covariables pour la dérive (séance 5).** Je ne mets **aucune** covariable dans le journal d'inférence, et je crée un **second dispositif** : un **journal de dérive** séparé, alimenté par l'API à chaque inférence réussie. Chaque ligne contient les 40 variables d'entrée, les numériques arrondies (2 décimales, âge par pas de 5 comme dans le jeu), plus `probabilite_maligne`, `model_version` et la **date seule** (jour, sans heure). Elle ne contient ni `patient_ref`, ni `request_id`, ni `lesion_id`, ni praticien. Ce journal sert à comparer la distribution servie à celle de l'entraînement, sans pouvoir être relié au journal d'inférence ni à un patient. Il est conservé 13 mois puis remplacé par des histogrammes agrégés par mois. Ce découplage garde la séance 5 possible sans faire du journal d'audit un fichier de santé complet. Ses limites : sans identifiant, il est impossible de dédoublonner les lésions d'un même patient, et le croisement des variables d'une même ligne reste un quasi-identifiant faible (6.2), d'où l'accès restreint.

**Pseudonymisation de `patient_id`.**

```python
import hashlib
import os

def pseudonymiser(patient_id: str) -> str:
    """patient_ref stable dans le temps, mais non réversible sans le sel."""
    SEL = os.environ["INFERENCE_LOG_SALT"]      # jamais en dur dans le code
    return hashlib.sha256(f"{SEL}:{patient_id}".encode("utf-8")).hexdigest()[:16]
```

On concatène le sel lu dans l'environnement, un séparateur et l'identifiant ; on hache en SHA-256 ; on garde les **16 premiers caractères hexadécimaux** (64 bits : aucune collision attendue en dessous de plusieurs centaines de millions de patients). Le même calcul, avec un sel distinct, produit `praticien_ref`.

**Question 6.4**
1. **Le sel est indispensable** parce que l'espace des identifiants est minuscule et prévisible. Les identifiants ISIC suivent un format régulier (`IP_` suivi de 7 chiffres, soit 10⁷ valeurs possibles), et le jeu ne compte que 1 042 patients : un attaquant calcule `sha256` des 10 millions d'identifiants possibles en quelques secondes sur un portable et inverse tout le journal. Un hachage sans sel n'est qu'un changement d'écriture. Avec un sel secret de 128 bits, il faudrait d'abord deviner le sel, ce qui est hors de portée.
2. **La stabilité est nécessaire** : un même patient porte des dizaines à des milliers de lésions, et une réclamation porte sur **un patient**. Il faut pouvoir retrouver toutes ses inférences, compter les alertes par patient, et suivre une lésion d'une visite à l'autre. **C'est aussi une faiblesse** : elle permet de relier toutes les lignes d'une même personne. Un profil complet (dates de visite, nombre de lésions, décisions) se reconstruit sans connaître son nom, et il suffit d'un seul lien externe (une date de rendez-vous connue) pour le nommer.
3. **Seul le centre de dépistage** (le responsable de traitement qui détient `patient_id` et le dossier), et chez DermaScan seulement le délégué à la protection des données ou un rôle d'audit nommé, sur demande tracée, doivent pouvoir remonter de `patient_ref` à `patient_id`. Le moyen n'est **pas** de « déhacher » : c'est de recalculer `pseudonymiser(patient_id)` pour l'identifiant fourni par le centre et de chercher ce `patient_ref` dans le journal. Cela demande l'accès au sel, conservé dans Key Vault et lisible par l'application et par ce seul rôle d'audit (accès journalisé). Aucune table de correspondance stockée.
4. **Si le sel tourne**, tout l'historique devient **impossible à relier** aux nouveaux `patient_ref` : les mêmes patients reçoivent d'autres pseudonymes, et retrouver les anciennes inférences d'un patient exige l'ancien sel. Si l'ancien sel est détruit, le journal historique devient de fait **anonymisé**. C'est **une propriété recherchée**, à condition d'être décidée : c'est le mécanisme qui permet d'appliquer une durée de conservation de la capacité de réidentification. Ce serait un défaut si la rotation était accidentelle pendant la période où l'audit doit rester possible. Il faut donc versionner les sels (`sel_version` dans la ligne) et ne détruire un sel qu'à l'échéance de conservation des lignes qu'il protège.

## 6.3 — Durées de conservation

| Catégorie de trace | Durée de conservation | Besoin qui la justifie | Ce qui se passe à l'échéance |
|---|---|---|---|
| Journal d'inférence complet (pseudonymisé) | **90 jours en ligne**, puis **10 ans en archive** chiffrée, immuable, à accès restreint | En ligne : enquêtes d'incident et réclamations récentes. Archive : la responsabilité médicale se prescrit par 10 ans à compter de la consolidation du dommage (art. L1142-28 du Code de la santé publique), et le patient du scénario revient « six mois plus tard » : il faut pouvoir dire quelle probabilité et quel seuil lui ont été appliqués | Purge automatique des lignes, puis **destruction du sel** de la période : ce qui subsisterait dans une copie oubliée devient non réidentifiable |
| Journal d'erreurs applicatives | **90 jours** | Diagnostic et correction des défauts ; au-delà, un défaut non corrigé est suivi dans un ticket, pas dans un log | Suppression ; les comptages d'erreurs survivent dans les métriques agrégées |
| Métriques agrégées, sans identifiant | **5 ans** | Tendances de performance, de volume et de dérive (taux d'alertes par semaine, distribution des probabilités), comparaison entre versions de modèle, preuve de qualité sur la durée du marquage du dispositif | Suppression, ou conservation sans limite si elles sont réellement non identifiantes (agrégats d'au moins k patients) |
| Journal d'accès de la plateforme (lignes gunicorn, frontal) | **30 jours** | Sécurité (détection d'abus, attaques) et exploitation à court terme ; il ne contient ni patient, ni décision | Rotation automatique par la plateforme (rétention des logs App Service et de l'espace Log Analytics réglée à 30 jours) |

**Question 6.5** — Les deux exigences sont la **minimisation des données** et la **limitation de leur conservation** (RGPD art. 5.1.c et 5.1.e : ne garder que le nécessaire, pas plus longtemps que nécessaire), d'un côté, et la **capacité d'audit a posteriori** (responsabilité, art. 5.2 ; traçabilité exigée d'un dispositif médical et d'un système d'IA à haut risque), de l'autre. Le mécanisme qui satisfait les deux est l'**agrégation**, combinée à la **pseudonymisation à durée de vie limitée** : on garde longtemps des **métriques agrégées sans identifiant** (troisième ligne de la grille) qui répondent aux questions statistiques de l'audit (le modèle a-t-il dérivé ? combien d'alertes ?), et on ne garde le détail ligne à ligne que sous pseudonyme, avec un sel détruit à l'échéance, ce qui transforme l'archive en données anonymes.

**Question 6.6** — La purge doit être configurée **là où les données sont stockées, au niveau de la plateforme** : la rétention de l'espace **Log Analytics** (ou du compte de stockage, par une **politique de gestion du cycle de vie** qui supprime les objets au-delà de N jours), et la rétention des logs App Service (`az webapp log config … --docker-container-logging filesystem` avec une durée de rétention, ou envoi vers un stockage soumis à cette politique). Si je la configure **seulement dans mon code applicatif**, je ne purge que ce que mon code gère. Toutes les copies tenues par la plateforme survivent : fichiers `/home/LogFiles` (l'archive `logs_s3.zip` le montre), flux vers Log Analytics, sauvegardes, exports. Elles survivent avec leur propre durée, souvent bien plus longue. La donnée est alors conservée au-delà de la durée annoncée, ce qui viole la limitation de conservation, et je l'affirmerais faussement dans le registre des traitements.
