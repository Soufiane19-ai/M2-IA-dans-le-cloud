"""Seance 4 — donnees.

Usage autonome :  python donnees.py
"""
import hashlib
import io
import os
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image
from sklearn.model_selection import StratifiedGroupKFold

DOSSIER = Path(os.environ.get("DONNEES", "donnees"))
ZIP_VIGNETTES = DOSSIER / "ISIC_2024_Permissive_Training_Input.zip"
VERITE = DOSSIER / "ISIC_2024_Permissive_Training_GroundTruth.csv"
N_NEGATIFS = int(os.environ.get("N_NEGATIFS", "5000"))
GRAINE = 42
TAILLE = 128
MOYENNE = [0.485, 0.456, 0.406]
ECART_TYPE = [0.229, 0.224, 0.225]
MANIFESTE = "manifeste_echantillon.csv"


def metadonnees():
    verite = pd.read_csv(VERITE)
    chemin = DOSSIER / "train-metadata.csv"
    if not chemin.exists():
        chemin = DOSSIER / "train-metadata.csv.zip"
    meta = pd.read_csv(chemin, usecols=["isic_id", "patient_id", "target"])
    d = verite.merge(meta, on="isic_id", how="left", validate="one_to_one")
    assert d["patient_id"].notna().all(), "vignettes sans patient_id : mauvais train-metadata.csv ?"
    assert (d["malignant"].astype(int) == d["target"]).all(), "etiquettes discordantes"
    return d.rename(columns={"malignant": "cible"}).astype({"cible": int})[
        ["isic_id", "patient_id", "cible"]]


def echantillonner(d, n_negatifs=N_NEGATIFS, graine=GRAINE):
    pos = d[d.cible == 1]
    neg = d[d.cible == 0].sample(n=n_negatifs, random_state=graine)
    return pd.concat([pos, neg]).sort_values("isic_id").reset_index(drop=True)


def decouper(e, graine=GRAINE):
    plis = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=graine)
    tr, va = next(plis.split(e, e.cible, groups=e.patient_id))
    e = e.copy()
    e["jeu"] = "entrainement"
    e.loc[va, "jeu"] = "validation"
    communs = set(e.patient_id[e.jeu == "entrainement"]) & set(e.patient_id[e.jeu == "validation"])
    assert not communs, f"fuite : {len(communs)} patients des deux cotes"
    return e


def lire_vignette(source, taille=TAILLE):
    im = Image.open(source).convert("RGB").resize((taille, taille), Image.BILINEAR)
    return np.asarray(im, dtype=np.uint8)


def charger_vignettes(ids, taille=TAILLE):
    cache = DOSSIER / f"cache_{len(ids)}_{taille}_{empreinte_ids(ids)[:12]}.npy"
    if cache.exists():
        return np.load(cache)
    x = np.empty((len(ids), taille, taille, 3), dtype=np.uint8)
    with zipfile.ZipFile(ZIP_VIGNETTES) as z:
        for i, isic_id in enumerate(ids):
            x[i] = lire_vignette(io.BytesIO(z.read(f"ISIC_2024_Permissive_Training_Input/{isic_id}.jpg")), taille)
    np.save(cache, x)
    return x


def empreinte_ids(ids):
    return hashlib.sha256("\n".join(ids).encode()).hexdigest()


def vers_tenseur(x_uint8):
    import torch
    t = torch.from_numpy(x_uint8).permute(0, 3, 1, 2).float().div(255)
    m = torch.tensor(MOYENNE).view(1, 3, 1, 1)
    s = torch.tensor(ECART_TYPE).view(1, 3, 1, 1)
    return (t - m) / s


def augmenter(t, generateur):
    import torch
    if torch.rand(1, generator=generateur) < 0.5:
        t = t.flip(3)
    if torch.rand(1, generator=generateur) < 0.5:
        t = t.flip(2)
    return t.rot90(int(torch.randint(0, 4, (1,), generator=generateur)), (2, 3))


def preparer(sortie=Path("model")):
    d = metadonnees()
    e = decouper(echantillonner(d))
    sortie.mkdir(exist_ok=True)
    e.to_csv(sortie / MANIFESTE, index=False)
    return d, e


if __name__ == "__main__":
    d, e = preparer()
    print(f"archive Permissive : {len(d):,} vignettes, {d.cible.sum()} positifs "
          f"({100 * d.cible.mean():.3f} %), {d.patient_id.nunique()} patients")
    print(f"echantillon : {len(e):,} vignettes ({(e.cible == 1).sum()} pos + {(e.cible == 0).sum()} neg, "
          f"graine {GRAINE}), prevalence {100 * e.cible.mean():.2f} %")
    for jeu, g in e.groupby("jeu"):
        print(f"  {jeu:12s} {len(g):5d} vignettes  {g.cible.sum():3d} positifs  "
              f"{g.patient_id.nunique():4d} patients")
    print("patients communs aux deux jeux : 0")
    print(f"manifeste : model/{MANIFESTE}  sha256 "
          f"{hashlib.sha256((Path('model') / MANIFESTE).read_bytes()).hexdigest()[:16]}...")
    x = charger_vignettes(e.isic_id.tolist())
    print(f"vignettes en RAM : {x.shape} {x.dtype}, {x.nbytes / 1e6:.0f} Mo")
    with zipfile.ZipFile(ZIP_VIGNETTES) as z:
        tailles = [Image.open(io.BytesIO(z.read(f"ISIC_2024_Permissive_Training_Input/{i}.jpg"))).size
                   for i in e.isic_id[:500]]
    print(f"taille d'origine (500 premieres) : mediane {np.median([t[0] for t in tailles]):.0f} px, "
          f"min {min(t[0] for t in tailles)}, max {max(t[0] for t in tailles)}")
