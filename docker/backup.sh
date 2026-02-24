#!/usr/bin/env bash
set -euo pipefail

TS=$(date +%F_%H%M%S)
mkdir -p ./backups

docker exec summit-db pg_dump -U "${POSTGRES_USER:-summit}" "${POSTGRES_DB:-summit_trace}" \
  > "./backups/summit_trace_${TS}.sql"

echo "Backup written to ./backups/summit_trace_${TS}.sql"