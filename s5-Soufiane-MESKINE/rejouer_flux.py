"""Seance 5 — rejouer un flux de consultations contre l'API, conforme ou derive.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Les vignettes viennent de l'archive ISIC de S4 (lues dans le zip),
JAMAIS de l'echantillon d'entrainement (manifeste exclu). Chaque appel envoie l'image et
ses quatre covariables, comme le ferait le poste de consultation.

  conforme : tirage uniforme dans l'archive, la composition du flux reel
  derive   : tirage restreint par un levier -- la derive se provoque, elle ne s'attend pas
             eclairage : tbp_tile_type = 3D: XP (lumiere polarisee seule, ex. un nouveau centre)
             age       : age_approx >= 70
             site      : anatom_site_general = head/neck

Usage :  python rejouer_flux.py URL PHASE [N] [DEBIT] [LEVIER]
         python rejouer_flux.py http://localhost:8000 conforme 400 0 ; ... derive 400 0 eclairage
DEBIT en requetes par seconde (0 = aussi vite que possible). Donnees dans $DONNEES.
"""
import os
import sys
import time
import zipfile
from pathlib import Path

import pandas as pd
import requests

URL, PHASE = sys.argv[1].rstrip("/"), sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 400
DEBIT = float(sys.argv[4]) if len(sys.argv) > 4 else 0
LEVIER = sys.argv[5] if len(sys.argv) > 5 else "eclairage"
DONNEES = Path(os.environ.get("DONNEES", "donnees"))
MANIFESTE = Path(os.environ.get("MANIFESTE", "model/manifeste_echantillon.csv"))
COLONNES = ["age_approx", "sex", "anatom_site_general", "tbp_tile_type"]
LEVIERS = {"eclairage": lambda d: d.tbp_tile_type == "3D: XP",
           "age": lambda d: d.age_approx >= 70,
           "site": lambda d: d.anatom_site_general == "head/neck"}
assert PHASE in ("conforme", "derive") and LEVIER in LEVIERS, __doc__

archive = pd.read_csv(DONNEES / "ISIC_2024_Permissive_Training_GroundTruth.csv", usecols=["isic_id"])
meta = pd.read_csv(DONNEES / "train-metadata.csv", usecols=["isic_id", "patient_id"] + COLONNES)
d = archive.merge(meta, on="isic_id")
d = d[~d.isic_id.isin(pd.read_csv(MANIFESTE).isic_id)]          # jamais une vignette d'entrainement
if PHASE == "derive":
    d = d[LEVIERS[LEVIER](d)]
graine = {"conforme": 1, "derive": 2}[PHASE]                     # deux phases, deux tirages distincts
flux = d.sample(n=N, random_state=graine)

codes, alertes = {}, 0
with zipfile.ZipFile(DONNEES / "ISIC_2024_Permissive_Training_Input.zip") as z, requests.Session() as s:
    for k, ligne in enumerate(flux.itertuples(index=False), 1):
        debut = time.monotonic()
        champs = {c: str(getattr(ligne, c)) for c in COLONNES if pd.notna(getattr(ligne, c))}
        try:
            r = s.post(f"{URL}/predict", data=champs, timeout=60,
                       files={"image": (f"{ligne.isic_id}.jpg",
                                        z.read(f"ISIC_2024_Permissive_Training_Input/{ligne.isic_id}.jpg"),
                                        "image/jpeg")},
                       # request_id porte la phase : le journal dira ou la derive a commence.
                       headers={"X-Request-Id": f"{PHASE}-{LEVIER if PHASE == 'derive' else 'flux'}-{k:05d}",
                                "X-Patient-Ref": ligne.patient_id})
        except requests.RequestException as exc:
            # Un appel perdu (delai de 60 s observe sur Azure le 25/10) ne doit pas tuer 20 min de rejeu.
            codes[type(exc).__name__] = codes.get(type(exc).__name__, 0) + 1
            continue
        codes[r.status_code] = codes.get(r.status_code, 0) + 1
        alertes += r.ok and r.json()["decision"] == "a_examiner"
        if DEBIT:
            time.sleep(max(0.0, 1 / DEBIT - (time.monotonic() - debut)))

print(f"{PHASE} ({LEVIER if PHASE == 'derive' else 'archive'}) : {N} appels, codes {codes}, "
      f"a_examiner {alertes} ({alertes / max(codes.get(200, 0), 1):.1%})")
