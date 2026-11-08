#!/usr/bin/env bash
# backup_foodstore.sh — Respaldo lógico de foodstore en formato custom (TP Unidad 6)
# Genera, con el mismo sello de fecha <base>_AAAAMMDD_HHMMSS:
#   .dump    respaldo (pg_dump -Fc)
#   .conteo  huella de la base antes del respaldo (conteo_referencia.sql): referencia de la restauracion
#   .sha256  hash del .dump, para comprobar que el archivo no cambio antes de restaurarlo
#   _globals.sql roles y permisos del cluster (pg_dumpall --globals-only --no-role-passwords)
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
LOG_DIR="$DIR/logs"
LOG="$LOG_DIR/backup_foodstore.log"
mkdir -p "$LOG_DIR"

# Configuración pisable por entorno
BACKUP_DIR="${BACKUP_DIR:-$DIR/backups}"
RETENCION_DIAS="${RETENCION_DIAS:-7}"
RETENCION_MIN_JUEGOS="${RETENCION_MIN_JUEGOS:-3}"
ORIGEN="${ORIGEN:-manual}"

config_invalida() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | RETENCION | resultado=config_invalida | origen=$ORIGEN | motivo=$1" >> "$LOG"
    echo "CONFIG INVALIDA: $1. No se hizo nada." >&2
    exit 2
}

[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || config_invalida "DB_NAME='$DB_NAME' no es identificador"
[[ "$RETENCION_DIAS" =~ ^[0-9]+$ ]] && [ "$RETENCION_DIAS" -ge 1 ] || config_invalida "RETENCION_DIAS='$RETENCION_DIAS' (entero >= 1)"
[[ "$RETENCION_MIN_JUEGOS" =~ ^[0-9]+$ ]] && [ "$RETENCION_MIN_JUEGOS" -ge 1 ] || config_invalida "RETENCION_MIN_JUEGOS='$RETENCION_MIN_JUEGOS' (entero >= 1)"
case "$BACKUP_DIR" in ""|"/"|"\\") config_invalida "BACKUP_DIR='$BACKUP_DIR'" ;; esac

mkdir -p "$BACKUP_DIR" || config_invalida "no se pudo crear BACKUP_DIR=$BACKUP_DIR"
[ -d "$BACKUP_DIR" ] || config_invalida "BACKUP_DIR no es carpeta: $BACKUP_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)" || config_invalida "BACKUP_DIR inaccesible"

FECHA="$(date +%Y%m%d_%H%M%S)"
BASE="$BACKUP_DIR/${DB_NAME}_${FECHA}"
ARCHIVO="$BASE.dump"
CONTEO="$BASE.conteo"
HASH="$BASE.sha256"
GLOBALS="$BASE"'_globals.sql'
ERR_TMP="$LOG_DIR/.backup_error_${FECHA}.tmp"

# Registra FAIL, borra lo generado a medias y sale con 1
fallar() {
    local paso="$1" codigo="$2"
    local detalle; detalle="$(tr '\n\r' '  ' < "$ERR_TMP" 2>/dev/null)"
    rm -f "$ARCHIVO" "$CONTEO" "$HASH" "$GLOBALS" "$ERR_TMP"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | FAIL | base=$DB_NAME | origen=$ORIGEN | archivo=$(basename "$ARCHIVO") | paso=$paso | codigo=$codigo | detalle=$detalle" >> "$LOG"
    echo "FAIL en el paso '$paso' (codigo $codigo). No queda respaldo. Ver $LOG" >&2
    exit 1
}

# --- Retención -------------------------------------------------------------
# Borra juegos COMPLETOS con RETENCION_DIAS o más de antigüedad.
# Reglas: solo tras PASS · nunca menos de RETENCION_MIN_JUEGOS · nunca archivos sueltos.
# La edad sale del sello AAAAMMDD_HHMMSS del nombre, no del mtime.
edad_dias() {                       # $1=sello  $2=ahora(epoch) → días (puede ser <0)
    local sello="$1" ahora="$2" ep
    [[ "$sello" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]] || return 1
    ep=$(date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null) || return 1
    [ -n "$ep" ] || return 1
    echo $(( (ahora - ep) / 86400 ))
}

log_ret() {                         # $1=resultado $2=motivo $3=antes $4=despues
    local resultado="$1" motivo="$2" antes="$3" despues="$4"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | RETENCION | resultado=$resultado | origen=$ORIGEN | dias=$RETENCION_DIAS | min_juegos=$RETENCION_MIN_JUEGOS | antes=$antes | despues=$despues | motivo=$motivo | eliminados=${5:-ninguno} | quedan=${6:-ninguno} | ignorados=${7:-ninguno}" >> "$LOG"
}

retener() {
    local ahora sello edad antes despues rc=0
    local -a dumps=() juegos=() orden=()
    local eliminados="" quedan="" ignorados="" n_borr=0

    ahora=$(date +%s)

    # 1) Inventario: nombre exacto + juego completo (.dump con tamaño, .conteo, .sha256)
    shopt -s nullglob
    dumps=("$BACKUP_DIR/${DB_NAME}_"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].dump)
    shopt -u nullglob

    local f
    for f in "${dumps[@]}"; do
        sello="${f##*/}"; sello="${sello%.dump}"; sello="${sello#"${DB_NAME}_"}"
        if [ -s "$f" ] \
           && [ -f "$BACKUP_DIR/${DB_NAME}_${sello}.conteo" ] \
           && [ -f "$BACKUP_DIR/${DB_NAME}_${sello}.sha256" ]; then
            juegos+=("$sello")
        else
            ignorados="${ignorados}${sello}:incompleto;"      # se informa, no se borra
        fi
    done

    antes=${#juegos[@]}
    if [ "$antes" -eq 0 ]; then
        log_ret "omitida" "sin_juegos_completos" 0 0 "" "" "$ignorados"
        return 0
    fi

    # 2) Orden: más nuevo primero (el sello de ancho fijo ordena lexicográficamente)
    while IFS= read -r sello; do orden+=("$sello"); done \
        < <(printf '%s\n' "${juegos[@]}" | sort -r)

    # 3) Plan completo; recién después se borra
    local i ruta ext
    for i in "${!orden[@]}"; do
        sello="${orden[$i]}"
        if [ "$i" -lt "$RETENCION_MIN_JUEGOS" ] || [ "$sello" = "$FECHA" ]; then
            quedan="${quedan}${sello};"; continue          # piso de juegos + el de esta corrida
        fi
        if ! edad=$(edad_dias "$sello" "$ahora"); then
            ignorados="${ignorados}${sello}:sello_ilegible;"; quedan="${quedan}${sello};"; continue
        fi
        [ "$edad" -lt "$RETENCION_DIAS" ] && { quedan="${quedan}${sello};"; continue; }

        # 4) Borrado archivo por archivo, ruta construida y verificada; el .dump va último
        local ok=0
        for ext in conteo sha256; do
            ruta="$BACKUP_DIR/${DB_NAME}_${sello}.${ext}"
            if [ -f "$ruta" ]; then rm -f -- "$ruta" || ok=1; fi
        done
        ruta="$BACKUP_DIR/${DB_NAME}_${sello}_globals.sql"
        if [ -f "$ruta" ]; then rm -f -- "$ruta" || ok=1; fi
        # El .dump solo se borra si los borrados anteriores del mismo juego salieron bien
        if [ "$ok" -eq 0 ]; then
            ruta="$BACKUP_DIR/${DB_NAME}_${sello}.dump"
            if [ -f "$ruta" ]; then rm -f -- "$ruta" || ok=1; fi
        fi

        if [ "$ok" -eq 0 ] && [ ! -e "$BACKUP_DIR/${DB_NAME}_${sello}.dump" ]; then
            eliminados="${eliminados}${sello};"; n_borr=$((n_borr + 1))
        else
            ignorados="${ignorados}${sello}:no_se_pudo_borrar;"; quedan="${quedan}${sello};"; rc=1
        fi
    done

    despues=$(( antes - n_borr ))
    if [ "$rc" -eq 0 ]; then
        log_ret "ok" "juegos_borrados=$n_borr" "$antes" "$despues" "$eliminados" "$quedan" "$ignorados"
    else
        log_ret "error" "borrado_parcial" "$antes" "$despues" "$eliminados" "$quedan" "$ignorados"
    fi
    return "$rc"
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

# Paso 4: roles y permisos del cluster (pg_dumpall se conecta a la base
# "postgres", NO a $DB_NAME; --globals-only vuelca CREATE ROLE, pertenencias,
# ALTER ROLE ... SET y tablespaces. Sin --no-role-passwords filtraría hashes.)
pg_dumpall "${CONN[@]}" --globals-only --no-role-passwords > "$GLOBALS" 2> "$ERR_TMP" \
    || fallar pg_dumpall $?
[ -s "$GLOBALS" ] || fallar globals_vacio 1
grep -q '^CREATE ROLE' "$GLOBALS" || fallar globals_sin_roles 1
grep -q 'SCRAM-SHA-256' "$GLOBALS" && fallar globals_con_hash 1

# Paso 5: tamaño y SHA256 del .dump
TAMANO=$(stat -c %s "$ARCHIVO")
SHA=$(sha256sum "$ARCHIVO" | cut -d' ' -f1)
( cd "$BACKUP_DIR" && sha256sum "$(basename "$ARCHIVO")" ) > "$HASH"

rm -f "$ERR_TMP"
echo "$(date '+%Y-%m-%d %H:%M:%S') | PASS | base=$DB_NAME | origen=$ORIGEN | archivo=$(basename "$ARCHIVO") | bytes=$TAMANO | sha256=$SHA | objetos_toc=$TOC | conteo=$(basename "$CONTEO") | globals=$(basename "$GLOBALS") | segundos=$((FIN - INICIO))" >> "$LOG"
echo "PASS: $(basename "$ARCHIVO") ($TAMANO bytes, $TOC objetos en el TOC)"
echo "SHA256: $SHA"
echo "Huella de referencia:"
sed 's/^/  /' "$CONTEO"

# Limpieza solo después de un PASS
retener || { echo "ADVERTENCIA: la retención falló (ver $LOG)" >&2; exit 1; }
exit 0
