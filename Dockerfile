# Container-Image für den Betrieb unter Coolify (oder jedem anderen
# Docker-Host). Gedacht für DATA_SOURCE=api: der Container spricht per HTTP
# mit dem mAirListDB Server im LAN und braucht keinen Zugriff auf die .mldb.
# Einrichtung und Umgebungsvariablen: COOLIFY.md.

# better-sqlite3 13 setzt Node >= 22 voraus
ARG NODE_VERSION=22

# --- Frontend bauen ---
FROM node:${NODE_VERSION}-bookworm-slim AS frontend
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# --- Server-Abhängigkeiten installieren ---
# Build-Tools nur als Fallback, falls better-sqlite3 kein passendes
# Prebuilt-Binary findet und aus dem Quellcode kompilieren muss.
FROM node:${NODE_VERSION}-bookworm-slim AS server-deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev

# --- Laufzeit-Image ---
FROM node:${NODE_VERSION}-bookworm-slim

# TRUST_PROXY=1: der Container läuft hinter genau einem Reverse Proxy
# (Coolifys Traefik). Sitzt ein weiterer Proxy davor, in Coolify erhöhen.
ENV NODE_ENV=production \
    PORT=8841 \
    DATA_SOURCE=api \
    WEB_AUTH_DB_PATH=/data/webinterface-auth.db \
    SETTINGS_PATH=/data/settings.json \
    TRUST_PROXY=1

WORKDIR /app/server
COPY --from=server-deps /app/server/node_modules ./node_modules
COPY server/ ./
COPY --from=frontend /app/frontend/dist ../frontend/dist

# /data als persistentes Volume einbinden (Benutzer-DB + Panel-Einstellungen),
# sonst sind beide nach jedem Redeploy weg.
RUN mkdir -p /data && chown node:node /data
USER node

EXPOSE 8841

# Per Node statt curl/wget, die das slim-Image nicht enthält
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 8841) + '/api/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "index.js"]
