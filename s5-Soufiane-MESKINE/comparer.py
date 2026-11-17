"""Seance 5 — les trois variantes du meme modele, face a face : PyTorch, ONNX, ONNX int8.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Pour chaque variante : taille du fichier, latence (lot de 1, 1 fil),
probabilites sur les 1 058 vignettes de validation de S4, decisions au seuil servi.
La reference est PyTorch : c'est le modele que S4 a valide.

Usage :  python comparer.py [dossier_modele]        (defaut : model ; donnees dans $DONNEES)
Sortie : sorties/comparaison_variantes.csv (une ligne par vignette et par variante)
"""
import io
import json
import math
import os
import sys
import time
import zipfile
from pathlib import Path

import numpy as np
import onnxruntime as ort
import pandas as pd
import torch
import torchvision
from PIL import Image

DOSSIER = Path(sys.argv[1] if len(sys.argv) > 1 else "model")
DONNEES = Path(os.environ.get("DONNEES", "donnees"))
META = json.loads((DOSSIER / "modele_meta.json").read_text())
T, SEUIL, CORRECTION = META["taille_entree"], META["seuil"], META["correction_logit"]
MOY = np.array(META["normalisation"]["moyenne"], dtype=np.float32).reshape(1, 3, 1, 1)
ECT = np.array(META["normalisation"]["ecart_type"], dtype=np.float32).reshape(1, 3, 1, 1)
CHAUFFE, MESURES = 20, 300

torch.set_num_threads(1)            # 1 fil partout, pour PyTorch comme pour ONNX Runtime
OPTIONS = ort.SessionOptions()
OPTIONS.intra_op_num_threads = 1
OPTIONS.inter_op_num_threads = 1


def tenseur(octets):
    """Les trois lignes de l'API, a l'identique, puis la normalisation : (1, 3, T, T) float32."""
    im = Image.open(io.BytesIO(octets)).convert("RGB").resize((T, T), Image.BILINEAR)
    x = np.array(im, dtype=np.uint8).transpose(2, 0, 1)[None].astype(np.float32) / 255
    return (x - MOY) / ECT


reseau = torchvision.models.resnet18(weights=None)
reseau.fc = torch.nn.Linear(reseau.fc.in_features, 1)
reseau.load_state_dict(torch.load(DOSSIER / "modele.pt", map_location="cpu", weights_only=True))
reseau.eval()


def pytorch(x):
    with torch.no_grad():
        return reseau(torch.from_numpy(x)).numpy()[:, 0]


def session(fichier):
    s = ort.InferenceSession(DOSSIER / fichier, OPTIONS, providers=["CPUExecutionProvider"])
    return lambda x: s.run(None, {"entree": x})[0][:, 0]


VARIANTES = {"pytorch": ("modele.pt", pytorch), "onnx": ("modele.onnx", session("modele.onnx"))}
if (DOSSIER / "modele_int8.onnx").exists():
    VARIANTES["onnx_int8"] = ("modele_int8.onnx", session("modele_int8.onnx"))

manifeste = pd.read_csv(DOSSIER / "manifeste_echantillon.csv")
validation = manifeste[manifeste.jeu == "validation"].reset_index(drop=True)
with zipfile.ZipFile(DONNEES / "ISIC_2024_Permissive_Training_Input.zip") as z:
    lire = lambda i: z.read(f"ISIC_2024_Permissive_Training_Input/{i}.jpg")   # noqa: E731
    lot = np.concatenate([tenseur(lire(i)) for i in validation.isic_id])
    controle = tenseur(lire(META["controle"]["isic_id"]))


def roc_auc(y, score):
    """Mann-Whitney : probabilite qu'un positif soit classe au-dessus d'un negatif."""
    r = pd.Series(score).rank().to_numpy()
    n1 = y.sum()
    return (r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * (len(y) - n1))


sigmoide = lambda l: 1 / (1 + np.exp(-(l.astype(np.float64) + CORRECTION)))   # noqa: E731
y = validation.cible.to_numpy()
lignes, resume = [], []
for nom, (fichier, f) in VARIANTES.items():
    for _ in range(CHAUFFE):
        f(controle)
    durees = []
    for _ in range(MESURES):
        t0 = time.perf_counter()
        f(controle)
        durees.append((time.perf_counter() - t0) * 1000)
    proba = sigmoide(np.concatenate([f(lot[i:i + 1]) for i in range(len(lot))]))
    decision = proba >= SEUIL
    lignes.append(pd.DataFrame({"isic_id": validation.isic_id, "cible": y, "variante": nom,
                                "probabilite_maligne": proba, "a_examiner": decision}))
    resume.append({"variante": nom, "taille_mo": round((DOSSIER / fichier).stat().st_size / 1e6, 1),
                   "p50_ms": round(float(np.percentile(durees, 50)), 2),
                   "p95_ms": round(float(np.percentile(durees, 95)), 2),
                   "proba_controle": round(float(sigmoide(f(controle))[0]), 6),
                   "rappel_au_seuil": round(float(decision[y == 1].mean()), 4),
                   "alertes": int(decision.sum()),
                   "roc_auc": round(float(roc_auc(y, proba)), 4)})

table = pd.concat(lignes)
ref = table[table.variante == "pytorch"].set_index("isic_id")
for r in resume:
    v = table[table.variante == r["variante"]].set_index("isic_id")
    r["ecart_max_proba"] = float(f'{(v.probabilite_maligne - ref.probabilite_maligne).abs().max():.1e}')
    r["decisions_changees"] = int((v.a_examiner != ref.a_examiner).sum())

Path("sorties").mkdir(exist_ok=True)
table.to_csv("sorties/comparaison_variantes.csv", index=False)
print(f"{len(validation)} vignettes de validation ({int(y.sum())} malignes), seuil {SEUIL:.6f}, "
      f"controle {META['controle']['isic_id']} = {META['controle']['probabilite_maligne']} (meta S4)")
print(pd.DataFrame(resume).to_string(index=False))
