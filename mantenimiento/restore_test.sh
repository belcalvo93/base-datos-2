#!/usr/bin/env bash
# restore_test.sh — Simulacro de restauración contra reloj (TP Unidad 6)
# Restaura el ÚLTIMO respaldo de foodstore en la base DESCARTABLE foodstore_restore_test,
# valida filas, importes, estructura e integridad, y mide RTO y antigüedad del respaldo.
# La base foodstore NUNCA se toca ni se consulta: se compara contra el .conteo del respaldo.
# Antes de borrar foodstore_restore_test pide autorización escrita y la deja registrada.
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf
# Uso: ./restore_test.sh   (para correrlo sin preguntar: CONFIRMAR=foodstore_restore_test ./restore_test.sh)

set -u -o pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
# Nombre de la base de produccion: solo se usa para el guard de seguridad, nunca se conecta
ORIGEN="foodstore"
DESTINO="foodstore_restore_test"
CONN=(-h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w)

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/logs/restore_test.log"
SELLO="$(date +%Y%m%d_%H%M%S)"
EVID="$DIR/evidencias/restore_test_${SELLO}.txt"
mkdir -p "$DIR/logs" "$DIR/evidencias"
: > "$EVID"
out() { echo "$*" | tee -a "$EVID"; }
# psql en Windows devuelve fin de línea \r\n: se quita el \r para poder comparar
consulta() { psql "${CONN[@]}" -X -A -t -F' ' -v ON_ERROR_STOP=1 "$@" | tr -d '\r'; }

DUMP=""
fallar() {
    out "RESULTADO: FAIL — $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | FAIL | dump=$(basename "${DUMP:-ninguno}") | motivo=$1 | evidencia=$(basename "$EVID")" >> "$LOG"
    exit 1
}

# Seguridad: jamás restaurar sobre la base principal
[ "$DESTINO" = "$ORIGEN" ] && { echo "ABORTADO: destino = origen"; exit 1; }

# Ultimo respaldo generado, su huella (.conteo) y su hash (.sha256)
DUMP="$(ls -t "$DIR"/backups/foodstore_*.dump 2>/dev/null | head -n 1)"
[ -z "$DUMP" ] && fallar "no hay respaldos en $DIR/backups"
CONTEO_FILE="${DUMP%.dump}.conteo"
HASH_FILE="${DUMP%.dump}.sha256"
[ -f "$CONTEO_FILE" ] || fallar "falta el .conteo de este respaldo: generalo con backup_foodstore.sh"
[ -f "$HASH_FILE" ]   || fallar "falta el .sha256 de este respaldo: generalo con backup_foodstore.sh"

out "=== Simulacro de restauración — $(date '+%Y-%m-%d %H:%M:%S') ==="
out "Respaldo usado: $(basename "$DUMP") ($(stat -c %s "$DUMP") bytes)"

# Verificación 0: el .dump es exactamente el que se generó (mismo SHA256)
( cd "$(dirname "$DUMP")" && sha256sum -c --quiet "$(basename "$HASH_FILE")" ) > /dev/null 2>&1 \
    || fallar "el SHA256 del .dump no coincide con el registrado: el archivo cambió o está dañado"
out "SHA256 verificado: $(cut -d' ' -f1 "$HASH_FILE")"

# Se lee ANTES de arrancar el cronometro: es lectura de archivo, no parte del RTO.
CONTEO_RESPALDO="$(tr -d '\r' < "$CONTEO_FILE")"
[ -n "$CONTEO_RESPALDO" ] || fallar "el .conteo esta vacio: $CONTEO_FILE"

# Control humano: autorización escrita antes de borrar la base descartable
# Origen de la autorizacion: por variable de entorno (automatizable) o tipeada a mano
ORIGEN_CONFIRMA="interactivo"
if [ "${CONFIRMAR:-}" = "$DESTINO" ]; then
    ORIGEN_CONFIRMA="variable"
else
    read -r -p "Se va a BORRAR y recrear $DESTINO. Escribí su nombre para autorizar: " CONFIRMAR
fi
[ "$CONFIRMAR" = "$DESTINO" ] || fallar "borrado de $DESTINO no autorizado"
out "Borrado de $DESTINO autorizado por ${USERNAME:-${USER:-desconocido}} (origen=$ORIGEN_CONFIRMA) el $(date '+%Y-%m-%d %H:%M:%S')"
echo "$(date '+%Y-%m-%d %H:%M:%S') | AUTORIZADO | usuario=${USERNAME:-${USER:-desconocido}} | origen=$ORIGEN_CONFIRMA | accion=dropdb $DESTINO" >> "$LOG"

# Limpieza de un ensayo anterior (solo la base descartable, fuera del cronómetro)
dropdb "${CONN[@]}" --if-exists "$DESTINO" 2>/dev/null || fallar "no se pudo borrar $DESTINO anterior"

# Antiguedad del respaldo (RPO observado) al momento del simulacro: se mide ahora,
# antes de createdb y sin contar la espera de autorizacion.
STAMP="$(basename "$DUMP" .dump | sed 's/^foodstore_//')"   # AAAAMMDD_HHMMSS
F="${STAMP%_*}"; H="${STAMP#*_}"
EPOCH_DUMP=$(date -d "$F ${H:0:2}:${H:2:2}:${H:4:2}" +%s)
EDAD_SEG=$(( $(date +%s) - EPOCH_DUMP ))

# ---- Cronómetro: arranca inmediatamente antes de crear la base de prueba ----
T0=$(date +%s.%N)

createdb "${CONN[@]}" -T template0 "$DESTINO" || fallar "createdb $DESTINO"
# Confirmar contra el motor que la conexión va a la base descartable
BASE_ACTUAL="$(consulta -d "$DESTINO" -c 'SELECT current_database();')" || fallar "no se pudo consultar $DESTINO"
[ "$BASE_ACTUAL" = "$DESTINO" ] || fallar "la conexión no apunta a $DESTINO"
out "Destino confirmado por el motor: current_database() = $BASE_ACTUAL"
pg_restore "${CONN[@]}" -d "$DESTINO" --exit-on-error --no-owner --no-privileges "$DUMP" \
    || fallar "pg_restore"
T_RESTORE=$(date +%s.%N)

# Validación 1: misma huella que el respaldo (filas, total facturado y estructura)
HUELLA_RESTORE="$(consulta -d "$DESTINO" -f "$DIR/conteo_referencia.sql")" || fallar "huella en $DESTINO"

# Validación 2: indicadores de integridad (todos deben dar 0)
# El UNION ALL no garantiza el orden: se ordena por la columna 'orden' para que la
# evidencia salga siempre en el mismo orden que el SQL.
SQL_INTEGRIDAD="
SELECT clave, cantidad
FROM (
       SELECT 1 AS orden, 'precio_negativo' AS clave, count(*) AS cantidad
       FROM producto WHERE precio < 0
  UNION ALL SELECT 2, 'stock_negativo', count(*) FROM producto WHERE stock < 0
  UNION ALL SELECT 3, 'cantidad_no_positiva', count(*) FROM detalle_pedido WHERE cantidad <= 0
  UNION ALL SELECT 4, 'precio_unitario_negativo', count(*) FROM detalle_pedido WHERE precio_unitario < 0
  UNION ALL SELECT 5, 'detalle_sin_pedido', count(*) FROM detalle_pedido d
                WHERE NOT EXISTS (SELECT 1 FROM pedido p WHERE p.id_pedido = d.id_pedido)
  UNION ALL SELECT 6, 'detalle_sin_producto', count(*) FROM detalle_pedido d
                WHERE NOT EXISTS (SELECT 1 FROM producto pr WHERE pr.id_producto = d.id_producto)
  UNION ALL SELECT 7, 'pedido_sin_cliente', count(*) FROM pedido p
                WHERE NOT EXISTS (SELECT 1 FROM cliente c WHERE c.id_cliente = p.id_cliente)
  UNION ALL SELECT 8, 'producto_sin_categoria', count(*) FROM producto pr
                WHERE NOT EXISTS (SELECT 1 FROM categoria c WHERE c.id_categoria = pr.id_categoria)
) t
ORDER BY orden;"
INTEGRIDAD="$(consulta -d "$DESTINO" -c "$SQL_INTEGRIDAD")" || fallar "controles de integridad"

T1=$(date +%s.%N)
# ---- Cronómetro: termina cuando las validaciones terminaron ----

out ""
out "Validación 1 — huella restaurada vs respaldo (filas, total facturado y estructura):"
paste -d' ' <(echo "$HUELLA_RESTORE") <(echo "$CONTEO_RESPALDO" | cut -d' ' -f2) \
  | awk '{ printf "  %-16s restaurada=%-14s respaldo=%-14s %s\n", $1, $2, $3, ($2==$3 ? "OK" : "DIFERENTE") }' \
  | tee -a "$EVID"
out "Validación 2 — indicadores de integridad (esperado 0):"
echo "$INTEGRIDAD" | awk '{ printf "  %-26s %-6s %s\n", $1, $2, ($2=="0" ? "OK" : "FALLA") }' | tee -a "$EVID"
INTEGRIDAD_OK=$(echo "$INTEGRIDAD" | awk '$2 != "0" {m++} END {print (m ? "no" : "si")}')

# Tiempos
SEG_RESTORE=$(awk "BEGIN{printf \"%.2f\", $T_RESTORE - $T0}")
RTO=$(awk "BEGIN{printf \"%.2f\", $T1 - $T0}")

out ""
out "Tiempo createdb + pg_restore: ${SEG_RESTORE} s"
out "RTO observado (createdb -> validaciones OK): ${RTO} s"
out "Antigüedad del respaldo (RPO observado): ${EDAD_SEG} s (~$(( EDAD_SEG / 60 )) min). Medida antes de createdb; no incluye la espera de autorizacion."
out "Alcance: se restauran datos y estructura; NO roles ni permisos (--no-owner --no-privileges)."

if [ "$HUELLA_RESTORE" = "$CONTEO_RESPALDO" ] && [ "$INTEGRIDAD_OK" = "si" ]; then
    out "RESULTADO: PASS"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | PASS | dump=$(basename "$DUMP") | rto_s=$RTO | edad_respaldo_s=$EDAD_SEG | evidencia=$(basename "$EVID")" >> "$LOG"
    exit 0
else
    fallar "las validaciones no coinciden"
fi
