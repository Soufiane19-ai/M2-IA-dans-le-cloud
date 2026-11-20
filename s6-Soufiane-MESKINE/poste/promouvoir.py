"""Seance 6 — promouvoir un run au registre, avec validateur et repli.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Usage :
    python promouvoir.py --run <run_id> --validateur "Prenom Nom"
La version promue recoit l'alias production ; celle qu'elle remplace recoit
l'alias repli. Le registre pointe vers le fichier exact du run : son
empreinte doit egaler celle du fichier servi.
"""
import argparse

from mlflow import MlflowClient
from mlflow.exceptions import MlflowException

SUIVI = "sqlite:///suivi/mlflow.db"
NOM = "dermascan-tabulaire"
ALIAS_SERVI = "production"
ALIAS_REPLI = "repli"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--run", required=True)
    p.add_argument("--validateur", required=True)
    a = p.parse_args()

    c = MlflowClient(SUIVI)
    try:
        c.create_registered_model(NOM)
    except MlflowException:
        pass  # deja cree par une promotion precedente
    try:
        precedente = c.get_model_version_by_alias(NOM, ALIAS_SERVI).version
    except MlflowException:
        precedente = None

    run = c.get_run(a.run)
    v = c.create_model_version(
        NOM, source=f"{run.info.artifact_uri}/model/modele.joblib", run_id=a.run,
        tags={"sha256_modele": run.data.tags["sha256_modele"], "validateur": a.validateur,
              "repli": precedente or "aucune"})
    c.set_registered_model_alias(NOM, ALIAS_SERVI, v.version)
    if precedente:
        c.set_registered_model_alias(NOM, ALIAS_REPLI, precedente)
    print(f"{NOM} v{v.version} -> production (run {run.info.run_name}, valide par "
          f"{a.validateur}) ; repli : {precedente or 'aucune'}")


if __name__ == "__main__":
    main()
