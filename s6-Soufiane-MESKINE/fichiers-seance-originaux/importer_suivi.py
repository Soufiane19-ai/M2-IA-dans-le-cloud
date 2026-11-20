"""Seance 6 — rendre lisible sur le poste un suivi ecrit ailleurs (Colab).

Fichier distribue en debut de seance : lisez-le avant de le lancer. MLflow enregistre l'emplacement des artefacts en chemin
ABSOLU (/content/... sur Colab). Apres export, metriques et parametres se
relisent, mais les artefacts pointent vers un dossier qui n'existe plus ici.
Ce script reecrit ce prefixe vers suivi/artefacts du poste. Usage :
    python importer_suivi.py
"""
import sqlite3
from pathlib import Path

BASE = Path("suivi/mlflow.db")
COLONNES = [("experiments", "artifact_location"), ("runs", "artifact_uri"),
            ("model_versions", "source"), ("model_versions", "storage_location")]


def main():
    nouveau = str(Path("suivi/artefacts").resolve())
    with sqlite3.connect(BASE) as cx:
        anciens = {r[0] for r in cx.execute(
            "SELECT artifact_location FROM experiments WHERE artifact_location LIKE '%/suivi/artefacts'")}
        for ancien in anciens - {nouveau}:
            for table, col in COLONNES:
                if col not in {r[1] for r in cx.execute(f"PRAGMA table_info({table})")}:
                    continue
                n = cx.execute(f"UPDATE {table} SET {col} = replace({col}, ?, ?) "
                               f"WHERE {col} LIKE ? || '%'", (ancien, nouveau, ancien)).rowcount
                print(f"{table}.{col} : {n} ligne(s) {ancien} -> {nouveau}")
    if not anciens - {nouveau}:
        print("rien a reecrire : le suivi pointe deja vers ce poste")


if __name__ == "__main__":
    main()
