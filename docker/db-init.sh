#!/bin/bash
set -e

SQLCMD=$(command -v /opt/mssql-tools18/bin/sqlcmd || command -v /opt/mssql-tools/bin/sqlcmd || command -v sqlcmd || true)
if [ -z "$SQLCMD" ]; then echo "sqlcmd not found"; exit 2; fi
echo "Using sqlcmd: $SQLCMD"

# Ingen -C trust (kompatibel med v17/v18)
SQLCMD_FLAGS=""
echo "Flags: $SQLCMD_FLAGS"

# Vent på SQL (op til ~4 min)
for n in $(seq 1 120); do
  $SQLCMD $SQLCMD_FLAGS -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1 && break || true
  echo "Waiting for SQL Server (attempt $n)..." ; sleep 2
done

# Opret DB + kør scripts
$SQLCMD $SQLCMD_FLAGS -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -Q "IF DB_ID('CerealDb') IS NULL CREATE DATABASE CerealDb;"
for f in "/scripts/Create Table.sql" "/scripts/Create User Table.sql" "/scripts/Create User.sql" "/scripts/Extra Queries.sql"; do
  [ -f "$f" ] && $SQLCMD $SQLCMD_FLAGS -S tcp:db,1433 -U sa -P "$SA_PASSWORD" -d CerealDb -i "$f" || true
done

echo "db-init completed"
