# Image de base légère, version figée : jamais latest, pour une construction reproductible.
FROM python:3.12.7-slim-bookworm

# Répertoire de travail absolu, créé s'il n'existe pas.
WORKDIR /app

# Pas de .pyc, logs non tamponnés (sinon docker logs reste muet), port par défaut.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Ce qui change le moins souvent en premier : la liste des dépendances seule.
COPY requirements.txt ./

# Installation des dépendances, sans embarquer le cache de pip dans la couche.
RUN pip install --no-cache-dir -r requirements.txt

# Le code applicatif, qui change à chaque modification, copié le plus tard possible.
COPY app.py ./

# Utilisateur non privilégié (uid > 10000) propriétaire du répertoire de travail.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app

# Le processus final ne tourne pas en root.
USER 10001

# Déclaratif : seul -p au lancement publie réellement le port.
EXPOSE 8000

# Forme exec : le processus Python est le PID 1 et reçoit SIGTERM à l'arrêt.
CMD ["python", "app.py"]
