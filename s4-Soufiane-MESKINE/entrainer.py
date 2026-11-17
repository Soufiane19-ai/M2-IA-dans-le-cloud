"""Seance 4 — entrainement ResNet18 sur les vignettes ISIC, puis paquet de modele.

Variables : N_NEGATIFS, EPOQUES_TETE, EPOQUES_DEGEL, REPRISE.
"""
import hashlib
import json
import math
import os
import platform
import resource
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torchvision
from sklearn.metrics import (average_precision_score, confusion_matrix,
                             precision_recall_curve, roc_auc_score)

import donnees as D

VERSION = "2.0.0"
EPOQUES_TETE = int(os.environ.get("EPOQUES_TETE", "4"))
EPOQUES_DEGEL = int(os.environ.get("EPOQUES_DEGEL", "4"))
COUCHES_DEGELEES = ["fc"] + (["layer4"] if EPOQUES_DEGEL else [])
LOT = 64
LR_TETE, LR_DEGEL, WEIGHT_DECAY = 1e-3, 1e-4, 1e-4
RAPPEL_CIBLE = 0.90
REPRISE = Path(os.environ.get("REPRISE", "sorties/reprise.pt"))
MODELE, META = Path("model/modele.pt"), Path("model/modele_meta.json")


def construire(poids_imagenet=True):
    r = torchvision.models.resnet18(weights="IMAGENET1K_V1" if poids_imagenet else None)
    r.fc = torch.nn.Linear(r.fc.in_features, 1)
    return r


def regler_gel(reseau, degel):
    actives = ["fc"] + (["layer4"] if degel else [])
    for nom, p in reseau.named_parameters():
        p.requires_grad = nom.split(".")[0] in actives
    return actives


def mode_entrainement(reseau, actives):
    reseau.eval()
    for nom in actives:
        getattr(reseau, nom).train()


def pauc_80(y, p):
    v = roc_auc_score(1 - y, -p, max_fpr=0.2)
    return 0.5 * 0.2 ** 2 + (0.2 - 0.5 * 0.2 ** 2) / (1.0 - 0.5) * (v - 0.5)


@torch.no_grad()
def logits(reseau, x, dispositif):
    reseau.eval()
    return torch.cat([reseau(D.vers_tenseur(x[i:i + 256]).to(dispositif)).squeeze(1).cpu()
                      for i in range(0, len(x), 256)]).double().numpy()


def seuil_pour_rappel(y, proba, cible):
    precision, rappel, seuils = precision_recall_curve(y, proba)
    i = np.where(rappel >= cible)[0][-1]
    return float(seuils[min(i, len(seuils) - 1)]), float(precision[i]), float(rappel[i])


def sigmoide(z):
    return 1 / (1 + np.exp(-z))


def ram_max_mo():
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return r / 1e6 if sys.platform == "darwin" else r / 1e3   # octets sur macOS, Ko sur Linux


def main():
    torch.manual_seed(D.GRAINE)
    dispositif = "cuda" if torch.cuda.is_available() else "cpu"
    Path("sorties").mkdir(exist_ok=True)
    t_debut = time.time()

    d, e = D.preparer()
    ids = e.isic_id.tolist()
    x = D.charger_vignettes(ids)
    y = e.cible.to_numpy()
    tr, va = (e.jeu == "entrainement").to_numpy(), (e.jeu == "validation").to_numpy()
    xtr, ytr, xva, yva = x[tr], y[tr], x[va], y[va]
    print(f"[{dispositif}] entrainement {len(xtr)} ({ytr.sum()} pos), validation {len(xva)} "
          f"({yva.sum()} pos), chargement {time.time() - t_debut:.1f} s")

    reseau = construire().to(dispositif)
    perte = torch.nn.BCEWithLogitsLoss()
    gen = torch.Generator().manual_seed(D.GRAINE)
    historique, meilleur, debut, ck = [], {"pr_auc": -1}, 0, None
    if REPRISE.exists():
        ck = torch.load(REPRISE, weights_only=False)
        reseau.load_state_dict(ck["etat"])
        historique, meilleur, debut = ck["historique"], ck["meilleur"], ck["epoque"] + 1
        gen.set_state(ck["generateur"])
        print(f"reprise a l'epoque {debut + 1}")

    optim = None
    for ep in range(debut, EPOQUES_TETE + EPOQUES_DEGEL):
        degel = ep >= EPOQUES_TETE
        actives = regler_gel(reseau, degel)
        if optim is None or ep == EPOQUES_TETE:
            optim = torch.optim.AdamW([p for p in reseau.parameters() if p.requires_grad],
                                      lr=LR_DEGEL if degel else LR_TETE, weight_decay=WEIGHT_DECAY)
            if ck is not None and ep == debut and ck["degel"] == degel:
                optim.load_state_dict(ck["optim"])
        t0 = time.time()
        mode_entrainement(reseau, actives)
        ordre = torch.randperm(len(xtr), generator=gen).numpy()
        cumul = 0.0
        for i in range(0, len(ordre), LOT):
            j = ordre[i:i + LOT]
            xb = D.augmenter(D.vers_tenseur(xtr[j]), gen).to(dispositif)
            yb = torch.from_numpy(ytr[j]).float().to(dispositif)
            optim.zero_grad()
            l = perte(reseau(xb).squeeze(1), yb)
            l.backward()
            optim.step()
            cumul += l.item() * len(j)
        p = sigmoide(logits(reseau, xva, dispositif))
        ligne = {"epoque": ep + 1, "phase": "degel" if degel else "tete",
                 "perte_entrainement": cumul / len(xtr),
                 "pr_auc": average_precision_score(yva, p), "roc_auc": roc_auc_score(yva, p),
                 "pauc_80": pauc_80(yva, p), "duree_s": time.time() - t0}
        historique.append(ligne)
        print(" ".join(f"{k} {v:.4f}" if isinstance(v, float) else f"{k} {v}" for k, v in ligne.items()))
        if ligne["pr_auc"] > meilleur["pr_auc"]:
            meilleur = {"pr_auc": ligne["pr_auc"], "epoque": ep + 1,
                        "etat": {k: v.detach().cpu().clone() for k, v in reseau.state_dict().items()}}
        torch.save({"epoque": ep, "degel": degel, "etat": reseau.state_dict(), "optim": optim.state_dict(),
                    "historique": historique, "meilleur": meilleur, "generateur": gen.get_state()},
                   REPRISE.with_suffix(".tmp"))
        os.replace(REPRISE.with_suffix(".tmp"), REPRISE)

    reseau.load_state_dict(meilleur["etat"])
    REPRISE.unlink(missing_ok=True)
    duree = time.time() - t_debut
    z = logits(reseau, xva, dispositif)
    p = sigmoide(z)

    n_neg_total = int((d.cible == 0).sum())
    beta = D.N_NEGATIFS / n_neg_total
    correction = math.log(beta)
    prev_reelle, prev_ech = float(d.cible.mean()), float(e.cible.mean())
    z_seuil, prec_val, rappel = seuil_pour_rappel(yva, z, RAPPEL_CIBLE)
    seuil_brut, seuil = float(sigmoide(z_seuil)), float(sigmoide(z_seuil + correction))
    p_cal = sigmoide(z + correction)
    decision = z >= z_seuil
    assert ((p_cal >= seuil) == decision).all(), "decisions modifiees"
    vn, fp, fn, vp = confusion_matrix(yva, decision.astype(int), labels=[0, 1]).ravel()
    tfp = fp / (fp + vn)
    prec_reelle = rappel * prev_reelle / (rappel * prev_reelle + tfp * (1 - prev_reelle))

    latence = {}
    for disp in (["cpu", "cuda"] if dispositif == "cuda" else ["cpu"]):
        r = reseau.to(disp).eval()
        xb = D.vers_tenseur(xva[:1]).to(disp)
        with torch.no_grad():
            for _ in range(5):
                r(xb)
            mes = []
            for _ in range(50):
                t0 = time.perf_counter()
                r(xb)
                if disp == "cuda":
                    torch.cuda.synchronize()
                mes.append(1000 * (time.perf_counter() - t0))
        latence[disp] = {"p50_ms": float(np.percentile(mes, 50)), "p95_ms": float(np.percentile(mes, 95))}
    reseau.to("cpu")

    torch.save(reseau.state_dict(), MODELE)
    i_ctrl = int(np.argmax(yva))
    meta = {
        "version": VERSION,
        "architecture": "resnet18",
        "sortie": "1 logit ; probabilite_maligne = sigmoide(logit + correction_logit)",
        "taille_entree": D.TAILLE,
        "normalisation": {"moyenne": D.MOYENNE, "ecart_type": D.ECART_TYPE},
        "redimensionnement": "PIL RGB, resize (taille_entree, taille_entree), BILINEAR",
        "graine": D.GRAINE,
        "echantillonnage": {
            "methode": "tous les positifs + negatifs tires uniformement sans remise (pandas.sample)",
            "source": "ISIC 2024 SLICE-3D Permissive, licence CC-BY 4.0",
            "n_positifs": int((e.cible == 1).sum()), "n_negatifs": D.N_NEGATIFS,
            "n_negatifs_disponibles": n_neg_total, "taux_negatifs": beta, "graine": D.GRAINE,
            "manifeste": D.MANIFESTE,
            "sha256_manifeste": hashlib.sha256((MODELE.parent / D.MANIFESTE).read_bytes()).hexdigest()},
        "decoupage": {"methode": "StratifiedGroupKFold(5) sur patient_id, pli 0 en validation",
                      "n_entrainement": int(tr.sum()), "n_validation": int(va.sum()),
                      "positifs_validation": int(yva.sum()), "patients_communs": 0},
        "entrainement": {"dispositif": dispositif, "epoques_tete": EPOQUES_TETE,
                         "epoques_degel": EPOQUES_DEGEL, "couches_degelees": COUCHES_DEGELEES,
                         "lot": LOT, "lr_tete": LR_TETE, "lr_degel": LR_DEGEL,
                         "weight_decay": WEIGHT_DECAY, "perte": "BCEWithLogitsLoss sans ponderation",
                         "augmentations": ["flip horizontal", "flip vertical", "rotation 90 degres"],
                         "critere_selection": "pr_auc validation", "epoque_retenue": meilleur["epoque"],
                         "duree_totale_s": round(duree, 1),
                         "duree_moyenne_epoque_s": round(float(np.mean([h["duree_s"] for h in historique])), 1),
                         "ram_max_mo": round(ram_max_mo())},
        "prevalence_entrainement": prev_ech,
        "prevalence_reelle": prev_reelle,
        "correction_logit": correction,
        "rappel_cible": RAPPEL_CIBLE,
        "seuil_brut": seuil_brut,
        "seuil": seuil,
        "metriques": {"pr_auc": float(average_precision_score(yva, p)), "roc_auc": float(roc_auc_score(yva, p)),
                      "pauc_80": float(pauc_80(yva, p)), "hasard_pr_auc": float(yva.mean()),
                      "rappel_au_seuil": rappel, "precision_au_seuil_validation": prec_val,
                      "precision_projetee_prevalence_reelle": prec_reelle,
                      "lesions_examinees_par_maligne_reelle": round(1 / prec_reelle),
                      "matrice_confusion_validation": {"VP": int(vp), "FP": int(fp), "FN": int(fn), "VN": int(vn)}},
        "latence_inference_lot1": latence,
        "controle": {"isic_id": e.isic_id[va].iloc[i_ctrl], "probabilite_maligne": round(float(p_cal[i_ctrl]), 6)},
        "sha256_poids": hashlib.sha256(MODELE.read_bytes()).hexdigest(),
        "entraine_le": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "versions": {"python": platform.python_version(), "torch": torch.__version__,
                     "torchvision": torchvision.__version__},
    }
    META.write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    pd.DataFrame(historique).to_csv("sorties/historique.csv", index=False)
    pd.DataFrame({"isic_id": e.isic_id[va].to_numpy(), "cible": yva, "proba_brute": p,
                  "probabilite_maligne": p_cal}).to_csv("sorties/predictions_validation.csv", index=False)
    print(json.dumps({k: meta[k] for k in ("seuil_brut", "seuil", "correction_logit", "metriques",
                                           "latence_inference_lot1", "controle")}, indent=2))
    print(f"duree totale {duree:.0f} s, RAM max {ram_max_mo():.0f} Mo, "
          f"{MODELE} {MODELE.stat().st_size / 1e6:.1f} Mo")


if __name__ == "__main__":
    main()
