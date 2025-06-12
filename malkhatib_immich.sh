#!/bin/bash

echo ""
echo "Welcome to the Immich Easy Installer!"
echo "Malkhatib Youtube Channel"
echo "https://www.youtube.com/@malkhatib"
echo ""

# ----------- 1. Ask user for locations (either relative or absolute) -----------
read -p "Enter directory name or full path for uploads [uploads]: " UPLOAD_DIR
UPLOAD_DIR="${UPLOAD_DIR:-uploads}"

read -p "Enter directory name or full path for database [db]: " DB_DIR
DB_DIR="${DB_DIR:-db}"

# Absolute path for permission commands and user hints
UPLOAD_DIR_ABS="$(realpath -m "$UPLOAD_DIR")"
DB_DIR_ABS="$(realpath -m "$DB_DIR")"

mkdir -p "$UPLOAD_DIR_ABS"
mkdir -p "$DB_DIR_ABS"

# ----------- 2. Set up permissions on the DB directory -----------
echo "Fixing database directory permissions (needed for Postgres)..."
sudo chown -R 999:999 "$DB_DIR_ABS"
sudo chmod -R 700 "$DB_DIR_ABS"

# ----------- 3. Gather further configuration from user -----------
read -p "Enter database username [postgres]: " DB_USERNAME
DB_USERNAME="${DB_USERNAME:-postgres}"

read -p "Enter database name [immich]: " DB_DATABASE_NAME
DB_DATABASE_NAME="${DB_DATABASE_NAME:-immich}"

while true; do
    read -p "Enter the database password (alphanumeric, no spaces): " DB_PASSWORD
    if [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
        break
    else
        echo "Password must be alphanumeric only!"
    fi
done

read -p "Enter the Immich version (e.g. v1.71.0) or leave blank for 'release': " IMMICH_VERSION
IMMICH_VERSION="${IMMICH_VERSION:-release}"

read -p "Enter timezone (e.g. Etc/UTC, Europe/Berlin) [Etc/UTC]: " TZ
TZ="${TZ:-Etc/UTC}"

read -p "Enter the web server port to expose [2283]: " WEB_PORT
WEB_PORT="${WEB_PORT:-2283}"

# ----------- 4. Prepare ENV paths (absolute vs relative) -----------
if [[ "$UPLOAD_DIR" = /* ]]; then
  ENV_UPLOAD="$UPLOAD_DIR_ABS"
else
  ENV_UPLOAD="./$UPLOAD_DIR"
fi

if [[ "$DB_DIR" = /* ]]; then
  ENV_DB="$DB_DIR_ABS"
else
  ENV_DB="./$DB_DIR"
fi

# ----------- 5. Create .env file in current (parent) directory -----------
cat > .env <<EOF
UPLOAD_LOCATION=$ENV_UPLOAD
DB_DATA_LOCATION=$ENV_DB
TZ=$TZ
IMMICH_VERSION=$IMMICH_VERSION
DB_PASSWORD=$DB_PASSWORD
DB_USERNAME=$DB_USERNAME
DB_DATABASE_NAME=$DB_DATABASE_NAME
EOF

# ----------- 6. Create docker-compose.yml in current (parent) directory -----------
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:\${IMMICH_VERSION:-release}
    volumes:
      - \${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '${WEB_PORT}:2283'
    depends_on:
      - redis
      - database
    restart: always
    healthcheck:
      disable: false
    networks:
      - immich_network

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:\${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    healthcheck:
      disable: false
    networks:
      - immich_network

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:8-bookworm@sha256:ff21bc0f8194dc9c105b769aeabf9585fea6a8ed649c0781caeac5cb3c247884
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always
    networks:
      - immich_network

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0@sha256:fa4f6e0971f454cd95fec5a9aaed2ed93d8f46725cc6bc61e0698e97dba96da1
    environment:
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_USER: \${DB_USERNAME}
      POSTGRES_DB: \${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - \${DB_DATA_LOCATION}:/var/lib/postgresql/data
    restart: always
    networks:
      - immich_network

volumes:
  model-cache:

networks:
  immich_network:
EOF

# ----------- 7. Show user how to launch Immich and the access URL -----------
echo ""
echo "Setup complete!"

IP_ADDR="$(hostname -I | awk '{print $1}')"
if [[ -z "$IP_ADDR" ]]; then
    IP_ADDR="localhost"
fi

echo ""
echo "To start Immich, run:"
echo "  docker compose up -d"
echo ""
echo "Once running, open this URL in your browser:"
echo "  http://${IP_ADDR}:${WEB_PORT}"
echo ""
echo "Uploads directory:      $UPLOAD_DIR_ABS"
echo "Database files:         $DB_DIR_ABS"
echo ""
echo "If you ever want to remove everything (including all your files and database), run:"
echo "  docker compose down -v"
echo ""
