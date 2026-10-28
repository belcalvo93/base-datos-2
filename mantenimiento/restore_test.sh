#!/usr/bin/env bash
# restore_test.sh — Simulacro de restauración contra reloj (TP Unidad 6)
# Restaura el ÚLTIMO respaldo de foodstore en la base DESCARTABLE foodstore_restore_test,
# valida tablas y restricciones lógicas y mide RTO y antigüedad del respaldo (RPO observado).
# La base foodstore NUNCA se toca: solo se lee para comparar conteos.
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf

set -u -o pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
ORIGEN="foodstore"
DESTINO="foodstore_restore_test"
CONN=(-h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w)

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/logs/restore_test.log"
EVID="$DIR/evidencias/restore_test_salida.txt"
mkdir -p "$DIR/logs" "$DIR/evidencias"
: > "$EVID"
out() { echo "$*" | tee -a "$EVID"; }
# psql en Windows devuelve fin de línea \r\n: se quita el \r para poder comparar
consulta() { psql "${CONN[@]}" -X -A -t -F' ' "$@" | tr -d '\r'; }

fallar() {
    out "RESULTADO: FALLA — $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | FALLA | $1" >> "$LOG"
    exit 1
}

# Seguridad: jamás restaurar sobre la base principal
[ "$DESTINO" = "$ORIGEN" ] && { echo "ABORTADO: destino = origen"; exit 1; }

# Último respaldo generado
DUMP="$(ls -t "$DIR"/backups/foodstore_*.dump 2>/dev/null | head -n 1)"
[ -z "$DUMP" ] && fallar "no hay respaldos en $DIR/backups"

out "=== Simulacro de restauración — $(date '+%Y-%m-%d %H:%M:%S') ==="
out "Respaldo usado: $(basename "$DUMP") ($(stat -c %s "$DUMP") bytes)"

# Limpieza de un ensayo anterior (solo la base descartable, fuera del cronómetro)
dropdb "${CONN[@]}" --if-exists "$DESTINO" 2>/dev/null || fallar "no se pudo borrar $DESTINO anterior"

# ---- Cronómetro: arranca inmediatamente antes de crear la base de prueba ----
T0=$(date +%s.%N)

createdb "${CONN[@]}" "$DESTINO" || fallar "createdb $DESTINO"
pg_restore "${CONN[@]}" -d "$DESTINO" --no-owner --no-privileges "$DUMP" || fallar "pg_restore"
T_RESTORE=$(date +%s.%N)

SQL_CONTEO="SELECT 'categoria' AS tabla, COUNT(*) AS filas FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;"

SQL_INVALIDOS="SELECT (SELECT COUNT(*) FROM producto WHERE precio < 0 OR stock < 0),
       (SELECT COUNT(*) FROM detalle_pedido WHERE cantidad <= 0 OR precio_unitario < 0);"

CONTEO_RESTORE="$(consulta -d "$DESTINO" -c "$SQL_CONTEO")" || fallar "conteo en $DESTINO"
CONTEO_ORIGEN="$(consulta -d "$ORIGEN" -c "$SQL_CONTEO")" || fallar "conteo en $ORIGEN"
read -r PROD_INV DET_INV <<< "$(consulta -d "$DESTINO" -c "$SQL_INVALIDOS")"

T1=$(date +%s.%N)
# ---- Cronómetro: termina cuando las validaciones mínimas terminaron ----

out ""
out "Validación 1 — filas por tabla (restaurada vs foodstore):"
paste -d' ' <(echo "$CONTEO_RESTORE") <(echo "$CONTEO_ORIGEN" | cut -d' ' -f2) \
  | awk '{ printf "  %-15s restaurada=%-8s foodstore=%-8s %s\n", $1, $2, $3, ($2==$3 ? "OK" : "DIFERENTE") }' \
  | tee -a "$EVID"
out "Validación 2 — productos inválidos (precio<0 o stock<0): $PROD_INV"
out "Validación 3 — detalles inválidos (cantidad<=0 o precio_unitario<0): $DET_INV"

# Tiempos
SEG_RESTORE=$(awk "BEGIN{printf \"%.2f\", $T_RESTORE - $T0}")
RTO=$(awk "BEGIN{printf \"%.2f\", $T1 - $T0}")

# Antigüedad del respaldo (RPO observado): fecha del nombre del archivo vs ahora
STAMP="$(basename "$DUMP" .dump | sed 's/^foodstore_//')"   # AAAAMMDD_HHMMSS
F="${STAMP%_*}"; H="${STAMP#*_}"
EPOCH_DUMP=$(date -d "$F ${H:0:2}:${H:2:2}:${H:4:2}" +%s)
EDAD_SEG=$(( $(date +%s) - EPOCH_DUMP ))

out ""
out "Tiempo createdb + pg_restore: ${SEG_RESTORE} s"
out "RTO observado (createdb -> validaciones OK): ${RTO} s"
out "Antigüedad del respaldo (RPO observado): ${EDAD_SEG} s (~$(( EDAD_SEG / 60 )) min)"

if [ "$CONTEO_RESTORE" = "$CONTEO_ORIGEN" ] && [ "$PROD_INV" = "0" ] && [ "$DET_INV" = "0" ]; then
    out "RESULTADO: OK"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | OK | dump=$(basename "$DUMP") | rto_s=$RTO | edad_respaldo_s=$EDAD_SEG" >> "$LOG"
    exit 0
else
    fallar "las validaciones no coinciden"
fi
