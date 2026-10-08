"""Sonde de sante DermaScan — service HTTP minimal.

Fichier fourni pour la seance 1. Ne le modifiez pas, sauf a l'endroit
explicitement demande par l'experience de cache de la partie 3.5.
L'objet de la seance est d'emballer ce service, pas de l'ecrire.
"""

import os
import socket
import time

from flask import Flask, jsonify

# Instant de demarrage du processus : sert a calculer uptime_seconds.
STARTED_AT = time.time()

# Configuration lue dans l'environnement, avec une valeur par defaut.
# Surchargeable au lancement du conteneur, sans reconstruction de l'image.
SERVICE_NAME = os.environ.get("SERVICE_NAME", "dermascan-health")
APP_VERSION = os.environ.get("APP_VERSION", "0.1.0")
PORT = int(os.environ.get("PORT", "8000"))

app = Flask(__name__)


@app.get("/")
def accueil():
    return jsonify({"message": "DermaScan health probe",
                    "service": SERVICE_NAME,
                    "endpoints": ["/", "/health"]})


@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE_NAME,
                    "version": APP_VERSION, "hostname": socket.gethostname(),
                    "uptime_seconds": round(time.time() - STARTED_AT, 1)})


if __name__ == "__main__":
    # host="0.0.0.0" : indispensable en conteneur. Une ecoute sur 127.0.0.1
    # ne serait joignable que depuis l'interieur du conteneur lui-meme.
    app.run(host="0.0.0.0", port=PORT)
