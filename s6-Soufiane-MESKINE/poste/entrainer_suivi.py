"""Seance 6 — un entrainement, un run MLflow, ecrit sans reseau.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Usage :
    python entrainer_suivi.py --approche reference --graine 42
Le suivi s'ecrit dans suivi/ (base SQLite + artefacts) : ce dossier voyage
avec le paquet de modele, comme en S4.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path

import joblib
import mlflow
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, precision_recall_curve
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, OrdinalEncoder, StandardScaler

SOURCE = "data/train-metadata.csv"
SUIVI = "sqlite:///suivi/mlflow.db"
EXPERIENCE = "dermascan-tabulaire"
RAPPEL_CIBLE = 0.90      # decide AVANT le premier entrainement, comme en S2
# Memes exclusions qu'en S2 : colonnes derivees du diagnostic, identifiants.
FUITES = ["iddx_full", "iddx_1", "iddx_2", "iddx_3", "iddx_4", "iddx_5",
          "mel_mitotic_index", "mel_thick_mm", "lesion_id"]
IDENTIFIANTS = ["isic_id", "patient_id", "attribution", "copyright_license", "image_type"]


def empreinte(chemin):
    return hashlib.sha256(Path(chemin).read_bytes()).hexdigest()


def construire(approche, num, cat, graine):
    if approche == "reference":
        pre = ColumnTransformer([
            ("num", Pipeline([("imputation", SimpleImputer(strategy="median")),
                              ("echelle", StandardScaler())]), num),
            ("cat", Pipeline([("imputation", SimpleImputer(strategy="most_frequent")),
                              ("encodage", OneHotEncoder(handle_unknown="ignore"))]), cat)])
        clf = LogisticRegression(max_iter=1000, class_weight="balanced", random_state=graine)
        hyper = {"modele": "LogisticRegression", "max_iter": 1000, "class_weight": "balanced"}
    else:
        pre = ColumnTransformer([
            ("num", "passthrough", num),
            ("cat", OrdinalEncoder(handle_unknown="use_encoded_value", unknown_value=-1,
                                   encoded_missing_value=-1), cat)])
        clf = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05,
                                             class_weight="balanced", random_state=graine)
        hyper = {"modele": "HistGradientBoostingClassifier", "max_iter": 200,
                 "learning_rate": 0.05, "class_weight": "balanced"}
    return Pipeline([("pre", pre), ("clf", clf)]), hyper


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--approche", choices=["reference", "variante"], required=True)
    p.add_argument("--graine", type=int, required=True)
    a = p.parse_args()

    manifeste = json.loads(Path("donnees/manifeste.json").read_text())
    decoupage = Path(manifeste["decoupages"][str(a.graine)]["fichier"])
    assert empreinte(decoupage) == manifeste["decoupages"][str(a.graine)]["sha256"], \
        "le decoupage ne correspond plus au manifeste"
    test = set(json.loads(decoupage.read_text())["patients_test"])

    d = pd.read_csv(SOURCE, low_memory=False)
    est_test = d["patient_id"].isin(test).to_numpy()
    y = d["target"].to_numpy()
    X = d.drop(columns=["target"] + FUITES + IDENTIFIANTS, errors="ignore")
    num = X.select_dtypes(include=np.number).columns.tolist()
    cat = [c for c in X.columns if c not in num]
    modele, hyper = construire(a.approche, num, cat, a.graine)

    # Le suivi s'ecrit dans suivi/ : base ET artefacts, rien ailleurs.
    Path("suivi").mkdir(exist_ok=True)
    mlflow.set_tracking_uri(SUIVI)
    if mlflow.get_experiment_by_name(EXPERIENCE) is None:
        mlflow.create_experiment(EXPERIENCE, artifact_location=str(Path("suivi/artefacts").resolve()))
    mlflow.set_experiment(EXPERIENCE)

    with mlflow.start_run(run_name=f"{a.approche}-g{a.graine}") as run:
        t0 = time.time()
        modele.fit(X[~est_test], y[~est_test])
        duree = time.time() - t0
        proba = modele.predict_proba(X[est_test])[:, 1]
        pr_auc = average_precision_score(y[est_test], proba)
        precision, rappel, seuils = precision_recall_curve(y[est_test], proba)
        i = np.where(rappel >= RAPPEL_CIBLE)[0][-1]
        seuil = float(seuils[min(i, len(seuils) - 1)])

        rep = Path("model") / run.info.run_name
        rep.mkdir(parents=True, exist_ok=True)
        meta = {"approche": a.approche, "graine": a.graine, "run_id": run.info.run_id,
                "seuil": seuil, "rappel_cible": RAPPEL_CIBLE, "colonnes_attendues": list(X.columns),
                "sha256_manifeste": empreinte("donnees/manifeste.json"),
                "sha256_donnees": manifeste["sha256"], "commit": manifeste["commit"]}
        joblib.dump({"pipeline": modele, **meta}, rep / "modele.joblib")
        meta["sha256_modele"] = empreinte(rep / "modele.joblib")
        (rep / "modele_meta.json").write_text(json.dumps(meta, indent=2))

        mlflow.log_params({"approche": a.approche, "graine": a.graine, "decoupage": "patient_id",
                           "rappel_cible": RAPPEL_CIBLE, **hyper})
        mlflow.log_metrics({"pr_auc": pr_auc, "precision_au_seuil": float(precision[i]),
                            "rappel_au_seuil": float(rappel[i]), "seuil": seuil,
                            "duree_entrainement_s": duree})
        mlflow.set_tags({"sha256_manifeste": meta["sha256_manifeste"],
                         "sha256_modele": meta["sha256_modele"], "commit": meta["commit"]})
        mlflow.log_artifact(str(rep / "modele.joblib"), "model")
        mlflow.log_artifact(str(rep / "modele_meta.json"), "model")
        print(f"{run.info.run_name}  PR-AUC {pr_auc:.4f}  precision@{RAPPEL_CIBLE:.0%} "
              f"{precision[i]:.4f}  seuil {seuil:.4f}  {duree:.0f} s  run {run.info.run_id}")


if __name__ == "__main__":
    main()
