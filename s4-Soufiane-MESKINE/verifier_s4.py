"""Seance 4 — controle du paquet de modele AVANT de construire l'image.

Usage : python verifier_s4.py [dossier_du_paquet]     (par defaut : model)
Code retour 0 si recevable, 1 sinon. Ne fait aucun appel a Azure.
"""
import hashlib
import io
import json
import math
import os
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torchvision

CLES = ["version", "architecture", "taille_entree", "normalisation", "graine", "echantillonnage",
        "decoupage", "entrainement", "prevalence_entrainement", "prevalence_reelle",
        "correction_logit", "rappel_cible", "seuil_brut", "seuil", "metriques", "controle",
        "sha256_poids", "entraine_le", "versions"]
resultats = []


def controle(libelle, condition, detail=""):
    resultats.append(bool(condition))
    print(f"{'OK    ' if condition else 'ECHEC '} {libelle}{'  — ' + str(detail) if detail else ''}")


def main():
    dossier = Path(sys.argv[1] if len(sys.argv) > 1 else "model")
    poids, chemin_meta = dossier / "modele.pt", dossier / "modele_meta.json"
    if not (poids.exists() and chemin_meta.exists()):
        sys.exit(f"usage : python verifier_s4.py <dossier>  ({poids} ou {chemin_meta} introuvable)")
    meta = json.loads(chemin_meta.read_text())

    # 1. Metadonnees completes
    manquantes = [c for c in CLES if c not in meta]
    controle("cles du meta", not manquantes, manquantes or f"{len(CLES)} cles")
    if manquantes:
        return 1

    # 2. Integrite et tracabilite
    controle("sha256 des poids", hashlib.sha256(poids.read_bytes()).hexdigest() == meta["sha256_poids"])
    ech = meta["echantillonnage"]
    man = dossier / ech["manifeste"]
    controle("manifeste present et intact", man.exists()
             and hashlib.sha256(man.read_bytes()).hexdigest() == ech["sha256_manifeste"])
    m = pd.read_csv(man)
    controle("effectifs du manifeste = meta", (m.cible == 1).sum() == ech["n_positifs"]
             and (m.cible == 0).sum() == ech["n_negatifs"], f"{(m.cible == 1).sum()} + {(m.cible == 0).sum()}")
    communs = set(m.patient_id[m.jeu == "entrainement"]) & set(m.patient_id[m.jeu == "validation"])
    controle("aucun patient des deux cotes", not communs, f"{len(communs)} en commun")

    # 3. Rechargement
    reseau = torchvision.models.resnet18(weights=None)
    reseau.fc = torch.nn.Linear(reseau.fc.in_features, 1)
    etat = torch.load(poids, map_location="cpu", weights_only=True)
    reseau.load_state_dict(etat)
    reseau.eval()
    t = meta["taille_entree"]
    with torch.no_grad():
        sortie = reseau(torch.zeros(2, 3, t, t))
    controle("sortie (lot, 1) : un logit par image", tuple(sortie.shape) == (2, 1), tuple(sortie.shape))

    # 4. Gel
    couches = meta["entrainement"]["couches_degelees"]
    try:
        ref = torchvision.models.resnet18(weights="IMAGENET1K_V1").state_dict()
        bouge = [k for k in ref if k.split(".")[0] not in couches and k in etat
                 and not k.endswith("num_batches_tracked") and not torch.equal(ref[k], etat[k])]
        controle(f"backbone gele hors {couches}", not bouge, bouge[:3] or f"{len(ref)} tenseurs compares")
    except Exception as exc:                                   # noqa: BLE001
        print(f"SAUTE  gel non verifiable (poids ImageNet indisponibles : {type(exc).__name__})")

    # 5. Seuil et recalibration
    beta = ech["n_negatifs"] / ech["n_negatifs_disponibles"]
    controle("correction_logit = ln(n_negatifs / negatifs disponibles)",
             abs(meta["correction_logit"] - math.log(beta)) < 1e-9, f"{meta['correction_logit']:.4f}")
    sb = meta["seuil_brut"]
    attendu = 1 / (1 + math.exp(-(math.log(sb / (1 - sb)) + meta["correction_logit"])))
    controle("seuil = seuil_brut recalibre", abs(meta["seuil"] - attendu) < 1e-9,
             f"{sb:.4f} -> {meta['seuil']:.6f}")
    controle("prevalence reelle < prevalence d'entrainement",
             meta["prevalence_reelle"] < meta["prevalence_entrainement"])
    mt = meta["metriques"]
    controle("PR-AUC au-dessus du hasard", mt["pr_auc"] > mt["hasard_pr_auc"],
             f"{mt['pr_auc']:.3f} contre {mt['hasard_pr_auc']:.3f}")
    controle("rappel au seuil >= rappel cible", mt["rappel_au_seuil"] >= meta["rappel_cible"])

    # 6. Image de controle
    zp = Path(os.environ.get("DONNEES", "donnees")) / "ISIC_2024_Permissive_Training_Input.zip"
    if zp.exists():
        c = meta["controle"]
        with zipfile.ZipFile(zp) as z:
            octets = z.read(f"ISIC_2024_Permissive_Training_Input/{c['isic_id']}.jpg")
        from PIL import Image
        im = Image.open(io.BytesIO(octets)).convert("RGB").resize((t, t), Image.BILINEAR)
        x = torch.from_numpy(np.array(im, dtype=np.uint8)).permute(2, 0, 1).float().div(255)
        n = meta["normalisation"]
        x = (x - torch.tensor(n["moyenne"]).view(3, 1, 1)) / torch.tensor(n["ecart_type"]).view(3, 1, 1)
        with torch.no_grad():
            p = 1 / (1 + math.exp(-(reseau(x.unsqueeze(0)).item() + meta["correction_logit"])))
        controle(f"controle {c['isic_id']} reproduit", abs(p - c["probabilite_maligne"]) < 1e-5,
                 f"{p:.6f} contre {c['probabilite_maligne']}")
    else:
        print(f"SAUTE  concordance (vignettes absentes : {zp})")

    ok = all(resultats)
    print(f"\n{sum(resultats)}/{len(resultats)} controles OK — {'RENDU RECEVABLE' if ok else 'RENDU NON RECEVABLE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
