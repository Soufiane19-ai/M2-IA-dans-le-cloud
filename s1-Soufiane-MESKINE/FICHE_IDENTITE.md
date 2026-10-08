# Fiche d'identité du conteneur — dermascan-health

| # | Rubrique | Valeur |
|---|---|---|
| 1 | Nom de l'artefact et tag | `dermascan-health:0.1.0` (nom complet : `acrdermascansm26.azurecr.io/dermascan-health:0.1.0`) |
| 2 | Digest `sha256` | `sha256:df2fa4f619a350750c79527799f376b795d67ad0e9e5f33cb96cb45698d98451` (index d'image ; manifeste amd64 : `sha256:f7cea7eaad9308d4ede1c512811bc62d4d0d75a4a2c04abb969e0fce6e2a098c`) |
| 3 | Image de base, avec son tag exact | `python:3.12.7-slim-bookworm@sha256:60d9996b6a8a3689d36db740b49f4327be3be09a21122bd02fb8895abb38b50d` (Debian GNU/Linux 12 « bookworm », variante slim) |
| 4 | Version de Python embarquée | `Python 3.12.7` |
| 5 | Dépendances directes et leurs versions | `Flask==3.0.3` (`requirements.txt`) |
| 6 | Dépendances transitives | `blinker==1.9.0`, `click==8.5.0`, `itsdangerous==2.2.0`, `Jinja2==3.1.6`, `MarkupSafe==3.0.4`, `Werkzeug==3.1.9` : 6 paquets en plus de Flask (`pip freeze`) |
| 7 | Licences identifiées et obligations associées | Flask et ses dépendances Pallets : BSD-3-Clause (blinker : MIT), qui impose de conserver la notice de copyright et la licence. CPython : licence PSF, permissive, avec conservation de la notice. Paquets système Debian : licences mixtes dont GPL-2.0/GPL-3.0 et LGPL : redistribuer l'image impose de fournir (ou d'offrir) le code source correspondant et les textes de licence. Ce sont ces dernières, copyleft, qui pèsent le plus si DermaScan livre l'image à un centre client. |
| 8 | Architecture et OS cibles | `linux/amd64` |
| 9 | Utilisateur d'exécution (uid) | `10001` (`appuser`, non root ; `Config.User = 10001`) |
| 10 | Port exposé et endpoint de santé | Port `8000` (`EXPOSE 8000`, variable `PORT`, écoute sur `0.0.0.0`) ; `GET /health` renvoie 200 et un JSON `status`, `service`, `version`, `hostname`, `uptime_seconds` |
| 11 | Producteur : nom, promotion, date et heure de construction | Soufiane Meskine, Master 2 YNOV Campus Montpellier, Industrialisation de l'IA dans le Cloud 2026-2027 ; construite le 2026-10-06 à 14:29:29 UTC (16:29 heure de Paris, champ `Created`) |
| 12 | Registre de publication : `loginServer` et dépôt | `acrdermascansm26.azurecr.io`, dépôt `dermascan-health`, tag `0.1.0` (ACR Basic, groupe `rg-dermascan-registre-sm26`, France Central) |
| 13 | Destination connue | Séance 2 : image de base de l'API d'inférence DermaScan (même Dockerfile, `requirements.txt` enrichi de scikit-learn, pandas et numpy) |
| 14 | Limites connues et risques résiduels | (1) **Aucun scan de vulnérabilités** (ni Trivy, ni Docker Scout, ni Defender for Containers) : les CVE des paquets Debian et Python sont inconnues. (2) **Serveur de développement Flask** (Werkzeug 3.1.9, qui l'annonce lui-même au démarrage : « This is a development server. Do not use it in a production deployment ») : mono-processus, non conçu pour la charge ni pour la production ; il faudra un serveur WSGI (gunicorn) derrière. (3) **Pas d'`HEALTHCHECK`** dans l'image ni de gestion de l'arrêt propre : l'orchestrateur ne détecte pas seul un processus bloqué. (4) **Base figée par tag mais vieillissante** : `python:3.12.7` date de 23 mois et ne reçoit plus les correctifs de sécurité Debian ultérieurs. (5) **Tag mutable** : `0.1.0` peut être écrasé dans le registre, seul le digest identifie le contenu de façon fiable. (6) **Image non signée** et sans SBOM ni attestation de provenance. (7) **Registre Basic exposé publiquement** sur Internet, protégé uniquement par l'authentification. |
