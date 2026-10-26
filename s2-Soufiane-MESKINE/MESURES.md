# Séance 2 — Mesures 6 à 17 et questions 2.1 à 6.1

Soufiane Meskine · M2 YNOV Montpellier · suffixe `sm26`

| Décision | Valeur |
|---|---|
| Suffixe | `sm26` |
| Groupe du registre | `rg-dermascan-registre-sm26` |
| Registre ACR | `acrdermascansm26` |
| Rappel visé (fixé avant toute mesure) | **0,90** |
| Étiquette `a_detruire` | 2027-06-30 |

> Entraînement et tests locaux : environnement virtuel Python 3.12.7 (même version que l'image), sortie complète de `entrainer.py` reproduite par la commande `python3 entrainer.py`. Partie 4 : mesures relevées sur le poste Windows (Docker Desktop), journal `logs/sortie_s2.log`.

## Partie 2 — Pipeline

### 2.1 — Découpage sans fuite

Paramètres : `GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)`, `groups=patient_id`. L'assertion `not (set(groupes[train]) & set(groupes[test]))` passe : aucun patient n'est des deux côtés.

#### Mesure 6

| Relevé | Entraînement | Test |
|---|---|---|
| Nombre de lignes | 319 514 | 81 545 |
| Nombre de patients | 833 | 209 |
| Nombre de positifs | 283 | 110 |
| Taux de positifs | 0,0886 % | 0,1349 % |

**Question 2.1** — Non : 0,089 % contre 0,135 %, le test contient 1,5 fois plus de malignes en proportion. `GroupShuffleSplit` tire des **patients** au hasard sans regarder la cible. Or les 393 malignes sont concentrées chez quelques patients, donc le nombre de positifs qui tombent dans le test dépend fortement du tirage. Mesuré sur 5 graines : **57, 84, 86, 87 et 110 positifs** dans le test (taux de 0,079 % à 0,135 %). Conséquence : avec quelques dizaines à une centaine de positifs, chaque métrique (rappel, précision, PR-AUC, seuil) est **instable d'une graine à l'autre**, puisqu'un seul cas manqué de plus fait varier le rappel d'environ un point. Il faut donc rapporter une moyenne et un écart sur plusieurs graines, ou utiliser `StratifiedGroupKFold`, qui équilibre la cible tout en respectant les groupes.

### 2.2 — Construction du pipeline

Paramètres : numériques `SimpleImputer(strategy="median")` puis `StandardScaler` ; catégorielles `SimpleImputer(strategy="most_frequent")` puis `OneHotEncoder(handle_unknown="ignore")`. Il y a 35 variables numériques et 5 catégorielles (`sex`, `anatom_site_general`, `tbp_tile_type`, `tbp_lv_location`, `tbp_lv_location_simple`).

**Question 2.2** — Avec `handle_unknown="error"` (le défaut), une position anatomique jamais vue lève `ValueError: Found unknown categories` : la requête échoue et la lésion n'est pas triée du tout. Avec `"ignore"`, la modalité inconnue est encodée comme un vecteur de zéros : le modèle prédit à partir des 39 autres variables, et cette variable ne contribue plus. Pour un service de tri médical, je retiens **`ignore`**. Une lésion non évaluée est le pire résultat (elle sort du circuit sans alerte), alors qu'une prédiction un peu moins informée reste exploitable. En contrepartie, on journalise ces modalités inconnues pour la surveillance de dérive (séance 5).

**Question 2.3** — Parce que l'imputation **apprend** quelque chose (une médiane, une modalité la plus fréquente). Si on l'applique au tableau complet avant le découpage, ces statistiques sont calculées en partie sur les lignes de test : les valeurs du test entrent dans le modèle et son évaluation n'est plus faite sur des données réellement inconnues. En tant qu'étape du pipeline, elle n'apprend que sur `X.iloc[train]`, et le même traitement figé s'applique ensuite en production.

### 2.3 — Entraînement et piège de l'exactitude

Paramètres : `class_weight="balanced"`, `DummyClassifier(strategy="most_frequent")`, `predict_proba(...)[:, 1]`, hasard `y[test].mean()`.

#### Mesure 7

| Modèle | Exactitude | ROC-AUC | PR-AUC |
|---|---|---|---|
| `DummyClassifier` | **0,9987** | 0,5000 | 0,0013 |
| Régression logistique | 0,8490 | **0,9097** | **0,0551** |
| Valeur du hasard pour la PR-AUC | — | — | 0,00135 |

**Question 2.4** — Selon l'exactitude, le meilleur est le `DummyClassifier` (99,87 % contre 84,90 %). En réalité, c'est la régression logistique : le Dummy ne trouve **aucune** maligne, alors que la régression place une maligne au-dessus d'une bénigne dans 91 % des paires (ROC-AUC 0,91) et a une PR-AUC 41 fois supérieure au hasard. L'exactitude compte toutes les bonnes réponses avec le même poids. Avec 99,87 % de bénignes dans le test, elle mesure surtout la capacité à dire « bénin ». Elle ne compte pas ce qui coûte : les malignes manquées (faux négatifs), qui ne pèsent que 0,13 % du total. Avec `class_weight="balanced"`, le modèle accepte de nombreux faux positifs pour attraper les malignes, ce qui fait **baisser** l'exactitude au moment même où il devient utile.

**Question 2.5** — Vérifié : PR-AUC du Dummy = 0,0013 = taux de positifs du test (110 / 81 545 = 0,00135). Un modèle qui ne sait rien a une précision égale à la prévalence, quel que soit le seuil. La ROC-AUC combine le taux de vrais positifs et le taux de **faux positifs**, rapporté aux 81 435 négatifs. Avec autant de négatifs, même 12 000 fausses alertes ne font qu'un taux de faux positifs de 15 %, et la ROC-AUC reste flatteuse (0,91). La PR-AUC utilise la **précision**, qui met les faux positifs en regard des vrais positifs : c'est exactement ce que paie le dermatologue. Elle part de la prévalence (0,13 %) et non de 0,5 : 0,055 dit clairement que le problème est loin d'être résolu, ce que 0,91 cache.

### 2.4 — Choix du seuil

#### Mesure 8 — compromis rappel / précision (test, 110 malignes, 81 545 lésions)

| Seuil | Rappel | Précision | Vrais positifs | Faux positifs | Faux négatifs | Alertes pour 1000 lésions |
|---|---|---|---|---|---|---|
| 0,50 | 0,818 | 0,0073 | 90 | 12 293 | 20 | 151,9 |
| 0,80 | 0,618 | 0,0155 | 68 | 4 310 | 42 | 53,7 |
| 0,90 | 0,473 | 0,0218 | 52 | 2 333 | 58 | 29,2 |
| 0,99 | 0,182 | 0,0488 | 20 | 390 | 90 | 5,0 |

Paramètres : `np.where(rappel >= 0.90)[0][-1]`. Je prends le **dernier** indice qui atteint encore 0,90 : `rappel` décroît quand le seuil croît, donc c'est le seuil le plus haut qui garantit le rappel visé, celui qui donne le moins d'alertes.

#### Mesure 9

| Relevé | Valeur |
|---|---|
| Rappel visé, décidé en début de séance | 0,90 |
| Seuil correspondant | **0,3475** |
| Précision à ce seuil | 0,0051 (0,51 %) |
| **Nombre de lésions examinées par maligne trouvée** | **198** |
| Faux négatifs restants | 11 sur 110 |

**Question 2.6** — « Pour trouver 9 cancers sur 10, ce modèle demande à vos dermatologues d'examiner environ **198 lésions pour une maligne**. Il signale 240 lésions sur 1 000 : il retire donc les trois quarts du volume tout en laissant passer une maligne sur dix (11 sur 110 dans notre test). » S'il juge 198 inacceptable, je lui réponds qu'il y a deux leviers, et que c'est à lui de choisir. Le premier : baisser l'exigence de rappel. Calculé sur le même test, à 0,80 on passe à **128** lésions par maligne trouvée (138 alertes pour 1 000), mais deux malignes sur dix sont manquées. À l'inverse, à 0,95, il en faudrait **338**. Ce choix est clinique et lui revient, pas à moi. Le second : améliorer le modèle (images en séance 4, modèle plus riche). Ce que je refuse, c'est de baisser le chiffre en cachant le rappel : c'est le couple « 198 lésions, 1 maligne sur 10 manquée » qui se décide.

**Question 2.7** — Sur des lésions comparables à celles de l'entraînement, ce service signale au dermatologue 90 % des lésions malignes et en laisse passer 10 % : il trie, il ne garantit pas qu'une lésion non signalée est bénigne.

### 2.5 — Sérialisation avec métadonnées

Champs du paquet : `version` « 1.0.0 », `colonnes_attendues` (liste des 40), `seuil` 0,3475, `rappel_cible` 0,90, `metriques` (PR-AUC, ROC-AUC, hasard, rappel, précision, faux négatifs), `prevalence_entrainement` 0,000886, `entraine_le` (date UTC ISO), et en plus `versions` (python, scikit-learn, pandas, numpy, joblib) et `donnees` (source, volumétrie, graine).

#### Mesure 10

| Relevé | Valeur |
|---|---|
| Taille du fichier | 9,5 Ko |
| Nombre de colonnes attendues déclarées | 40 |
| Durée de l'entraînement | 18,4 s |

**Question 2.8** — Elle ne sert à aucun calcul de prédiction, mais c'est la **référence** du flux d'entraînement. En séance 5, on comparera la part de lésions signalées et, quand les diagnostics reviendront, la prévalence observée à 0,089 %. Un écart fort indique que la population a changé (autre type de consultation, autre cabine). Dans ce cas, la précision et le seuil calculés ici ne valent plus, et l'alerte de dérive se fonde sur ce chiffre. Sans lui dans le paquet, il faudrait retrouver les données d'entraînement pour savoir à quoi comparer.

**Question 2.9** — (1) L'API ne peut pas **valider** la charge utile : elle ne sait pas quelles variables exiger, donc une requête incomplète arrive au pipeline et produit une erreur 500, au lieu d'un 400 qui nomme les variables manquantes. (2) Elle ne peut pas **construire la ligne dans le bon ordre** ni ignorer les champs en trop : le `DataFrame` passé au `ColumnTransformer` dépendrait de ce que le client envoie. Un champ en trop, absent ou mal nommé donnerait une erreur, et `/model/info` ne pourrait pas publier le contrat aux équipes clientes.

## Partie 3 — API d'inférence

Paramètres : `MODEL_PATH` par défaut `model/modele.joblib`, `PAQUET["seuil"]`, erreur `"variables manquantes"` avec le code `400`, décision `"a_examiner"` / `"surveillance"`.

**Question 3.1** — Le paquet pèse 9,5 Ko. Le recharger coûte **1,4 ms** à chaud, mesuré sur 5 chargements une fois scikit-learn importé, soit environ +12 % sur une prédiction d'environ 12 ms. Mais le premier chargement dans un processus coûte **1,2 s**, à cause de l'import de scikit-learn et pandas, et chaque requête relirait le disque, soit autant d'occasions d'échouer en plein trafic. On charge une fois au démarrage : le coût est payé une seule fois, et un modèle illisible est détecté par `/health`, et non par un client.

### Mesure 11 — réponses de l'API (tests locaux, `PORT=8000 python3 app.py`, puis confirmés dans le conteneur)

| Appel | Code HTTP | Élément relevé |
|---|---|---|
| `GET /health` | 200 | `model_loaded: true` |
| `GET /model/info` | 200 | 40 colonnes attendues |
| `POST /predict`, charge valide | 200 | `probabilite_maligne` 0,750853, `decision` « a_examiner » (une lésion maligne réelle du test) |
| `POST /predict`, charge incomplète | 400 | 30 variables manquantes signalées (les 10 premières listées) |
| `POST /predict`, corps vide | 400 | `"corps JSON absent ou invalide"` |

Dans le conteneur (`captures/predict_conteneur.txt`) : `/health` 200 (`model_loaded: true`, servi par gunicorn), `/predict` valide 200 avec la même probabilité 0,750853, charge incomplète 400 avec 30 variables manquantes. Le test « corps vide » n'a pas pu être rejoué depuis PowerShell, qui supprime l'argument vide de `curl.exe -d ""`. Le comportement 400 est celui mesuré en local, avec le même `app.py`.

### Mesure 12 — latence de dix appels successifs (charge valide)

| Contexte | Minimum | Médiane | Maximum |
|---|---|---|---|
| Local, serveur Flask | 9,4 ms | 11,6 ms | 13,5 ms |
| Conteneur sur le poste Windows (gunicorn, 2 workers) | 111,5 ms | 185,0 ms | 321,3 ms |

L'écart vient de la mesure, pas du modèle. Côté conteneur, chaque appel traverse `curl.exe` sous Windows, puis la redirection de port de Docker Desktop (WSL2) jusqu'au conteneur, et gunicorn ferme la connexion à chaque requête. Le calcul de la prédiction lui-même reste autour de 10 ms, comme en local.

**Question 3.2** — La décision seule ne dit pas **avec quelle règle** elle a été prise. Dans six mois, le seuil aura peut-être été relevé ou abaissé, ou surchargé par la variable `SEUIL`. Un dermatologue qui relit un dossier doit savoir que « surveillance » voulait dire « probabilité 0,31 sous un seuil de 0,35 réglé pour 90 % de rappel ». Une lésion juste sous le seuil ne se lit pas comme une lésion à 0,01. Les trois champs rendent la décision **traçable et contestable** : on peut la rejouer avec le seuil de l'époque, et expliquer un faux négatif en audit.

**Question 3.3** — Sans `model/modele.joblib`, l'API démarre et `/health` renvoie **503** : `{"model_loaded": false, "status": "indisponible", "erreur": "FileNotFoundError: ..."}`. C'est préférable à un plantage, parce que la plateforme distingue alors « processus vivant » et « service prêt ». La sonde de disponibilité retire l'instance du trafic sans la tuer en boucle, et la cause exacte est lisible dans la réponse et les journaux. Un plantage au démarrage produirait une boucle de redémarrages (*CrashLoop*) sans message exploitable, et pourrait faire échouer tout le déploiement.

## Partie 4 — Conteneurisation et publication

Dockerfile : celui de la séance 1, étendu. Les ajouts sont `COPY model/modele.joblib ./model/` et `CMD ["sh","-c","exec gunicorn --bind 0.0.0.0:${PORT} ..."]`. `sh -c` permet de lire `PORT` comme l'exige le contrat, et `exec` garde gunicorn en PID 1 pour qu'il reçoive SIGTERM.

**Question 4.1** — Estimation : en séance 1, Flask et ses dépendances ajoutaient 5,6 Mo à une base d'environ 140 Mo. scikit-learn, numpy, scipy (tiré par scikit-learn) et pandas sont des bibliothèques compilées de plusieurs dizaines de Mo chacune. J'attendais environ +250 à +300 Mo, soit une image d'environ 450 Mo contre 192 Mo. **Vérification : 651 Mo, soit +459 Mo.** J'ai sous-estimé : la seule couche `RUN pip install` pèse 362 Mo dans `docker history`, parce que scikit-learn tire scipy, qui est la plus lourde des dépendances, plus numpy et pandas avec leurs bibliothèques compilées.

### Mesure 13 — image de la séance 2 comparée à celle de la séance 1

| Relevé | Séance 1 | Séance 2 |
|---|---|---|
| Taille de l'image | 192 Mo | **651 Mo** |
| Nombre de couches (`docker history`) | 19 | 20 (une ligne `COPY model/` en plus) |
| Durée de construction à froid | 17,1 s | **646,4 s** (dont l'essentiel en téléchargement des roues pip, environ 330 s pour la seule étape `pip install` ; la connexion du poste était lente ce jour-là) |
| Nombre de paquets dans `pip freeze` | 7 | **18** (6 directs épinglés et 12 transitifs, dont scipy, threadpoolctl, python-dateutil, six, narwhals et cloudpickle) |

**Question 4.2** — Le modèle pèse 9,5 Ko, et l'image en pèse des centaines de Mo. Ce qui coûte cher dans un artefact d'inférence, ce n'est pas l'intelligence, c'est **l'outillage pour l'exécuter** : les bibliothèques de calcul et leurs binaires. Si la taille devenait un problème, on optimiserait d'abord les dépendances : retirer pandas du chemin de prédiction, ne garder que ce que le pipeline utilise, ou exporter le modèle dans un format d'échange léger (ONNX et son runtime) au lieu d'embarquer scikit-learn et scipy. On ferait aussi une construction multi-étapes. Réduire le modèle ne servirait à rien.

### Mesure 15 — cohérence des versions entre l'entraînement et l'image

| Relevé | Valeur |
|---|---|
| Version de scikit-learn ayant entraîné le modèle (champ `versions` du paquet) | 1.9.1 |
| Version de scikit-learn épinglée dans `requirements.txt` | 1.9.1 |
| Sont-elles identiques ? | Oui. Les 6 dépendances sont épinglées dès le départ aux versions du paquet, et l'image utilise le même Python 3.12.7. |
| Message d'erreur exact, s'il y en a un | **Aucun.** Dans l'image : python 3.12.7, sklearn 1.9.1, pandas 3.0.6, numpy 2.5.4, identiques au champ `versions` du paquet. `/predict` renvoie dans le conteneur la même probabilité qu'en local (0,750853). |

**Question 4.3** — Sans épinglage, l'image aurait cessé de fonctionner (1) **à la prochaine reconstruction** après une nouvelle version de scikit-learn : pip l'installe, et le chargement du paquet échoue ou avertit (`InconsistentVersionWarning`, attributs internes renommés). (2) **À la prochaine mise à jour du modèle** entraîné dans un venv plus récent, que l'image figée ne saurait pas relire. Le plus dangereux pour un service en production est le premier. Il survient sans aucun changement de code, lors d'une simple reconstruction (correctif de sécurité, redéploiement automatique), et peut ne pas planter : le modèle se charge mais calcule différemment, et donne des probabilités faussées sans erreur visible.

### Mesure 16 — publication

| Relevé | Valeur |
|---|---|
| Image publiée | `acrdermascansm26.azurecr.io/dermascan-api:1.0.0` (registre recréé le 2026-10-11 à 13:13 UTC, SKU Basic, France Central) |
| Durée du push | 36,6 s (premier push du dépôt) |
| Digest | `sha256:cae2b6358fcfc65751d85a16536efb9ae660b5b26782e56f98fdcaedb310006b` |
| Tags présents dans le registre | `1.0.0` (`az acr repository show-tags`) ; un seul dépôt, `dermascan-api` (`dermascan-health` a disparu avec le registre supprimé le 06/10). Image : `linux/amd64`, utilisateur 10001, construite le 2026-10-11 à 13:05:38 UTC. |

## Nettoyage

### Mesure 17

| Contrôle de fin de séance | Observation |
|---|---|
| Espace disque libéré par `docker system prune` | _à relever_ |
| Espace libéré en séance 1, pour comparaison | 207,3 Mo |
| Nombre de ressources laissées actives | _à relever_ (attendu : 1, le registre) |
| Coût journalier estimé du SKU `Basic` | environ 0,167 USD/jour (≈ 5 USD/mois) |
| Date portée par l'étiquette `a_detruire` | 2027-06-30 |
| Crédit restant, relevé dans Cost Management | _à relever_ |
| Écart avec le relevé de la séance précédente | _à calculer_ (séance 1 : 88 $US sur 88 $US) |

**Question 6.1** — La phrase de la séance 1 n'est plus exacte. Le registre a été **supprimé le 06/10 à 19:20**, puis recréé en séance 2. Il ne contient plus `dermascan-health:0.1.0` mais `dermascan-api:1.0.0`, l'artefact que la séance 3 déploie. Phrase corrigée : « Le registre `acrdermascansm26` (groupe `rg-dermascan-registre-sm26`, SKU Basic, environ 0,17 USD/jour sur le crédit Azure for Students de Soufiane Meskine) contient l'image `dermascan-api:1.0.0`, que les séances 3 et 4 et le projet fil rouge déploient. Il reste actif jusqu'à la soutenance et peut être détruit avec `az group delete` après le 2027-06-30 (étiquette `a_detruire`). » Ce qui m'a fait la corriger : le contenu du registre a changé, et j'ai mesuré que le supprimer entre deux séances oblige à le recréer et à tout republier, ce qui coûte du temps et casse la continuité. La date reste valable, puisqu'elle est postérieure à la soutenance.

### Contrôle d'extinction

| Contrôle | Fait |
|---|---|
| `az group list` ne montre toujours qu'un groupe, celui du registre | _à relever_ |
| Aucun conteneur de la séance dans `docker ps -a` | _à relever_ |
| Docker Desktop quitté | ☐ |
| Machine éteinte | ☐ |
