"""Seance 4 — releves complementaires (mesures 3, 4, 5, 20, question 3.1).

Lance APRES `python donnees.py` (le manifeste et le cache .npy existent).
Usage : python analyses_s4.py > logs/analyses_s4.txt
"""
import hashlib
import json
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split

import donnees as D

res = {}
d = D.metadonnees()                                   # archive Permissive entiere
m = pd.read_csv("model/manifeste_echantillon.csv")
res["manifeste_sha256"] = hashlib.sha256(Path("model/manifeste_echantillon.csv").read_bytes()).hexdigest()

# Mesure 1 complements
res["archive"] = {"vignettes": len(d), "positifs": int(d.cible.sum()),
                  "prevalence_pct": round(100 * d.cible.mean(), 4), "patients": int(d.patient_id.nunique()),
                  "negatifs": int((d.cible == 0).sum())}

# Mesure 3 : exactitude du modele constant "benin"
va = m[m.jeu == "validation"]
res["mesure3"] = {
    "flux_reel": {"benins": int((d.cible == 0).sum()), "total": len(d), "exactitude": float((d.cible == 0).mean())},
    "echantillon": {"benins": int((m.cible == 0).sum()), "total": len(m), "exactitude": float((m.cible == 0).mean())},
    "validation": {"benins": int((va.cible == 0).sum()), "total": len(va), "exactitude": float((va.cible == 0).mean())},
}

# Mesure 4 : la fuite, refaite a la main (decoupage ligne a ligne)
tr_l, va_l = train_test_split(m, test_size=0.2, stratify=m.cible, random_state=D.GRAINE)
res["mesure4"] = {
    "decouper": {"vignettes_val": len(va), "positifs_val": int(va.cible.sum()),
                 "patients_val": int(va.patient_id.nunique()),
                 "patients_communs": len(set(m.patient_id[m.jeu == "entrainement"]) & set(va.patient_id))},
    "ligne_a_ligne": {"vignettes_val": len(va_l), "positifs_val": int(va_l.cible.sum()),
                      "patients_val": int(va_l.patient_id.nunique()),
                      "patients_communs": len(set(tr_l.patient_id) & set(va_l.patient_id))},
    "lesions_par_patient_archive": {"moyenne": float(d.groupby("patient_id").size().mean()),
                                    "mediane": float(d.groupby("patient_id").size().median())},
}

# Mesure 5 : le tenseur d'entree
import torch  # noqa: E402
x = D.charger_vignettes(m.isic_id.tolist())
t = D.vers_tenseur(x[:64])
res["mesure5"] = {"forme": list(t.shape), "type": str(t.dtype), "min": float(t.min()), "max": float(t.max()),
                  "moyenne": float(t.mean()), "ecart_type": float(t.std()),
                  "moyenne_par_canal": [float(v) for v in t.mean(dim=(0, 2, 3))],
                  "pixels_bruts_moyenne_par_canal_0_1": [float(v) for v in (x[:64] / 255).mean(axis=(0, 1, 2))]}

# Question 3.1 : parametres entrainables
import entrainer as E  # noqa: E402
r = E.construire(poids_imagenet=False)
total = sum(p.numel() for p in r.parameters())
E.regler_gel(r, False)
tete = sum(p.numel() for p in r.parameters() if p.requires_grad)
E.regler_gel(r, True)
degel = sum(p.numel() for p in r.parameters() if p.requires_grad)
res["q31"] = {"total": total, "tete": tete, "degel": degel,
              "part_tete_pct": 100 * tete / total, "part_degel_pct": 100 * degel / total}

# Mesure 20 : modalites d'eclairage
chemin = D.DOSSIER / "train-metadata.csv"
if not chemin.exists():
    chemin = D.DOSSIER / "train-metadata.csv.zip"
cols = ["isic_id", "tbp_tile_type", "age_approx", "sex", "anatom_site_general", "attribution"]
meta = pd.read_csv(chemin, usecols=cols, low_memory=False)
man = m.merge(meta, on="isic_id")
arc = d.merge(meta, on="isic_id")
pops = (("manifeste", man), ("positifs_archive", arc[arc.cible == 1]), ("archive", arc), ("S2_complet", meta))
res["mesure20"] = {nom: {"lesions": len(g), "tbp_tile_type": g.tbp_tile_type.value_counts(normalize=True).round(4).to_dict()}
                   for nom, g in pops}
res["populations_q62"] = {
    "institutions_archive": arc.attribution.value_counts().to_dict(),
    "age_archive": arc.age_approx.describe().round(1).to_dict(),
    "moins_de_30_archive": int((arc.age_approx < 30).sum()),
    "sex_archive": arc.sex.value_counts(dropna=False).to_dict(),
    "patients_archive": int(arc.patient_id.nunique()),
}

with zipfile.ZipFile(D.ZIP_VIGNETTES) as z:
    noms = z.namelist()
    attribution = [n for n in noms if n.upper().endswith("ATTRIBUTION.TXT")]
    res["zip"] = {"entrees": len(noms), "attribution_fichier": attribution}
    if attribution:
        res["attribution_texte"] = z.read(attribution[0]).decode("utf-8", "replace")

print(json.dumps(res, indent=2, ensure_ascii=False, default=str))
