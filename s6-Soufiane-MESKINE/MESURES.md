# Séance 6 — Mesures 1 à 6 et questions 1.1 à 1.5

Soufiane Meskine · 20/11/2026. Les sorties brutes sont dans `logs/`, les captures de l'interface MLflow dans `captures/`.

## 1.1 — Environnement et données

### Mesure 1

| Grandeur | Valeur |
|---|---|
| Lignes de test et positifs en test, graine 42 | **100 054 lignes, 130 positifs** (261 patients ; entraînement 301 005 lignes) |
| Lignes de test et positifs en test, graine 7 | **101 995 lignes, 108 positifs** (261 patients ; entraînement 299 064 lignes) |
| Les 12 premiers caractères de l'empreinte de `donnees/manifeste.json` | **`e3da1f52ff2c`** |

Sortie de `preparer.py` :
```
graine 42 : 301,005 / 100,054 lignes, 130 positifs en test, intersection vide
graine 7 : 299,064 / 101,995 lignes, 108 positifs en test, intersection vide
manifeste : donnees/manifeste.json  sha256 e3da1f52ff2c
```

**Question 1.1** — `GroupShuffleSplit` tire 25 % des **patients**, pas 25 % des lignes : on a 261 patients en test dans les deux cas. Mais un patient porte de quelques lésions à plusieurs milliers, et les 393 malignes sont concentrées chez peu de patients. Le nombre de lignes et de positifs dépend donc de **quels** patients sont tirés.

## 1.2 — Un run, écrit sans réseau

Blancs complétés dans `entrainer_suivi.py` :

```python
SUIVI = "sqlite:///suivi/mlflow.db"                                   # la même base que promouvoir.py et verifier_chaine.py
mlflow.create_experiment(EXPERIENCE, artifact_location=str(Path("suivi/artefacts").resolve()))
mlflow.set_tags({"sha256_manifeste": meta["sha256_manifeste"], ...})
```

`artifact_location` est un chemin **absolu, en texte**, construit comme le `nouveau` de `importer_suivi.py`. Il finit donc par `/suivi/artefacts`, la forme que la clause `LIKE '%/suivi/artefacts'` sait retrouver et réécrire. Un chemin relatif ou un autre dossier aurait laissé l'import sans effet.

### Mesure 2

```
reference-g42  PR-AUC 0.0500  precision@90% 0.0041  seuil 0.2864  12 s  run 63d45447b98e4b759f77f8b8987221c5
```

| PR-AUC | Précision au rappel cible (0,90) | Seuil | Durée | Identifiant du run |
|---|---|---|---|---|
| 0,0500 | 0,0041 | 0,2864 | 11,9 s | `63d45447b98e4b759f77f8b8987221c5` |

**Question 1.2** — Le seuil vaut **0,2864**, contre **0,3475** en S2. Cette différence ne prouve pas que ma chaîne n'est pas reproductible : **ce n'est pas la même chaîne**. En S2, le test prenait 20 % des patients (`test_size=0.2`, 110 positifs) ; ici il en prend 25 % (130 positifs). Or le seuil à rappel 0,90 est fixé par une **seule** lésion, la 117ᵉ maligne la mieux classée sur 130, donc il bouge dès que le test change.
La reproductibilité se prouve en rejouant **la même** chaîne : relancé à l'identique, `reference-g42` redonne exactement 0,0500 et 0,2864. Ma chaîne est donc reproductible, mais un seuil n'a de sens qu'avec son manifeste et son découpage, ce que le run enregistre maintenant.

## 1.3 — Le suivi voyage avec le paquet

Commandes de l'énoncé exécutées dans `/travail`. L'export pèse 36 Ko et contient `suivi/`, `model/` et `donnees/`.

### Mesure 3

| Observation | Valeur |
|---|---|
| Les métriques et paramètres du run sont-ils lisibles ? | **Oui** : 5 métriques, 7 paramètres et 3 tags sont affichés (`captures/mesure3a_avant_import_overview.png`) |
| Les artefacts (`model/modele.joblib`) sont-ils lisibles ? | **Non** : l'onglet Artifacts affiche « No Artifacts Recorded » (`captures/mesure3b_avant_import_artefacts.png`). `download_artifacts` échoue avec « Failed to download artifacts from path 'modele.joblib' » |
| Le chemin indiqué pour les artefacts, dans les détails du run | **`/travail/session/suivi/artefacts/63d45447b98e4b759f77f8b8987221c5/artifacts`**, un dossier qui n'existe plus depuis le `mv session session_fermee`. L'expérience pointe vers `/travail/session/suivi/artefacts`. MLflow 3.18 n'affiche plus ce champ dans l'onglet Overview : il a été lu par `MlflowClient` (`run.info.artifact_uri`). |

Sortie de `importer_suivi.py` :
```
experiments.artifact_location : 1 ligne(s) /travail/session/suivi/artefacts -> /travail/poste/suivi/artefacts
runs.artifact_uri : 1 ligne(s) /travail/session/suivi/artefacts -> /travail/poste/suivi/artefacts
model_versions.source : 0 ligne(s) /travail/session/suivi/artefacts -> /travail/poste/suivi/artefacts
model_versions.storage_location : 0 ligne(s) /travail/session/suivi/artefacts -> /travail/poste/suivi/artefacts
```
Après l'import, l'onglet Artifacts montre `model/modele.joblib` et `model/modele_meta.json` (`captures/04_run_reference_g42_artefacts.png`). Un second lancement répond « rien a reecrire : le suivi pointe deja vers ce poste ».

**Question 1.3**
- **(a)** Les métriques et paramètres sont des **valeurs stockées dans `mlflow.db`** : elles voyagent avec le fichier. Les artefacts sont des **fichiers à côté**, et la base n'en garde que le **chemin absolu** (`/travail/session/…`). Les fichiers ont bien voyagé dans le zip, mais la base pointe vers un dossier disparu.
- **(b)** Le script remplace l'ancien préfixe par `…/poste/suivi/artefacts` dans `experiments.artifact_location` et `runs.artifact_uri`, ainsi que dans `model_versions.source` et `storage_location` (0 ligne ici, le registre était encore vide).
- **(c)** Chaque membre du groupe a son propre chemin absolu (`C:\Users\…`, `/home/…`, `/content/…` sur Colab). Une base copiée d'un poste à l'autre pointerait donc toujours vers le dossier de son auteur : il faut réimporter sur chaque poste, ou ranger les artefacts dans un stockage commun adressé par URI.

## 1.4 — Comparer : deux approches, deux graines

Sorties :
```
reference-g7  PR-AUC 0.0654  precision@90% 0.0060  seuil 0.4904  11 s  run dd17eaa24f6b42a9b04f3f1ebb3a2ec8
variante-g42  PR-AUC 0.0834  precision@90% 0.0051  seuil 0.0615  3 s  run 9f9cd9cb425a40bdb10fec2b83673375
variante-g7  PR-AUC 0.0469  precision@90% 0.0052  seuil 0.1810  3 s  run 4b25cd4329e0435f8a61767c4151f8ca
```

### Mesure 4 (vue Compare : `captures/02_compare_4_runs.png`)

| Run | PR-AUC | Précision au rappel cible | Durée d'entraînement |
|---|---|---|---|
| reference-g42 | 0,0500 | 0,0041 | 11,9 s |
| reference-g7 | 0,0654 | 0,0060 | 10,9 s |
| variante-g42 | 0,0834 | 0,0051 | 3,5 s |
| variante-g7 | 0,0469 | 0,0052 | 2,7 s |

Les durées sont mesurées dans le conteneur de travail, qui a plusieurs cœurs. `HistGradientBoostingClassifier` est parallélisé, `LogisticRegression` (lbfgs) ne l'est pas. Le rapport des durées peut donc changer sur une autre machine.

### Mesure 5

| Grandeur | Valeur |
|---|---|
| Écart variante − référence, graine 42 | **+0,0334** |
| Écart variante − référence, graine 7 | **−0,0185** |
| Variation de la référence entre ses deux graines | **0,0154** |
| Variation de la variante entre ses deux graines | **0,0365** |

**Question 1.4** — Les deux écarts dépassent mon seuil de 0,010 en valeur absolue, mais ils sont **de signes opposés**, et ils restent de l'ordre de la variation d'une même approche d'une graine à l'autre (jusqu'à 0,0365). D'après mon tableau, aucune approche n'est meilleure, et je départage sur la durée : je promeus la **variante** (3,1 s contre 11,4 s en moyenne).
C'est contraire à ce que j'attendais : sur la seule graine 42, la variante semblait nettement supérieure (+0,033, soit +67 %), et je l'aurais déclarée gagnante sur sa PR-AUC. La graine 7 inverse le classement, et c'est exactement ce que le tableau écrit avant protège.

## 1.5 — Le registre : une version, un validateur, un repli

Alias complétés dans `promouvoir.py` : `ALIAS_SERVI = "production"` (l'alias que lit `verifier_chaine.py`) et `ALIAS_REPLI = "repli"`.

```
$ python promouvoir.py --run 63d45447b98e4b759f77f8b8987221c5 --validateur "Soufiane Meskine"
dermascan-tabulaire v1 -> production (run reference-g42, valide par Soufiane Meskine) ; repli : aucune
$ python promouvoir.py --run 9f9cd9cb425a40bdb10fec2b83673375 --validateur "Soufiane Meskine"
dermascan-tabulaire v2 -> production (run variante-g42, valide par Soufiane Meskine) ; repli : 1
```

### Mesure 6

```
$ python verifier_chaine.py model/variante-g42/modele.joblib
registre : dermascan-tabulaire v2, valide par Soufiane Meskine, repli 1
OK  fichier servi = version promue     1f807dc75894872f
run : variante-g42  graine 42  PR-AUC 0.0834
OK  artefact du run = fichier servi    1f807dc75894872f
OK  manifeste du run = manifeste local e3da1f52ff2cd0b5
OK  donnees du manifeste = donnees locales 536e8208cfb3502b
commit du code qui a produit les donnees : hors-git
code de sortie : 0
```

| Élément | Valeur |
|---|---|
| Version promue | `dermascan-tabulaire` **v2** (run `variante-g42`), validée par Soufiane Meskine |
| Version de repli | **v1** (run `reference-g42`) |
| Maillon 1 : fichier servi = version promue | OK, `1f807dc75894872f` |
| Maillon 2 : artefact du run = fichier servi | OK, `1f807dc75894872f` |
| Maillon 3 : manifeste du run = manifeste local | OK, `e3da1f52ff2cd0b5` |
| Maillon 4 : données du manifeste = données locales | OK, `536e8208cfb3502b` |
| Commit | `hors-git` |

Vérification sur l'autre fichier, comme si le mauvais modèle avait été copié dans l'image :
```
$ python verifier_chaine.py model/reference-g42/modele.joblib ; echo "code de sortie : $?"
registre : dermascan-tabulaire v2, valide par Soufiane Meskine, repli 1
KO  fichier servi = version promue     00e048b36de77adc  (attendu 1f807dc75894872f)
code de sortie : 1
```

**Question 1.5** — Le **premier maillon** rompt (« fichier servi = version promue ») : l'empreinte `00e048b3…` n'est pas celle de la version promue `1f807dc7…`. Le script s'arrête aussitôt avec le **code de sortie 1**.
Comme il renvoie 0 quand la chaîne est intacte et 1 au premier maillon rompu, il peut servir de test automatique (H2) : une CI s'arrête sur tout code non nul. Je le lancerais dans le pipeline **juste avant `docker build`**, sur le fichier copié dans le contexte de l'image : un mauvais modèle ne serait alors jamais poussé ni déployé.
