# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────
# Etapa 1: compilacion
# Aqui si hacen falta gcc y las cabeceras de libpq para construir las ruedas
# de psycopg y de las librerias de criptografia. Nada de esto llega a la
# imagen final: es exactamente lo que el Dockerfile de la Practica 4 dejaba
# dentro y lo que hacia que pesara mas de 600 MB.
# ─────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1     PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends     gcc     libpq-dev     python3-dev     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

# Las dependencias se instalan en un prefijo aislado para poder copiarlas
# enteras a la etapa final con una sola instruccion.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ─────────────────────────────────────────────────────────────
# Etapa 2: imagen final
# Solo la libreria cliente de Postgres en runtime (libpq5), sin compilador.
# ─────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends     libpq5     && rm -rf /var/lib/apt/lists/*     && apt-get clean

ENV PYTHONUNBUFFERED=1     PYTHONDONTWRITEBYTECODE=1     PORT=8001

# Usuario sin privilegios, requerido por runAsNonRoot: true.
RUN groupadd --gid 1000 appuser     && useradd --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser main.py ./
COPY --chown=appuser:appuser src ./src

USER appuser

EXPOSE 8001

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT} --log-level ${LOG_LEVEL:-info}"]
