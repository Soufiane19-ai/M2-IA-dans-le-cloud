"""Scenario de charge DermaScan, seance 4 : celui de la seance 3, seule la prediction change.

Lancement : IMAGE_CONTROLE_S4=ISIC_xxx.jpg locust -f locustfile_s4.py --host "$APP_URL" ...
"""
import os
from pathlib import Path

from locust import HttpUser, between, task

# L'image de controle (meta["controle"]["isic_id"]), lue UNE fois au chargement du module.
IMAGE = Path(os.environ["IMAGE_CONTROLE_S4"]).read_bytes()


class Dermatologue(HttpUser):
    # Identique a S3 : comparer a usage egal.
    wait_time = between(1, 3)

    def on_start(self):
        # Comme en S3 : sur le reseau de l'ecole, ouvrir une connexion TLS coutait ~19 s.
        # On la paie une fois par utilisateur, sous un nom a part, hors statistiques de /predict.
        self.client.get("/health", name="0. ouverture connexion TLS")

    @task(8)
    def predire(self):
        with self.client.post(
            "/predict",
            files={"image": ("controle.jpg", IMAGE, "image/jpeg")},
            name="POST /predict",
            catch_response=True,
        ) as reponse:
            if reponse.status_code == 200:
                reponse.success()
            else:
                reponse.failure(f"statut {reponse.status_code}")

    @task(1)
    def sante(self):
        self.client.get("/health", name="GET /health")

    @task(1)
    def carte_modele(self):
        self.client.get("/model/info", name="GET /model/info")
