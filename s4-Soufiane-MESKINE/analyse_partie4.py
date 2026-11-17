import json, math
import numpy as np, pandas as pd
from sklearn.metrics import confusion_matrix, average_precision_score, roc_auc_score, precision_recall_curve
meta=json.load(open("modele_meta.json")); v=pd.read_csv("predictions_validation.csv")
y,p,pb=v.cible.to_numpy(),v.probabilite_maligne.to_numpy(),v.proba_brute.to_numpy()
S,SB=meta["seuil"],meta["seuil_brut"]
dec=p>=S
vn,fp,fn,vp=confusion_matrix(y,dec.astype(int),labels=[0,1]).ravel()
print("M11",dict(VP=vp,FN=fn,FP=fp,VN=vn,somme=vp+fn+fp+vn,n=len(v)),meta["metriques"]["matrice_confusion_validation"])
# closest to threshold
v["d"]=(v.probabilite_maligne-S); 
print("proches du seuil (recalibre):"); print(v.reindex(v.d.abs().sort_values().index).head(5).to_string())
print("seuil exact",repr(S))
# Mesure 12
rap=vp/(vp+fn); prec=vp/(vp+fp); tfp=fp/(fp+vn); part=(vp+fp)/len(v)
print("M12 rappel %.4f precision %.4f TFP %.4f part %.4f"%(rap,prec,tfp,part))
for s in [0.5,0.1,0.05,SB,0.01]:
    d=pb>=s; a=int((d&(y==1)).sum()); b=int((d&(y==0)).sum())
    print("seuil brut %.6f VP %d FP %d rappel %.4f precision %s"%(s,a,b,a/59, ("%.4f"%(a/(a+b))) if a+b else "n/a"))
# Mesure 13
beta=5000/217183; z=math.log(SB/(1-SB))
print("M13 beta",beta,"lnb",math.log(beta),"seuil recal",1/(1+math.exp(-(z+math.log(beta)))))
decb=pb>=SB
print("decisions changees",int((decb!=dec).sum()))
pi=meta["prevalence_reelle"]; pr=rap*pi/(rap*pi+tfp*(1-pi)); print("prec projetee",pr,"lesions/maligne",1/pr, meta["metriques"]["precision_projetee_prevalence_reelle"])
# Q4.4
d1=pb>=S; d2=p>=SB
for nom,d in (("1 proba brute + seuil recalibre",d1),("2 proba recalibree + seuil brut",d2)):
    print(nom,"part examen %.4f rappel %.4f"%(d.mean(), (d&(y==1)).sum()/59))
# Mesure 14
w=np.where(y==1,1.0,1/beta)
print("M14 prauc meta",meta["metriques"]["pr_auc"],"hasard",y.mean())
print("repondere",average_precision_score(y,p,sample_weight=w),"hasard",(y==1).sum()/((y==1).sum()+(y==0).sum()/beta))
print("roc",roc_auc_score(y,p),"roc ponderee",roc_auc_score(y,p,sample_weight=w))
