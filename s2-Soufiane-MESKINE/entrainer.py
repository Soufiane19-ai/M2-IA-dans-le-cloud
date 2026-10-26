"""Entrainement du modele DermaScan (seance 2, partie 2).

Decoupage par patient, pipeline scikit-learn, evaluation, choix du seuil,
serialisation avec metadonnees. Regenere model/modele.joblib.
Lancement : python3 entrainer.py
"""
import datetime
import json
import os
import platform
import time

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, average_precision_score,
                             precision_recall_curve, roc_auc_score)
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

RAPPEL_VISE = 0.90          # decide avant toute mesure (tableau de decisions)
GRAINE = 42
VERSION = "1.0.0"

d = pd.read_csv("data/train-metadata.csv", low_memory=False)

# --- Colonnes ecartees (partie 1) ------------------------------------------
FUITES = ["iddx_full", "iddx_1", "iddx_2", "iddx_3", "iddx_4", "iddx_5",
          "mel_thick_mm", "mel_mitotic_index", "lesion_id"]
IDENTIFIANTS = ["isic_id", "patient_id"]
ADMINISTRATIVES = ["attribution", "copyright_license"]   # l'hopital, pas la lesion
CONSTANTES = ["image_type"]
CIBLE = "target"

ecartees = set(FUITES + IDENTIFIANTS + ADMINISTRATIVES + CONSTANTES + [CIBLE])
colonnes = [c for c in d.columns if c not in ecartees]
colonnes_categorielles = [c for c in colonnes if d[c].dtype == object or str(d[c].dtype) in ("str", "string", "category")]
colonnes_numeriques = [c for c in colonnes if c not in colonnes_categorielles]

X = d[colonnes]
y = d[CIBLE].to_numpy()
groupes = d["patient_id"].to_numpy()
print(f"variables : {len(colonnes)} ({len(colonnes_numeriques)} numeriques, "
      f"{len(colonnes_categorielles)} categorielles)")
print("categorielles :", colonnes_categorielles)

# --- 2.1 Decoupage sans fuite ----------------------------------------------
decoupe = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=GRAINE)
train, test = next(decoupe.split(X, y, groups=groupes))
assert not (set(groupes[train]) & set(groupes[test])), "fuite de patients"

print("\nMesure 6 - decoupage")
for nom, idx in (("entrainement", train), ("test", test)):
    print(f"  {nom:<13} lignes {len(idx):>7}  patients {len(set(groupes[idx])):>5}  "
          f"positifs {int(y[idx].sum()):>4}  taux {100 * y[idx].mean():.4f} %")

print("\nStabilite du taux de positifs du test selon la graine (Q2.1) :")
for g in (0, 1, 7, 42, 123):
    _, t = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=g).split(X, y, groups=groupes))
    print(f"  graine {g:>3} : {int(y[t].sum()):>3} positifs, taux {100 * y[t].mean():.4f} %")

# --- 2.2 Pipeline -----------------------------------------------------------
pre = ColumnTransformer([
    ("num", Pipeline([("imputation", SimpleImputer(strategy="median")),
                      ("echelle", StandardScaler())]), colonnes_numeriques),
    ("cat", Pipeline([("imputation", SimpleImputer(strategy="most_frequent")),
                      ("encodage", OneHotEncoder(handle_unknown="ignore"))]),
     colonnes_categorielles),
])

# --- 2.3 Entrainement et piege de l'exactitude ------------------------------
modele = Pipeline([("pre", pre),
                   ("clf", LogisticRegression(max_iter=1000, class_weight="balanced"))])
t0 = time.perf_counter()
modele.fit(X.iloc[train], y[train])
duree = time.perf_counter() - t0

reference = DummyClassifier(strategy="most_frequent").fit(X.iloc[train], y[train])
y_test = y[test]
proba = modele.predict_proba(X.iloc[test])[:, 1]
proba_ref = reference.predict_proba(X.iloc[test])[:, 1]

def scores(p, pred):
    return {"exactitude": accuracy_score(y_test, pred),
            "roc_auc": roc_auc_score(y_test, p),
            "pr_auc": average_precision_score(y_test, p)}

s_ref = scores(proba_ref, reference.predict(X.iloc[test]))
s_mod = scores(proba, modele.predict(X.iloc[test]))
hasard = y_test.mean()
print("\nMesure 7 - comparaison sur le test")
print(f"  Dummy      exactitude {s_ref['exactitude']:.4f}  ROC-AUC {s_ref['roc_auc']:.4f}  PR-AUC {s_ref['pr_auc']:.4f}")
print(f"  RegLog     exactitude {s_mod['exactitude']:.4f}  ROC-AUC {s_mod['roc_auc']:.4f}  PR-AUC {s_mod['pr_auc']:.4f}")
print(f"  hasard PR-AUC = taux de positifs du test = {hasard:.5f}")

# --- 2.4 Choix du seuil ----------------------------------------------------------
def a_seuil(s):
    pred = proba >= s
    vp = int((pred & (y_test == 1)).sum())
    fp = int((pred & (y_test == 0)).sum())
    fn = int((~pred & (y_test == 1)).sum())
    rappel = vp / (vp + fn)
    precision = vp / (vp + fp) if vp + fp else float("nan")
    return rappel, precision, vp, fp, fn, 1000 * pred.mean()

print("\nMesure 8 - compromis rappel / precision")
print("  seuil  rappel  precision    VP      FP    FN  alertes/1000")
for s in (0.50, 0.80, 0.90, 0.99):
    r, p, vp, fp, fn, a = a_seuil(s)
    print(f"  {s:.2f}   {r:.3f}   {p:.5f}  {vp:>4}  {fp:>6}  {fn:>4}  {a:8.1f}")

precision, rappel, seuils = precision_recall_curve(y_test, proba)
# rappel decroit quand l'indice (donc le seuil) croit : on prend le DERNIER indice
# qui atteint encore le rappel vise, c'est-a-dire le seuil le plus haut qui le garantit
# (le moins d'alertes possible pour ce rappel).
i = np.where(rappel >= RAPPEL_VISE)[0][-1]
seuil_retenu = float(seuils[min(i, len(seuils) - 1)])
r, p, vp, fp, fn, a = a_seuil(seuil_retenu)
print("\nMesure 9 - seuil retenu")
print(f"  rappel vise {RAPPEL_VISE}  seuil {seuil_retenu:.6f}  rappel obtenu {r:.4f}")
print(f"  precision {p:.5f}  lesions examinees par maligne trouvee : {round(1 / p)}")
print(f"  faux negatifs restants : {fn} sur {vp + fn}  (alertes pour 1000 lesions : {a:.1f})")

# --- 2.5 Serialisation avec metadonnees ------------------------------------------
os.makedirs("model", exist_ok=True)
paquet = {
    "pipeline": modele,
    "version": VERSION,
    "colonnes_attendues": colonnes,
    "seuil": seuil_retenu,
    "rappel_cible": RAPPEL_VISE,
    "metriques": {"pr_auc": round(s_mod["pr_auc"], 5), "roc_auc": round(s_mod["roc_auc"], 5),
                  "pr_auc_hasard": round(float(hasard), 6),
                  "rappel_test": round(r, 4), "precision_test": round(p, 6),
                  "faux_negatifs_test": fn, "positifs_test": vp + fn},
    "prevalence_entrainement": round(float(y[train].mean()), 6),
    "entraine_le": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "versions": {"python": platform.python_version(), "scikit-learn": sklearn.__version__,
                 "pandas": pd.__version__, "numpy": np.__version__, "joblib": joblib.__version__},
    "donnees": {"source": "ISIC 2024 (Kaggle isic-2024-challenge), train-metadata.csv",
                "lignes": int(len(d)), "patients": int(d["patient_id"].nunique()),
                "graine_decoupage": GRAINE},
}
joblib.dump(paquet, "model/modele.joblib")
print("\nMesure 10 - paquet")
print(f"  taille {os.path.getsize('model/modele.joblib') / 1024:.1f} Ko  "
      f"colonnes attendues {len(colonnes)}  duree d'entrainement {duree:.1f} s")
print("  versions :", json.dumps(paquet["versions"]))

# Charge utile de test (Partie 3) : une vraie ligne maligne du jeu de test.
ligne = X.iloc[test][y_test == 1].iloc[0]
charge = {k: (None if pd.isna(v) else (v.item() if hasattr(v, "item") else v)) for k, v in ligne.items()}
with open("charge.json", "w") as f:
    json.dump(charge, f, indent=1)
incomplete = {k: v for k, v in list(charge.items())[:10]}
with open("charge_incomplete.json", "w") as f:
    json.dump(incomplete, f, indent=1)
print("  charge.json ecrite (une lesion maligne du test)")
