"""Seance 4 — API d'inference."""
import json
import math
import os
import socket
import time
from pathlib import Path

import numpy as np
import torch
import torchvision
from flask import Flask, jsonify, request
from PIL import Image

CHEMIN_MODELE = os.environ.get("MODEL_PATH", "model/modele.pt")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "isic-vignettes-api")
PORT = int(os.environ.get("PORT", "8000"))
STARTED_AT = time.time()

app = Flask(__name__)

try:
    META = json.loads(Path(CHEMIN_MODELE).with_name("modele_meta.json").read_text())
    RESEAU = torchvision.models.resnet18(weights=None)
    RESEAU.fc = torch.nn.Linear(RESEAU.fc.in_features, 1)
    RESEAU.load_state_dict(torch.load(CHEMIN_MODELE, map_location="cpu", weights_only=True))
    RESEAU.eval()
    SEUIL = float(os.environ.get("SEUIL", META["seuil"]))
    MOYENNE = torch.tensor(META["normalisation"]["moyenne"]).view(3, 1, 1)
    ECART = torch.tensor(META["normalisation"]["ecart_type"]).view(3, 1, 1)
    ERREUR_CHARGEMENT = None
except Exception as exc:                                   # noqa: BLE001
    META = RESEAU = SEUIL = None
    ERREUR_CHARGEMENT = f"{type(exc).__name__}: {exc}"


@app.get("/health")
def health():
    pret = RESEAU is not None
    corps = {"status": "ok" if pret else "degraded",
             "model_loaded": pret,
             "service": SERVICE_NAME,
             "hostname": socket.gethostname(),
             "uptime_seconds": round(time.time() - STARTED_AT, 1)}
    if not pret:
        corps["error"] = ERREUR_CHARGEMENT
    return jsonify(corps), (200 if pret else 503)


@app.get("/model/info")
def info():
    if RESEAU is None:
        return jsonify({"error": "modele non charge"}), 503
    return jsonify({
        "version": META["version"],
        "version_deployee": os.environ.get("MODEL_VERSION"),
        "seuil": SEUIL,
        "rappel_cible": META["rappel_cible"],
        "metriques": META["metriques"],
        "prevalence_entrainement": META["prevalence_entrainement"],
        "prevalence_reelle": META["prevalence_reelle"],
        "architecture": META["architecture"],
        "taille_entree": META["taille_entree"],
        "echantillonnage": META["echantillonnage"],
        "sha256_poids": META["sha256_poids"],
        "entraine_le": META["entraine_le"],
    })


@app.post("/predict")
def predict():
    if RESEAU is None:
        return jsonify({"error": "modele non charge"}), 503

    fichier = request.files.get("image")
    if fichier is None:
        return jsonify({"error": "champ multipart 'image' attendu",
                        "exemple": "curl -F image=@ISIC_xxx.jpg .../predict"}), 400
    try:
        t = META["taille_entree"]
        im = Image.open(fichier.stream).convert("RGB").resize((t, t), Image.BILINEAR)
        x = torch.from_numpy(np.array(im, dtype=np.uint8)).permute(2, 0, 1).float().div(255)
    except Exception as exc:                               # noqa: BLE001
        return jsonify({"error": "image illisible",
                        "detail": f"{type(exc).__name__}: {exc}"}), 400

    with torch.no_grad():
        logit = RESEAU(((x - MOYENNE) / ECART).unsqueeze(0)).item()
    proba = 1 / (1 + math.exp(-(logit + META["correction_logit"])))

    return jsonify({
        "probabilite_maligne": round(proba, 6),
        "seuil": SEUIL,
        "decision": "a_examiner" if proba >= SEUIL else "surveillance",
        "version_modele": META["version"],
        "rappel_cible": META["rappel_cible"],
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
