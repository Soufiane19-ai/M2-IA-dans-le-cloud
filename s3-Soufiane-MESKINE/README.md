# Séance 3 — Déploiement managé (Soufiane Meskine)

Master 2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027. TP réalisé le 26/10/2026 sur Azure for Students, cible **A — App Service for Containers** (plan Linux B1, France Central).

L'API d'inférence de la séance 2 (`acrdermascansm26.azurecr.io/dermascan-api:1.0.0`, digest `sha256:cae2b635…006b`) a été servie sur `https://app-dermascan-sm26.azurewebsites.net`, tirée du registre par **identité managée** (rôle `AcrPull`, aucun mot de passe), configurée par réglages d'application (seuil S2 `0.34747330294391954`), cassée puis réparée à partir des logs, puis chargée par Locust. Toutes les ressources de la séance ont été détruites ensuite ; seul le registre est conservé.

| Fichier | Contenu |
|---|---|
| `FAISABILITE.md` | Mesures 1-2, questions 0.1 à 1.2 |
| `DEPLOIEMENT.md` | Mesures 3-8 et 16-17, questions 2.1 à 3.4 et 7.1 (seuil S2 et seuil abaissé 0.0347) |
| `JOURNAL_INCIDENT.md` | Mesures 9-12, questions 4.1-4.2, compte rendu de la panne `WEBSITES_PORT=9999` |
| `RAPPORT_CHARGE.md` | Mesures 13-15, critère de rupture, questions 5.1 à 5.5 |
| `JOURNALISATION_INFERENCES.md` | Grille 6.1, format JSON 6.2, pseudonymisation, durées 6.3, questions 6.1 à 6.6 |
| `locustfile.py` | Scénario Locust (poids 8/1/1, réflexion 1-3 s, 4 variables perturbées) |
| `palier[1-4]_stats.csv`, `palier[1-4].html` | Sorties brutes de Locust (avec `*_failures.csv` et `*_stats_history.csv`) |
| `charge.json` | Charge utile réelle de S2 (40 variables) utilisée pour tous les appels |
| `captures/` | `/health` public en 200, `/predict` avec `decision` et `seuil`, réponses au seuil abaissé, page 503 avant droits, lignes de log des deux incidents, rapports Locust en image |
| `logs/` | Archive des logs App Service (`logs_s3.zip`, adresse IP publique du poste remplacée par `[IP-client-masquee]`), diagnostic réseau (`diag_s3.log`), mesure 14, nettoyage |
| `scripts/` | Scripts PowerShell qui ont exécuté la séance, et `charge_seuil.json` (seconde lésion réelle, utilisée pour montrer le basculement de décision) |

Fait marquant de la séance : chaque nouvelle connexion HTTPS depuis le réseau de l'école mettait ≈ 19 s à s'établir (poignée de main TLS), alors que le service répondait en 25 à 80 ms. Le diagnostic, et la façon dont il a été isolé de la mesure de charge, sont détaillés dans `DEPLOIEMENT.md` (question 2.4) et `RAPPORT_CHARGE.md`.

Aucun secret n'est versionné : le sel `INFERENCE_LOG_SALT` a été généré au moment de l'exécution, n'a jamais été écrit dans un fichier et a disparu avec l'application.
