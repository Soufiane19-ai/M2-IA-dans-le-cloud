# Seance 2 : le Dockerfile de la seance 1, etendu (dependances ML, modele, gunicorn).
# Image de base identique a la seance 1 : meme Python (3.12.7) que l'environnement d'entrainement.
FROM python:3.12.7-slim-bookworm

WORKDIR /app

# Pas de .pyc, logs non tamponnes, port et chemin du modele par defaut (contrat d'interface).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    MODEL_PATH=model/modele.joblib

# Les dependances d'abord, le code ensuite : l'ordre de la seance 1 tient toujours.
# Versions epinglees = celles qui ont entraine le modele (champ "versions" du paquet).
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Le modele est un artefact, pas du code : il a sa propre ligne.
COPY model/modele.joblib ./model/
COPY app.py ./

# Utilisateur non privilegie, comme en seance 1.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app
USER 10001

EXPOSE 8000

# gunicorn (serveur de production) au lieu du serveur de developpement Flask.
# sh -c pour lire $PORT, et exec pour que gunicorn reste le PID 1 et recoive SIGTERM.
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --access-logfile - app:app"]
