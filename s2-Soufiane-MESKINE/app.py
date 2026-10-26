"""API d'inference DermaScan (seance 2, partie 3).

Contrat d'interface (seance 3) :
  GET  /health      200 si le modele est charge, 503 sinon
  GET  /model/info  version, seuil, rappel vise, metriques, prevalence, colonnes
  POST /predict     corps JSON -> probabilite, seuil applique, decision, version
Variables lues : PORT (defaut 8000), MODEL_PATH (defaut model/modele.joblib), SEUIL.
"""
import os

import joblib
import pandas as pd
from flask import Flask, jsonify, request

# Chargement au demarrage, PAS dans la fonction de vue : une seule fois par processus.
# Un modele absent n'empeche pas le demarrage : c'est /health qui signale l'indisponibilite.
try:
    PAQUET = joblib.load(os.environ.get("MODEL_PATH", "model/modele.joblib"))
    PIPELINE = PAQUET["pipeline"]
    SEUIL = float(os.environ.get("SEUIL", PAQUET["seuil"]))
    COLONNES = PAQUET["colonnes_attendues"]
    ERREUR = None
except Exception as exc:
    PAQUET, PIPELINE, SEUIL, COLONNES = None, None, None, []
    ERREUR = f"{type(exc).__name__}: {exc}"

app = Flask(__name__)


@app.get("/health")
def health():
    if PIPELINE is None:
        return jsonify({"status": "indisponible", "model_loaded": False, "erreur": ERREUR}), 503
    return jsonify({"status": "ok", "model_loaded": True, "version_modele": PAQUET["version"]}), 200


@app.get("/model/info")
def model_info():
    if PIPELINE is None:
        return jsonify({"error": "modele non charge", "detail": ERREUR}), 503
    return jsonify({
        "version": PAQUET["version"],
        "seuil": SEUIL,
        "rappel_cible": PAQUET["rappel_cible"],
        "metriques": PAQUET["metriques"],
        "prevalence_entrainement": PAQUET["prevalence_entrainement"],
        "entraine_le": PAQUET["entraine_le"],
        "versions": PAQUET.get("versions", {}),
        "colonnes_attendues": COLONNES,
        "nombre_colonnes": len(COLONNES),
    })


@app.post("/predict")
def predict():
    if PIPELINE is None:
        return jsonify({"error": "modele non charge", "detail": ERREUR}), 503
    # Validation avant prediction : une charge incomplete donne un 400 explicite, jamais un 500.
    charge = request.get_json(silent=True)
    if not isinstance(charge, dict) or not charge:
        return jsonify({"error": "corps JSON absent ou invalide",
                        "attendu": "un objet JSON avec les colonnes de /model/info"}), 400
    manquantes = [c for c in COLONNES if c not in charge]
    if manquantes:
        return jsonify({"error": "variables manquantes", "nombre": len(manquantes),
                        "manquantes": manquantes[:10]}), 400
    # None -> valeur manquante : l'imputation du pipeline s'en charge, comme a l'entrainement.
    ligne = pd.DataFrame([{c: charge[c] for c in COLONNES}], columns=COLONNES)
    ligne = ligne.replace({None: float("nan")})
    try:
        proba = float(PIPELINE.predict_proba(ligne)[0, 1])
    except (ValueError, TypeError) as exc:
        return jsonify({"error": "valeurs invalides", "detail": str(exc)}), 400
    return jsonify({
        "probabilite_maligne": round(proba, 6),
        "seuil": SEUIL,
        "decision": "a_examiner" if proba >= SEUIL else "surveillance",
        "version_modele": PAQUET["version"],
        "rappel_cible": PAQUET["rappel_cible"],
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
