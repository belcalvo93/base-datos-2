#!/usr/bin/env bash
# backup_foodstore.sh — Respaldo lógico de foodstore en formato custom (TP Unidad 6)
# Genera dos archivos con el mismo sello de fecha: <base>_AAAAMMDD_HHMMSS.dump (respaldo)
# y <base>_AAAAMMDD_HHMMSS.conteo (filas por tabla, referencia para validar la restauracion).
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf
# Uso: ./backup_foodstore.sh   (desde cualquier carpeta)

set -u -o pipefail

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
CONTEO="$BACKUP_DIR/${DB_NAME}_${FECHA}.conteo"
ERR_TMP="$LOG_DIR/.pg_dump_error.tmp"

SQL_CONTEO="SELECT 'categoria' AS tabla, COUNT(*) AS filas FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;"

# Paso 1: conteo de filas por tabla ANTES del respaldo (SPEC U6: es la referencia
# para validar la restauracion). -X sin .psqlrc | -A -t -F' ' formato "tabla filas"
# | -w nunca pide contrasena | tr -d '\r' quita el CR de Windows para poder comparar.
if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -X -A -t -F' ' -w -c "$SQL_CONTEO" 2> "$ERR_TMP" \
        | tr -d '\r' > "$CONTEO" && [ -s "$CONTEO" ]; then
    rm -f "$ERR_TMP"
else
    CODIGO=$?
    MENSAJE="$(tr '\n' ' ' < "$ERR_TMP" 2>/dev/null)"
    rm -f "$CONTEO" "$ERR_TMP"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | base=$DB_NAME | paso=conteo | codigo=$CODIGO | detalle=$MENSAJE" >> "$LOG"
    echo "ERROR: no se pudo obtener el conteo de filas (codigo $CODIGO). No se genero respaldo. Ver $LOG" >&2
    exit 1
fi

INICIO=$(date +%s)

# Paso 2: respaldo en formato custom (-Fc para pg_restore) | -w = nunca pedir contraseña
# (falla si no está en pgpass, en lugar de quedarse esperando en una tarea programada)
if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -Fc -w -f "$ARCHIVO" 2> "$ERR_TMP"; then
    FIN=$(date +%s)
    TAMANO=$(stat -c %s "$ARCHIVO")
    echo "$(date '+%Y-%m-%d %H:%M:%S') | OK | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | bytes=$TAMANO | conteo=$(basename "$CONTEO") | segundos=$((FIN - INICIO))" >> "$LOG"
    rm -f "$ERR_TMP"
    echo "Respaldo OK: $ARCHIVO ($TAMANO bytes)"
    echo "Conteo de referencia: $CONTEO"
    exit 0
else
    CODIGO=$?
    MENSAJE="$(tr '\n' ' ' < "$ERR_TMP")"
    rm -f "$ARCHIVO" "$CONTEO" "$ERR_TMP"   # no dejar un .dump ni un .conteo sin respaldo
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | base=$DB_NAME | codigo=$CODIGO | detalle=$MENSAJE" >> "$LOG"
    echo "ERROR: pg_dump falló (código $CODIGO). Ver $LOG" >&2
    exit 1
fi
