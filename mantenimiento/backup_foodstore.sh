#!/usr/bin/env bash
# backup_foodstore.sh — Respaldo lógico de foodstore en formato custom (TP Unidad 6)
# Genera, con el mismo sello de fecha <base>_AAAAMMDD_HHMMSS:
#   .dump    respaldo (pg_dump -Fc)
#   .conteo  huella de la base antes del respaldo (conteo_referencia.sql): referencia de la restauracion
#   .sha256  hash del .dump, para comprobar que el archivo no cambio antes de restaurarlo
# Cada ejecución deja UNA línea en logs/backup_foodstore.log con PASS o FAIL, tamaño y SHA256.
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf
# Uso: ./backup_foodstore.sh   (desde cualquier carpeta)

set -u -o pipefail

# Parámetros de conexión (se pueden pisar con variables de entorno)
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
DB_NAME="${DB_NAME:-foodstore}"
CONN=(-h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w)

# Carpetas relativas a la ubicación del script
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$DIR/backups"
LOG_DIR="$DIR/logs"
LOG="$LOG_DIR/backup_foodstore.log"
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

FECHA="$(date +%Y%m%d_%H%M%S)"
BASE="$BACKUP_DIR/${DB_NAME}_${FECHA}"
ARCHIVO="$BASE.dump"
CONTEO="$BASE.conteo"
HASH="$BASE.sha256"
ERR_TMP="$LOG_DIR/.backup_error_${FECHA}.tmp"

# Registra FAIL, borra lo generado a medias y sale con 1
fallar() {
    local paso="$1" codigo="$2"
    local detalle; detalle="$(tr '\n\r' '  ' < "$ERR_TMP" 2>/dev/null)"
    rm -f "$ARCHIVO" "$CONTEO" "$HASH" "$ERR_TMP"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | FAIL | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | paso=$paso | codigo=$codigo | detalle=$detalle" >> "$LOG"
    echo "FAIL en el paso '$paso' (codigo $codigo). No queda respaldo. Ver $LOG" >&2
    exit 1
}

# Paso 1: huella de la base ANTES del respaldo (referencia para validar la restauración).
# -A -t -F' ' = formato "clave valor" | tr -d '\r' quita el CR de Windows.
psql "${CONN[@]}" -d "$DB_NAME" -X -A -t -F' ' -v ON_ERROR_STOP=1 -f "$DIR/conteo_referencia.sql" 2> "$ERR_TMP" \
    | tr -d '\r' > "$CONTEO" || fallar conteo $?
[ -s "$CONTEO" ] || fallar conteo_vacio 1

# Paso 2: respaldo en formato custom (-Fc, para pg_restore)
INICIO=$(date +%s)
pg_dump "${CONN[@]}" -d "$DB_NAME" -Fc -f "$ARCHIVO" 2> "$ERR_TMP" || fallar pg_dump $?
FIN=$(date +%s)

# Paso 3: verificar el archivo apenas se genera (no esperar a un incidente)
[ -s "$ARCHIVO" ] || fallar dump_vacio 1
TOC=$(pg_restore -l "$ARCHIVO" 2> "$ERR_TMP" | grep -c '^[0-9]') || fallar pg_restore_l $?
[ "$TOC" -gt 0 ] || fallar pg_restore_l_vacio 1

# Paso 4: tamaño y SHA256 del .dump
TAMANO=$(stat -c %s "$ARCHIVO")
SHA=$(sha256sum "$ARCHIVO" | cut -d' ' -f1)
( cd "$BACKUP_DIR" && sha256sum "$(basename "$ARCHIVO")" ) > "$HASH"

rm -f "$ERR_TMP"
echo "$(date '+%Y-%m-%d %H:%M:%S') | PASS | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | bytes=$TAMANO | sha256=$SHA | objetos_toc=$TOC | conteo=$(basename "$CONTEO") | segundos=$((FIN - INICIO))" >> "$LOG"
echo "PASS: $(basename "$ARCHIVO") ($TAMANO bytes, $TOC objetos en el TOC)"
echo "SHA256: $SHA"
echo "Huella de referencia:"
sed 's/^/  /' "$CONTEO"
exit 0
