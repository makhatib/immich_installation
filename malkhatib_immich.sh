#!/bin/bash

echo ""
echo "Welcome to the Immich Easy Installer!"
echo "Malkhatib Youtube Channel"
echo "https://www.youtube.com/@malkhatib"
echo ""

#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- helper ----------
need() { command -v "$1" &>/dev/null ||
           { echo "!! $1 is required but missing"; exit 1; }; }
for bin in docker realpath; do need "$bin"; done
SUDO=''; ((EUID)) && SUDO='sudo'

echo -e "\nWelcome to the Immich Easy Installer!"
echo   "Malkhatib Youtube Channel  –  https://www.youtube.com/@malkhatib"
echo

# ---------- 1. Upload location ----------
read -rp "Enter directory name or full path for uploads [uploads]: " UPLOAD_DIR
UPLOAD_DIR="${UPLOAD_DIR:-uploads}"
UPLOAD_DIR_ABS="$(realpath -m "$UPLOAD_DIR")"

# ---------- 2. DB directory ----------
DB_DIR="db"
DB_DIR_ABS="$(realpath -m "$DB_DIR")"

mkdir -p "$UPLOAD_DIR_ABS" "$DB_DIR_ABS"

# ---------- 3. Fix DB permissions ----------
echo "Fixing database directory permissions (needed for Postgres)…"
$SUDO chown -R 999:999 "$DB_DIR_ABS"
$SUDO chmod 700 "$DB_DIR_ABS"

# ---------- 4. User config ----------
read -rp "Enter database username [postgres]: "   DB_USERNAME
DB_USERNAME="${DB_USERNAME:-postgres}"

read -rp "Enter database name [immich]: "         DB_DATABASE_NAME
DB_DATABASE_NAME="${DB_DATABASE_NAME:-immich}"

while :; do
  read -rsp "Enter the database password (no spaces): " DB_PASSWORD; echo
  [[ "$DB_PASSWORD" =~ \  ]] || [[ -z "$DB_PASSWORD" ]] && \
     { echo "Password may not contain spaces."; continue; }
  break
done

read -rp "Enter the Immich version (e.g. v1.71.0) or leave blank for 'release': " IMMICH_VERSION
IMMICH_VERSION="${IMMICH_VERSION:-release}"

read -rp "Enter timezone (e.g. Etc/UTC, Europe/Berlin) [Etc/GMT+3]: " TZ
TZ="${TZ:-Etc/GMT+3}"

read -rp "Enter the web server port to expose [2283]: " WEB_PORT
WEB_PORT="${WEB_PORT:-2283}"

# ---------- 5. Prepare ENV ----------
[[ "$UPLOAD_DIR" = /* ]] && ENV_UPLOAD="$UPLOAD_DIR_ABS" || ENV_UPLOAD="./$UPLOAD_DIR"

cat > .env <<EOF
UPLOAD_LOCATION=$ENV_UPLOAD
DB_DATA_LOCATION=./db
TZ=$TZ
IMMICH_VERSION=$IMMICH_VERSION
DB_PASSWORD=$DB_PASSWORD
DB_USERNAME=$DB_USERNAME
DB_DATABASE_NAME=$DB_DATABASE_NAME
EOF

# ---------- 6. docker-compose ----------
cat > docker-compose.yml <<'EOF'
services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=${TZ}
    env_file: .env
    ports:
      - '${WEB_PORT}:2283'
    depends_on:
      - redis
      - database
    restart: unless-stopped
    networks: [immich_network]

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache
    environment:
      - TZ=${TZ}
    env_file: .env
    restart: unless-stopped
    networks: [immich_network]

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:8-bookworm
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli ping || exit 1"]
    restart: unless-stopped
    networks: [immich_network]

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    restart: unless-stopped
    networks: [immich_network]

volumes:
  model-cache:

networks:
  immich_network:
EOF

# ---------- 7. Final message ----------
IP_ADDR=$(hostname -I | awk '{print $1}') || IP_ADDR=localhost
echo -e "\nSetup complete!\n"
echo "Start Immich with:"
echo "  docker compose up -d"
echo
echo "Open   http://${IP_ADDR:-localhost}:${WEB_PORT}   in your browser."
echo
echo "Uploads directory: $UPLOAD_DIR_ABS"
echo "Database files    : $DB_DIR_ABS"
echo
echo "To remove everything (including volumes):"
echo "  docker compose down -v"
echo
