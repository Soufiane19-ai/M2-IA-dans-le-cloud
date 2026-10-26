"""Scenario de charge DermaScan (seance 3, partie 5).

Un utilisateur type = un dermatologue qui soumet des lesions depuis son poste.
Lancement : locust -f locustfile.py --host "$APP_URL" --users N --spawn-rate R ...
"""
import json
import random
from pathlib import Path

from locust import HttpUser, between, task

# charge.json de la seance 2 (une lesion reelle, 40 variables), lu UNE fois.
CHARGE = json.loads(Path(__file__).with_name("charge.json").read_text(encoding="utf-8"))


def borner(valeur, bas, haut):
    return max(bas, min(haut, valeur))


def charge_utile_perturbee():
    """Copie de la charge, perturbee sur 4 variables numeriques dans les plages de S2.

    Plages relevees sur train-metadata.csv (1er-99e percentile) :
    age_approx 25-85 (par pas de 5, comme dans le jeu), clin_size_long_diam_mm 2,39-10,95,
    tbp_lv_areaMM2 2,14-50,2, tbp_lv_perimeterMM 6,39-35,95.
    """
    c = dict(CHARGE)
    c["age_approx"] = borner(c["age_approx"] + random.choice((-10, -5, 0, 5, 10)), 25, 85)
    f = random.uniform(0.8, 1.2)                        # meme facteur : lesion plus ou moins grande
    c["clin_size_long_diam_mm"] = round(borner(c["clin_size_long_diam_mm"] * f, 2.39, 10.95), 2)
    c["tbp_lv_areaMM2"] = borner(c["tbp_lv_areaMM2"] * f * f, 2.14, 50.2)
    c["tbp_lv_perimeterMM"] = borner(c["tbp_lv_perimeterMM"] * f, 6.39, 35.95)
    return c


class Dermatologue(HttpUser):
    # Temps de reflexion : 1 a 3 s entre deux gestes (cadence soutenue d'une seance de tri,
    # volontairement plus rapide qu'un humain pour atteindre le point de rupture).
    wait_time = between(1, 3)

    def on_start(self):
        # Sur le reseau de mesure, chaque NOUVELLE connexion TLS coute ~19 s (poignee de main
        # ralentie entre le poste et Azure, mesuree par diag_s3.ps1 ; le serveur repond en ~50 ms).
        # La session Locust garde la connexion ouverte (keep-alive) : on paie ce cout une fois
        # par utilisateur, sous un nom a part, pour ne pas polluer les statistiques de /predict.
        self.client.get("/health", name="0. ouverture connexion TLS")

    @task(8)
    def predire(self):
        with self.client.post("/predict", json=charge_utile_perturbee(),
                              name="POST /predict", catch_response=True) as reponse:
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
