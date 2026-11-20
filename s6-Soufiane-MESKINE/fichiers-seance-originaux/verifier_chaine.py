"""Seance 6 — parcourir la chaine de tracabilite, du fichier servi au commit.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Usage :
    python verifier_chaine.py model/<run>/modele.joblib
Code de sortie 1 au premier maillon rompu : utilisable comme test.
"""
import hashlib
import json
import sys
from pathlib import Path

from mlflow import MlflowClient

SUIVI = "sqlite:///suivi/mlflow.db"
NOM = "dermascan-tabulaire"


def empreinte(chemin):
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def maillon(nom, attendu, obtenu):
    ok = attendu == obtenu
    print(f"{'OK ' if ok else 'KO '} {nom:<34} {str(obtenu)[:16]}"
          + ("" if ok else f"  (attendu {str(attendu)[:16]})"))
    if not ok:
        sys.exit(1)


def main():
    servi = Path(sys.argv[1])
    c = MlflowClient(SUIVI)
    v = c.get_model_version_by_alias(NOM, "production")
    print(f"registre : {NOM} v{v.version}, valide par {v.tags['validateur']}, "
          f"repli {v.tags['repli']}")
    maillon("fichier servi = version promue", v.tags["sha256_modele"], empreinte(servi))
    run = c.get_run(v.run_id)
    print(f"run : {run.info.run_name}  graine {run.data.params['graine']}  "
          f"PR-AUC {run.data.metrics['pr_auc']:.4f}")
    maillon("artefact du run = fichier servi", empreinte(servi),
            empreinte(c.download_artifacts(v.run_id, "model/modele.joblib")))
    maillon("manifeste du run = manifeste local", run.data.tags["sha256_manifeste"],
            empreinte("donnees/manifeste.json"))
    manifeste = json.loads(Path("donnees/manifeste.json").read_text())
    maillon("donnees du manifeste = donnees locales", manifeste["sha256"],
            empreinte(manifeste["source"]))
    print(f"commit du code qui a produit les donnees : {manifeste['commit']}")


if __name__ == "__main__":
    main()
