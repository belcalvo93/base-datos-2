#!/usr/bin/env bash
# backup_foodstore.sh — Respaldo lógico de foodstore en formato custom (TP Unidad 6)
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf
# Uso: ./backup_foodstore.sh   (desde cualquier carpeta)

set -u

# Parámetros de conexión (se pueden pisar con variables de entorno)
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
DB_NAME="${DB_NAME:-foodstore}"

# Carpetas relativas a la ubicación del script
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$DIR/backups"
LOG_DIR="$DIR/logs"
LOG="$LOG_DIR/backup_foodstore.log"
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

FECHA="$(date +%Y%m%d_%H%M%S)"
ARCHIVO="$BACKUP_DIR/${DB_NAME}_${FECHA}.dump"
ERR_TMP="$LOG_DIR/.pg_dump_error.tmp"

INICIO=$(date +%s)

# -Fc = formato custom (para pg_restore) | -w = nunca pedir contraseña (falla si no está en pgpass)
if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -Fc -w -f "$ARCHIVO" 2> "$ERR_TMP"; then
    FIN=$(date +%s)
    TAMANO=$(stat -c %s "$ARCHIVO")
    echo "$(date '+%Y-%m-%d %H:%M:%S') | OK | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | bytes=$TAMANO | segundos=$((FIN - INICIO))" >> "$LOG"
    rm -f "$ERR_TMP"
    echo "Respaldo OK: $ARCHIVO ($TAMANO bytes)"
    exit 0
else
    CODIGO=$?
    MENSAJE="$(tr '\n' ' ' < "$ERR_TMP")"
    rm -f "$ARCHIVO" "$ERR_TMP"   # no dejar un .dump incompleto
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | base=$DB_NAME | codigo=$CODIGO | detalle=$MENSAJE" >> "$LOG"
    echo "ERROR: pg_dump falló (código $CODIGO). Ver $LOG" >&2
    exit 1
fi
