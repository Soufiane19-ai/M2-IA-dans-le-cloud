"""Seance 5 — distribution de reference et detection de derive (PSI) sur le journal d'inference.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Deux commandes :

  python derive.py reference MANIFESTE METADONNEES > reference_covariables.json
      proportions de chaque covariable sur le jeu d'ENTRAINEMENT de S4

  python derive.py mesurer reference_covariables.json JOURNAL [FENETRE] [SEUIL]
      JOURNAL : lignes JSON de l'API (docker logs, ou export Log Analytics) ; le reste est ignore.
      PSI de chaque covariable sur une fenetre glissante des FENETRE derniers appels 200.
      Si les request_id portent la phase (rejouer_flux.py), affiche le delai de detection.

Seuil et fenetre se decident AVANT de mesurer (tableau de decisions de l'enonce).
"""
import json
import math
import sys
from pathlib import Path

import pandas as pd

COVARIABLES = ["tbp_tile_type", "age_tranche", "anatom_site_general", "sex"]
PLANCHER = 1e-4      # une modalite absente d'un cote : proportion plancher, sinon ln(0)


def tranche(age):
    return None if pd.isna(age) else f"{int(age // 10) * 10}-{int(age // 10) * 10 + 9}"


def reference(manifeste, metadonnees):
    m = pd.read_csv(manifeste)
    m = m[m.jeu == "entrainement"].merge(
        pd.read_csv(metadonnees, usecols=["isic_id", "age_approx", "sex", "anatom_site_general",
                                          "tbp_tile_type"]), on="isic_id")
    m["age_tranche"] = m.age_approx.map(tranche)
    sortie = {"source": f"{manifeste}, jeu = entrainement", "n": len(m)}
    for c in COVARIABLES:
        # Proportions sur les valeurs PRESENTES : l'absence se suit a part (taux_absent).
        sortie[c] = {"proportions": m[c].value_counts(normalize=True).round(6).to_dict(),
                     "taux_absent": round(float(m[c].isna().mean()), 6)}
    return sortie


def psi(ref, observees):
    """Population Stability Index : somme sur les modalites de (q - p) * ln(q / p)."""
    q = observees.value_counts(normalize=True)
    total = 0.0
    for modalite in set(ref) | set(q.index):
        p_, q_ = max(ref.get(modalite, 0), PLANCHER), max(q.get(modalite, 0), PLANCHER)
        total += (q_ - p_) * math.log(q_ / p_)
    return total


def lire_journal(chemin):
    lignes = []
    for brut in open(chemin, encoding="utf-8"):
        brut = brut.strip()
        if brut.startswith("{"):
            try:
                j = json.loads(brut)
            except json.JSONDecodeError:
                continue
            if j.get("http_status") == 200 and j.get("covariables") is not None:
                lignes.append({"request_id": j["request_id"], "decision": j["decision"],
                               "probabilite_maligne": j["probabilite_maligne"], **j["covariables"]})
    return pd.DataFrame(lignes)


def mesurer(chemin_ref, chemin_journal, fenetre=200, seuil=0.25):
    ref = json.load(open(chemin_ref, encoding="utf-8"))
    j = lire_journal(chemin_journal)
    assert len(j) >= fenetre, f"{len(j)} appels journalises, moins que la fenetre ({fenetre})"
    j["phase"] = j.request_id.str.split("-").str[0]
    if j.phase.isin(["conforme", "derive"]).any():      # flux rejoue : on ignore les appels manuels
        j = j[j.phase.isin(["conforme", "derive"])].reset_index(drop=True)
    debut_derive = (j.phase == "derive").idxmax() if (j.phase == "derive").any() else None
    serie = []
    for fin in range(fenetre, len(j) + 1):
        f = j.iloc[fin - fenetre:fin]
        ligne = {"appel": fin, "phase": j.phase.iloc[fin - 1],
                 "taux_a_examiner": round((f.decision == "a_examiner").mean(), 4)}
        for c in COVARIABLES:
            ligne[f"psi_{c}"] = round(psi(ref[c]["proportions"], f[c].dropna()), 4)
            ligne[f"absent_{c}"] = round(f[c].isna().mean(), 4)
        serie.append(ligne)
    serie = pd.DataFrame(serie)
    Path("sorties").mkdir(exist_ok=True)
    serie.to_csv("sorties/psi_fenetres.csv", index=False)

    print(f"{len(j)} appels journalises, fenetre {fenetre}, seuil d'alerte PSI >= {seuil}")
    print(f"Taux a_examiner par phase : {j.groupby('phase').decision.apply(lambda d: round((d == 'a_examiner').mean(), 4)).to_dict()}")
    for c in COVARIABLES:
        col = f"psi_{c}"
        texte = f"  {c:20s} PSI derniere fenetre {serie[col].iloc[-1]:7.4f}"
        conforme = serie[serie.appel <= (debut_derive if debut_derive is not None else len(j))]
        if len(conforme):
            texte += f" | max en flux conforme {conforme[col].max():.4f}"
        if debut_derive is not None:
            apres = serie[(serie.appel > debut_derive) & (serie[col] >= seuil)]
            texte += (f" | alerte {apres.appel.iloc[0] - debut_derive} appels apres le debut de la derive"
                      if len(apres) else " | aucune alerte apres le debut de la derive")
        print(texte)


if __name__ == "__main__":
    if sys.argv[1:2] == ["reference"]:
        print(json.dumps(reference(sys.argv[2], sys.argv[3]), indent=2, ensure_ascii=False))
    elif sys.argv[1:2] == ["mesurer"]:
        mesurer(sys.argv[2], sys.argv[3], *(int(sys.argv[4]),) if len(sys.argv) > 4 else (),
                *(float(sys.argv[5]),) if len(sys.argv) > 5 else ())
    else:
        sys.exit(__doc__)
