#!/bin/bash
set -euo pipefail

set -a
source environment.properties
set +a

echo "Removing existing containers..."
docker ps -aq | xargs -r docker stop | xargs -r docker rm
echo "Removing existing network connection..."
docker network rm incidenthub-net 2>/dev/null || true

echo "Creating network connection..."
docker network create incidenthub-net
echo "Creating Postgres Container"
docker run -d --name postgres_container \
  --network incidenthub-net \
  --env-file environment.properties \
  -p 5432:5432 \
  postgres:16

until docker exec -i postgres_container pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  echo "Waiting for Postgres..."
  sleep 1
done

echo "Running sql scripts"
for file in scripts/sql/run_as_admin/*.sql; do
  echo "Running $file"
  docker exec -i postgres_container psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$file"
done

echo "Created Postgres Container"
