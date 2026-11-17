"""Seance 5 - mesure 4 et question 3.1, a partir de sorties/comparaison_variantes.csv."""
import json

import pandas as pd

t = pd.read_csv("sorties/comparaison_variantes.csv")
meta = json.load(open("model/modele_meta.json"))
SEUIL = meta["seuil"]
p = t[t.variante == "pytorch"].set_index("isic_id")
for nom in [v for v in t.variante.unique() if v != "pytorch"]:
    q = t[t.variante == nom].set_index("isic_id")
    change = q.a_examiner != p.a_examiner
    print(f"== {nom}")
    print("vers a_examiner :", int((change & q.a_examiner).sum()),
          " vers surveillance :", int((change & ~q.a_examiner).sum()))
    print("malignes parmi les changees :", int(p[change].cible.sum()))
    print("decisions changees :", list(p[change].index))
    print((q.probabilite_maligne / p.probabilite_maligne).describe().to_string())

# Question 3.1 : les malignes les plus proches du seuil, sous chaque variante
mal = t[t.cible == 1].copy()
mal["ecart_au_seuil"] = mal.probabilite_maligne - SEUIL
proches = mal.loc[mal.ecart_au_seuil.abs().sort_values().index].head(9)
print("== malignes les plus proches du seuil", SEUIL)
print(proches.to_string(index=False))
print("rappel_au_seuil du meta :", meta["metriques"]["rappel_au_seuil"])
