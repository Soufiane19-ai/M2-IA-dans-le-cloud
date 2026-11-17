# Base de S1 : Wolfi (glibc), zero CVE connue au 16/11/2026 (le digest du 23/10 portait CVE-2026-84243, glibc), figee par digest.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:2c12da5496e21e99003b3db3b9246f025e53d533c4df334205391260f1e8f85b

RUN apk add --no-cache python-3.12

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_PATH=/app/model/modele.onnx \
    PORT=8000

# Les dependances d'abord, le code ensuite : l'ordre de la seance 1 tient toujours.
COPY requirements.txt ./
RUN apk add --no-cache py3.12-pip \
    && pip install --no-cache-dir -r requirements.txt \
    && apk del --no-cache py3.12-pip

# Le modele est un artefact, pas du code : il a sa propre couche.
COPY model/ ./model/
COPY app.py ./

# Pas de chown -R (question 4.5).
RUN adduser -D -u 10001 appuser

USER appuser

EXPOSE 8000

CMD ["sh", "-c", "gunicorn -b 0.0.0.0:${PORT} app:app"]
