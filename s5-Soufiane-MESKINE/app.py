"""Seance 5 — API d'inference servie par ONNX Runtime, instrumentee pour la surveillance.

Fichier distribue en debut de seance : lisez-le avant de le lancer. Meme port, memes endpoints, memes variables et meme reponse qu'en S4.
Deux changements seulement :
  1. le modele est un fichier ONNX execute par onnxruntime : plus de torch dans l'image ;
  2. chaque appel a /predict ecrit sur stdout UNE ligne JSON au format de journal de S3,
     avec les covariables recues en champs de formulaire facultatifs, a cote de l'image.
"""
import hashlib
import json
import math
import os
import socket
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import onnxruntime as ort
from flask import Flask, jsonify, request
from PIL import Image

CHEMIN_MODELE = os.environ.get("MODEL_PATH", "model/modele.onnx")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "isic-vignettes-api")
PORT = int(os.environ.get("PORT", "8000"))
STARTED_AT = time.time()
SCHEMA = "2.0"   # 1.0 = JSON tabulaire de S2 ; 2.0 = image multipart + covariables facultatives

# Domaines admis des covariables, ceux de train-metadata.csv. Tout le reste est refuse (400).
SEXES = {"male", "female"}
SITES = {"anterior torso", "posterior torso", "lower extremity", "upper extremity", "head/neck"}
ECLAIRAGES = {"3D: white", "3D: XP"}

app = Flask(__name__)

try:
    META = json.loads(Path(CHEMIN_MODELE).with_name("modele_meta.json").read_text())
    OPTIONS = ort.SessionOptions()
    # Un fil par defaut, reglable par ORT_THREADS (question 4.7).
    OPTIONS.intra_op_num_threads = int(os.environ.get("ORT_THREADS", "1"))
    SESSION = ort.InferenceSession(CHEMIN_MODELE, OPTIONS, providers=["CPUExecutionProvider"])
    ENTREE = SESSION.get_inputs()[0].name
    SHA256_SERVI = hashlib.sha256(Path(CHEMIN_MODELE).read_bytes()).hexdigest()
    SEUIL = float(os.environ.get("SEUIL", META["seuil"]))
    MOYENNE = np.array(META["normalisation"]["moyenne"], dtype=np.float32).reshape(3, 1, 1)
    ECART = np.array(META["normalisation"]["ecart_type"], dtype=np.float32).reshape(3, 1, 1)
    ERREUR_CHARGEMENT = None
except Exception as exc:                                   # noqa: BLE001
    META = SESSION = SEUIL = None
    ERREUR_CHARGEMENT = f"{type(exc).__name__}: {exc}"


def pseudonymiser(patient_id):
    """Transformation de S3 : sha256(sel:id), 16 caracteres. Sans sel, rien n'est journalise."""
    sel = os.environ.get("INFERENCE_LOG_SALT")
    if not patient_id or not sel:
        return None
    return hashlib.sha256(f"{sel}:{patient_id}".encode("utf-8")).hexdigest()[:16]


def covariables(formulaire):
    """Champs facultatifs -> bloc 'covariables' de S3. Leve ValueError si une valeur est hors domaine."""
    age = formulaire.get("age_approx")
    if age:
        age = float(age)                                   # ValueError si ce n'est pas un nombre
        if not 0 <= age <= 120:
            raise ValueError("age_approx hors de [0, 120]")
        age = f"{int(age // 10) * 10}-{int(age // 10) * 10 + 9}"   # tranche de 10 ans, jamais l'age brut
    bloc = {"age_tranche": age or None}
    for champ, domaine in (("sex", SEXES), ("anatom_site_general", SITES), ("tbp_tile_type", ECLAIRAGES)):
        valeur = formulaire.get(champ) or None
        if valeur is not None and valeur not in domaine:
            raise ValueError(f"{champ} inconnu : {valeur!r}")
        bloc[champ] = valeur
    return bloc


def journaliser(statut, cov=None, proba=None, decision=None, duree_ms=None):
    """Une ligne JSON par inference sur stdout : App Service la range dans AppServiceConsoleLogs."""
    print(json.dumps({
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "request_id": request.headers.get("X-Request-Id") or str(uuid.uuid4()),
        "model_version": META["version"] if META else None,
        "image_digest": os.environ.get("IMAGE_DIGEST"),
        "patient_ref": pseudonymiser(request.headers.get("X-Patient-Ref")),
        "probabilite_maligne": proba,
        "seuil_applique": SEUIL,
        "rappel_cible": META["rappel_cible"] if META else None,
        "decision": decision,
        "covariables": cov,
        "inference_ms": duree_ms,
        "http_status": statut,
        "input_schema_version": SCHEMA,
        "env": os.environ.get("ENVIRONMENT"),
    }, ensure_ascii=False), flush=True)


@app.get("/health")
def health():
    pret = SESSION is not None
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
    if SESSION is None:
        return jsonify({"error": "modele non charge"}), 503
    return jsonify({
        "version": META["version"],
        "version_deployee": os.environ.get("MODEL_VERSION"),
        "format": "onnx",
        "fichier_servi": Path(CHEMIN_MODELE).name,
        "sha256_fichier_servi": SHA256_SERVI,
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
        "covariables_acceptees": ["age_approx", "sex", "anatom_site_general", "tbp_tile_type"],
    })


@app.post("/predict")
def predict():
    if SESSION is None:
        return jsonify({"error": "modele non charge"}), 503

    fichier = request.files.get("image")
    if fichier is None:
        journaliser(400)
        return jsonify({"error": "champ multipart 'image' attendu",
                        "exemple": "curl -F image=@ISIC_xxx.jpg -F tbp_tile_type='3D: XP' .../predict"}), 400
    try:
        cov = covariables(request.form)
    except ValueError as exc:
        journaliser(400)
        return jsonify({"error": "covariable invalide", "detail": str(exc)}), 400
    try:
        # Les trois lignes de donnees.lire_vignette (S4), a l'identique.
        t = META["taille_entree"]
        im = Image.open(fichier.stream).convert("RGB").resize((t, t), Image.BILINEAR)
        x = np.array(im, dtype=np.uint8).transpose(2, 0, 1).astype(np.float32) / 255
    except Exception as exc:                               # noqa: BLE001
        journaliser(400, cov)
        return jsonify({"error": "image illisible",
                        "detail": f"{type(exc).__name__}: {exc}"}), 400

    t0 = time.perf_counter()
    logit = float(SESSION.run(None, {ENTREE: ((x - MOYENNE) / ECART)[None]})[0][0, 0])
    duree_ms = round((time.perf_counter() - t0) * 1000, 1)
    # Correction de prior de S4 : retour a la prevalence reelle.
    proba = 1 / (1 + math.exp(-(logit + META["correction_logit"])))
    decision = "a_examiner" if proba >= SEUIL else "surveillance"
    journaliser(200, cov, round(proba, 6), decision, duree_ms)

    return jsonify({
        "probabilite_maligne": round(proba, 6),
        "seuil": SEUIL,
        "decision": decision,
        "version_modele": META["version"],
        "rappel_cible": META["rappel_cible"],
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
