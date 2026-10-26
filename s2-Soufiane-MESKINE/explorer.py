"""Exploration du jeu ISIC 2024 (seance 2, partie 1).

Ne produit aucun modele : uniquement les chiffres reportes dans EXPLORATION.md.
Lancement : python3 explorer.py
"""
import pandas as pd

# low_memory=False : lecture d'un seul bloc, types deduits sur la colonne entiere
# (sinon pandas devine bloc par bloc et produit des avertissements de type mixte).
d = pd.read_csv("data/train-metadata.csv", low_memory=False)

# --- 1.2 Volumetrie et structure ------------------------------------------
print("lignes, colonnes :", d.shape)
print("patients distincts :", d["patient_id"].nunique())
tailles = d.groupby("patient_id").size()
print("lesions par patient :", tailles.min(), int(tailles.median()), tailles.max())
print("\ntypes des colonnes :")
print(d.dtypes.to_string())

# --- 1.3 Colonnes qui trahissent la reponse --------------------------------
SUSPECTES = ["iddx_full", "iddx_1", "mel_thick_mm", "mel_mitotic_index", "lesion_id"]
total_malignes = int(d["target"].sum())
print("\ncolonnes suspectes (malignes au total :", total_malignes, ")")
for c in SUSPECTES:
    rempli = d[c].notna().sum()
    malignes = d.loc[d[c].notna(), "target"].sum()
    print(f"{c:<22} rempli {rempli:>7}  dont malignes {int(malignes):>4}")

# Les autres colonnes iddx_* (diagnostics detailles) sont aussi posterieures au diagnostic.
IDDX = [c for c in d.columns if c.startswith("iddx_")]
print("famille iddx_* :", IDDX)
for c in IDDX:
    print(f"  {c:<20} valeurs : {d[c].dropna().unique()[:6].tolist()}")

# --- 1.4 Valeurs manquantes et colonnes constantes -------------------------
na = d.isna().sum()
print("\nvaleurs manquantes (nombre, taux) :")
manq = na[na > 0].sort_values(ascending=False)
print(pd.DataFrame({"manquantes": manq, "taux_%": (manq / len(d) * 100).round(3)}).to_string())
constantes = [c for c in d.columns if d[c].nunique(dropna=True) <= 1]
print("constantes :", constantes)
for c in constantes:
    print(f"  {c} = {d[c].dropna().unique().tolist()}")

# --- 1.5 Distribution de la cible -----------------------------------------
n1 = int((d["target"] == 1).sum())
n0 = int((d["target"] == 0).sum())
print("\ncible : target=1 :", n1, " target=0 :", n0)
print("taux de positifs : %.4f %%" % (100 * n1 / len(d)))
print("une maligne pour %.0f benignes" % (n0 / n1))
print("exactitude du classifieur 'toujours benin' : %.4f %%" % (100 * n0 / len(d)))

# --- Complements pour la model card ---------------------------------------
print("\ninstitutions (attribution) :")
print(d["attribution"].value_counts().to_string())
print("\nsexe :")
print(d["sex"].value_counts(dropna=False).to_string())
print("\nage approximatif : min %s, mediane %s, max %s" % (
    d["age_approx"].min(), d["age_approx"].median(), d["age_approx"].max()))
print("\nlocalisation simplifiee :")
print(d["anatom_site_general"].value_counts(dropna=False).to_string())
print("\ntype d'image :")
print(d["tbp_tile_type"].value_counts(dropna=False).to_string())
