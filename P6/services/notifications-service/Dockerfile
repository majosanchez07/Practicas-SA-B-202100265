# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────
# Etapa 1: dependencias
# Se instalan solo las de produccion y en una etapa aparte, de modo que el
# cache de npm y los archivos intermedios no lleguen a la imagen final.
# ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund || npm install --omit=dev --no-audit --no-fund

# ─────────────────────────────────────────────────────────────
# Etapa 2: imagen final
# Parte de alpine limpio y solo recibe node_modules ya resuelto y el codigo.
# ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

# dumb-init reencamina las señales: sin el, node corre como PID 1 y no recibe
# SIGTERM, por lo que Kubernetes tendria que matar el pod a la fuerza en cada
# rolling update, provocando la caida de servicio que el enunciado prohibe.
RUN apk add --no-cache dumb-init

ENV NODE_ENV=production     PORT=8003

WORKDIR /app

# Usuario sin privilegios: la imagen debe poder correr con
# runAsNonRoot: true y readOnlyRootFilesystem: true.
# node:alpine ya trae el usuario "node" (uid 1000).
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node src ./src

USER node

EXPOSE 8003

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]
