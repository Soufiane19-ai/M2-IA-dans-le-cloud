# isic-mlops-groupe — projet fil rouge MLOps (brouillon du 20/11/2026)

> **Brouillon préparé par Soufiane Meskine** avant la formation du groupe. Les noms des autres membres, leurs rôles et le nom définitif du dépôt sont **à compléter** au moment de la formation du groupe. Le sujet se fige au début du jour 7.

## Groupe

| Membre | Rôle | Registre Azure (ACR) | Crédit Azure restant |
|---|---|---|---|
| Soufiane Meskine | Suivi d'expériences et registre (MLflow), traçabilité | `acrdermascansm26` (tags `dermascan-api` 1.0.0, 2.0.0, 2.1.0) | 84 € sur 90 € (relevé du 17/11/2026, à revérifier le jour 7) |
| _à compléter_ | _données et découpage_ | _à relever_ | _à relever_ |
| _à compléter_ | _service, déploiement et surveillance_ | _à relever_ | _à relever_ |

## Sujet pressenti

**ISIC approfondi** : tri des lésions cutanées sur ISIC 2024 (vignettes et métadonnées), dans la continuité de DermaScan (S2 à S6).

## Données

Elles sont téléchargées sur chaque poste et **jamais versionnées** (`donnees/` est dans `.gitignore`). Chaque membre accepte lui-même les règles Kaggle `isic-2024-challenge` si le sujet l'exige.

Contrôle d'intégrité : `train-metadata.csv` doit avoir un sha256 commençant par `536e8208`.

## Règles du dépôt

- **Aucun** secret (`.env`), poids (`*.pt`, `*.onnx`), donnée ni suivi MLflow (`suivi/`) dans Git.
- Les scripts sont commités **avant** d'être lancés, pour que le manifeste et chaque run portent un vrai hash de commit (séance 6, question 2.4).
- Les décisions sont dans `DECISIONS.md`, écrites avant toute mesure.
- Dépôt **privé**, avec le formateur invité en lecture.
