#!/usr/bin/env bash
set -euo pipefail

SQLCMD=$(/usr/bin/which /opt/mssql-tools18/bin/sqlcmd || /usr/bin/which /opt/mssql-tools/bin/sqlcmd || echo "")
if [ -z "$SQLCMD" ]; then echo "sqlcmd not found"; exit 2; fi
echo "Using sqlcmd: $SQLCMD"

# Vent på SQL
for n in $(seq 1 120); do
  if $SQLCMD -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for SQL Server (attempt $n)..."; sleep 2
done

# Debug: se scripts og kør i determineret rækkefølge
echo "Scripts in /scripts:"
ls -la /scripts || true

# Opret DB
$SQLCMD -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -Q "IF DB_ID('CerealDb') IS NULL CREATE DATABASE CerealDb;"

# Kør filer hvis de findes – justér rækkefølge/filnavne til dine faktiske navne
for f in \
  "/scripts/Create Table.sql" \
  "/scripts/Create User Table.sql" \
  "/scripts/Create User.sql" \
  "/scripts/Extra Queries.sql"
do
  if [ -f "$f" ]; then
    echo "Running: $f"
    $SQLCMD -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -d CerealDb -i "$f"
  else
    echo "Skip (not found): $f"
  fi
done

# Efter-kontrol: findes Users?
$SQLCMD -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -d CerealDb -Q "SELECT name FROM sys.tables ORDER BY name"
echo "db-init completed"
