"""Seance 6 — manifeste du jeu de donnees et decoupages par patient.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Ecrit donnees/manifeste.json et un decoupage par graine
(donnees/decoupage_<graine>.json). Toutes les approches lisent les memes
fichiers : sinon leurs chiffres ne se comparent pas.
"""
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

import pandas as pd
from sklearn.model_selection import GroupShuffleSplit

SOURCE = Path("data/train-metadata.csv")
SORTIE = Path("donnees")
GRAINES = [42, 7]


def empreinte(chemin):
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def commit_courant():
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "hors-git"


def main():
    SORTIE.mkdir(exist_ok=True)
    d = pd.read_csv(SOURCE, usecols=["isic_id", "patient_id", "target"], low_memory=False)
    manifeste = {
        "source": str(SOURCE),
        "sha256": empreinte(SOURCE),
        "lignes": len(d),
        "positifs": int(d["target"].sum()),
        "patients": int(d["patient_id"].nunique()),
        "decoupages": {},
        "cree_le": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "commit": commit_courant(),
    }
    for graine in GRAINES:
        tr, te = next(GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=graine)
                      .split(d, d["target"], groups=d["patient_id"]))
        patients_test = sorted(set(d["patient_id"].iloc[te]))
        communs = set(d["patient_id"].iloc[tr]) & set(patients_test)
        if communs:
            sys.exit(f"fuite : {len(communs)} patients des deux cotes (graine {graine})")
        chemin = SORTIE / f"decoupage_{graine}.json"
        chemin.write_text(json.dumps({"graine": graine, "unite": "patient_id",
                                      "patients_test": patients_test}, indent=1))
        manifeste["decoupages"][str(graine)] = {
            "fichier": str(chemin), "sha256": empreinte(chemin),
            "lignes_test": int(len(te)), "positifs_test": int(d["target"].iloc[te].sum()),
            "patients_test": len(patients_test)}
        print(f"graine {graine} : {len(tr):,} / {len(te):,} lignes, "
              f"{int(d['target'].iloc[te].sum())} positifs en test, intersection vide")
    (SORTIE / "manifeste.json").write_text(json.dumps(manifeste, indent=2))
    print(f"manifeste : {SORTIE / 'manifeste.json'}  sha256 {empreinte(SORTIE / 'manifeste.json')[:12]}")


if __name__ == "__main__":
    main()
