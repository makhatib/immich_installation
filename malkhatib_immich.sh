#!/usr/bin/env bash
# Immich Easy-Installer
set -Eeuo pipefail

# ─────────────────── prerequisites ───────────────────
need() { command -v "$1" &>/dev/null ||
           { echo "!! $1 is required but not installed"; exit 1; }; }
for bin in docker realpath ip; do need "$bin"; done
docker compose version &>/dev/null || { echo "!! docker compose not found"; exit 1; }

SUDO=''; ((EUID)) && SUDO='sudo'      # elevate only when needed

# -------- helper: detect primary host IP (non-Docker) --------
get_host_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

# ───────────────────── banner ─────────────────────
echo -e "\nWelcome to the Immich Easy Installer!"
echo   "Malkhatib YouTube Channel  —  https://www.youtube.com/@malkhatib"
echo

# ────────────── 1) upload directory ──────────────
read -rp "Enter directory name or full path for uploads [uploads]: " UPLOAD_DIR
UPLOAD_DIR="${UPLOAD_DIR:-uploads}"
UPLOAD_DIR_ABS="$(realpath -m "$UPLOAD_DIR")"

# ────────────── 2) postgres directory ─────────────
DB_DIR="db"
DB_DIR_ABS="$(realpath -m "$DB_DIR")"

mkdir -p "$UPLOAD_DIR_ABS" "$DB_DIR_ABS"

echo "Fixing permissions on database directory (UID 999 = postgres)…"
$SUDO chown -R 999:999 "$DB_DIR_ABS"
$SUDO chmod 700 "$DB_DIR_ABS"

# ────────────── 3) user questions  ───────────────
read -rp "Database username   [postgres]: " DB_USERNAME
DB_USERNAME="${DB_USERNAME:-postgres}"

read -rp "Database name       [immich]   : " DB_DATABASE_NAME
DB_DATABASE_NAME="${DB_DATABASE_NAME:-immich}"

while :; do
  read -rsp "Database password  (no spaces): " DB_PASSWORD; echo
  [[ "$DB_PASSWORD" =~ \  ]] && { echo "Password may not contain spaces."; continue; }
  [[ -n "$DB_PASSWORD"    ]] || { echo "Password may not be empty.";    continue; }
  break
done

read -rp "Immich version (e.g. v1.74.0) or blank for 'release': " IMMICH_VERSION
IMMICH_VERSION="${IMMICH_VERSION:-release}"

read -rp "Timezone (e.g. Etc/UTC, Europe/Berlin) [Etc/GMT+3]: " TZ
TZ="${TZ:-Etc/GMT+3}"

read -rp "Host port to expose Immich on [2283]: " WEB_PORT
WEB_PORT="${WEB_PORT:-2283}"

# ────────────── 4) write .env file ───────────────
[[ "$UPLOAD_DIR" = /* ]] && ENV_UPLOAD="$UPLOAD_DIR_ABS" || ENV_UPLOAD="./$UPLOAD_DIR"

cat > .env <<EOF
UPLOAD_LOCATION=$ENV_UPLOAD
DB_DATA_LOCATION=./db
TZ=$TZ
IMMICH_VERSION=$IMMICH_VERSION
DB_PASSWORD=$DB_PASSWORD
DB_USERNAME=$DB_USERNAME
DB_DATABASE_NAME=$DB_DATABASE_NAME
WEB_PORT=$WEB_PORT
EOF

# ───────────── 5) docker-compose.yml ─────────────
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

# ───────────── 6) start the stack ───────────────
echo -e "\nPulling images and starting Immich … (this can take a while)"
docker compose pull
docker compose up -d
sleep 2   # let Docker register the containers

# ───────────── 7) determine mapped port ─────────
mapped=$(docker compose port immich-server 2283 2>/dev/null || true)
if [[ -n "$mapped" ]]; then
    HOST_PORT=${mapped##*:}
else
    HOST_PORT=$WEB_PORT
fi

# ───────────── 8) final message ────────────────
IP_ADDR=$(get_host_ip)
[[ -z "$IP_ADDR" ]] && IP_ADDR="localhost"

echo -e "\n────────────────── Immich is starting ──────────────────"
echo "Open the following URL in your browser once the health-checks are green:"
echo "    http://${IP_ADDR}:${HOST_PORT}"
echo
echo "Uploads directory : $UPLOAD_DIR_ABS"
echo "Database files    : $DB_DIR_ABS"
echo
echo "Follow logs with  : docker compose logs -f immich-server"
echo "Stop stack        : docker compose down"
echo "Remove + volumes  : docker compose down -v"
echo "──────────────────────────────────────────────────────────"
