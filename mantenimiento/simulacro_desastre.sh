#!/usr/bin/env bash
# simulacro_desastre.sh — Simulacro de desastre contra reloj (TPI Parcial II, objetivo 8)
# Especificación: mantenimiento/SPEC_simulacro_desastre.md
#
# Escenario: en la copia descartable foodstore_desastre ("producción" del simulacro) se
# registran 3 pedidos después del último respaldo y luego alguien ejecuta
# DELETE FROM detalle_pedido; sin WHERE. Se detecta, se restaura el último respaldo de la
# tarea programada en foodstore_restore_test (con restore_test.sh) y se miden RTO y RPO.
#
# La base foodstore NUNCA se modifica: solo se lee su huella antes y después, para probar
# que el simulacro no la tocó.
# La contraseña NO va acá: se toma de %APPDATA%\postgresql\pgpass.conf (todas las conexiones usan -w).
#
# Uso:
#   MODO=ensayo ./mantenimiento/simulacro_desastre.sh   # actividad y desastre en BEGIN … ROLLBACK, sin restaurar
#   MODO=real   ./mantenimiento/simulacro_desastre.sh   # simulacro completo
# Para no tipear las autorizaciones: CONFIRMAR_DESASTRE=foodstore_desastre
#                                    CONFIRMAR_RECUPERACION=foodstore_restore_test

set -u -o pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
CONN=(-h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w)

MODO="${MODO:-ensayo}"
PRODUCCION="foodstore"                 # solo se lee su huella; nunca se escribe
DESASTRE="foodstore_desastre"          # "producción" del simulacro: acá se provoca el desastre
RECUPERACION="foodstore_restore_test"  # la usa restore_test.sh para restaurar

RTO_META=900      # 15 min, en segundos (SPEC_U6.md)
RPO_META=86400    # 24 h, en segundos (SPEC_U6.md)

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/logs/simulacro_desastre.log"
LOG_BACKUP="$DIR/logs/backup_foodstore.log"
SELLO="$(date +%Y%m%d_%H%M%S)"
EVID="$DIR/evidencias/simulacro_desastre_${SELLO}.txt"
mkdir -p "$DIR/logs" "$DIR/evidencias"
: > "$EVID"

out()  { echo "$*" | tee -a "$EVID"; }
hora() { date '+%Y-%m-%d %H:%M:%S'; }
# psql en Windows devuelve \r\n: se quita el \r para poder comparar.
consulta() { psql "${CONN[@]}" -X -A -t -F' ' -v ON_ERROR_STOP=1 "$@" | tr -d '\r'; }

DUMP=""
fallar() {
    out "RESULTADO: FAIL — $1"
    echo "$(hora) | FAIL | modo=$MODO | dump=$(basename "${DUMP:-ninguno}") | motivo=$1 | evidencia=$(basename "$EVID")" >> "$LOG"
    exit 1
}

# Guarda de base: se antepone a todo SQL que modifica datos. Si la conexión no apunta a
# foodstore_desastre, la sentencia aborta antes de tocar nada.
GUARDA="DO \$\$ BEGIN
  IF current_database() <> '$DESASTRE' THEN
    RAISE EXCEPTION 'ABORTADO: se esperaba la base $DESASTRE y la conexion apunta a %', current_database();
  END IF;
END \$\$;"

# ---- Controles previos -----------------------------------------------------------
[ "$MODO" = "ensayo" ] || [ "$MODO" = "real" ] || fallar "MODO debe ser 'ensayo' o 'real' (vino '$MODO')"
# Ninguna base que el script crea, borra o modifica puede ser la de producción.
for B in "$DESASTRE" "$RECUPERACION"; do
    [ "$B" = "$PRODUCCION" ] && { echo "ABORTADO: $B coincide con la base de producción"; exit 1; }
done

out "=== Simulacro de desastre (objetivo 8) — modo $MODO — $(hora) ==="

# Último respaldo, su huella (.conteo) y su hash (.sha256), igual que restore_test.sh
DUMP="$(ls -t "$DIR"/backups/foodstore_*.dump 2>/dev/null | head -n 1)"
[ -n "$DUMP" ] || fallar "no hay respaldos en $DIR/backups"
CONTEO_FILE="${DUMP%.dump}.conteo"
HASH_FILE="${DUMP%.dump}.sha256"
[ -f "$CONTEO_FILE" ] || fallar "falta el .conteo de $(basename "$DUMP")"
[ -f "$HASH_FILE" ]   || fallar "falta el .sha256 de $(basename "$DUMP")"
( cd "$(dirname "$DUMP")" && sha256sum -c --quiet "$(basename "$HASH_FILE")" ) > /dev/null 2>&1 \
    || fallar "el SHA256 de $(basename "$DUMP") no coincide: el archivo cambió o está dañado"

# La spec pide el último respaldo de la TAREA PROGRAMADA: se busca su línea PASS en el log.
LINEA_BACKUP="$(grep "| PASS |" "$LOG_BACKUP" 2>/dev/null | grep "archivo=$(basename "$DUMP")" | tail -n 1)"
echo "$LINEA_BACKUP" | grep -q "origen=programada" \
    || fallar "$(basename "$DUMP") no figura como PASS con origen=programada en $(basename "$LOG_BACKUP")"
CONTEO_RESPALDO="$(tr -d '\r' < "$CONTEO_FILE")"

# Hora del respaldo, desde el sello AAAAMMDD_HHMMSS del nombre del archivo
STAMP="$(basename "$DUMP" .dump | sed 's/^foodstore_//')"
F="${STAMP%_*}"; H="${STAMP#*_}"
EPOCH_DUMP=$(date -d "$F ${H:0:2}:${H:2:2}:${H:4:2}" +%s)
out "Respaldo usado: $(basename "$DUMP") ($(stat -c %s "$DUMP") bytes), del $(date -d "@$EPOCH_DUMP" '+%Y-%m-%d %H:%M:%S'), SHA256 verificado"
out "Origen del respaldo (log de backup_foodstore.sh): $LINEA_BACKUP"

# Huella de foodstore ANTES (solo lectura): al final se compara para probar que no se tocó
HUELLA_PROD_ANTES="$(consulta -d "$PRODUCCION" -f "$DIR/conteo_referencia.sql")" || fallar "no se pudo leer la huella de $PRODUCCION"

# ---- Autorizaciones: se piden todas ANTES de arrancar, para no frenar el cronómetro ----
autorizar() {   # $1 = base a borrar, $2 = valor ya recibido por variable
    local base="$1" valor="$2" origen="variable"
    if [ "$valor" != "$base" ]; then
        origen="interactivo"
        read -r -p "Se va a BORRAR y recrear $base. Escribí su nombre para autorizar: " valor
    fi
    [ "$valor" = "$base" ] || fallar "borrado de $base no autorizado"
    out "Borrado de $base autorizado por ${USERNAME:-${USER:-desconocido}} (origen=$origen) el $(hora)"
    echo "$(hora) | AUTORIZADO | usuario=${USERNAME:-${USER:-desconocido}} | origen=$origen | accion=dropdb $base" >> "$LOG"
}
autorizar "$DESASTRE" "${CONFIRMAR_DESASTRE:-}"
[ "$MODO" = "real" ] && autorizar "$RECUPERACION" "${CONFIRMAR_RECUPERACION:-}"

# ---- Fase 0: preparar "producción" desde el último respaldo ---------------------------
out ""
out "--- Fase 0: preparación de $DESASTRE ---"
dropdb "${CONN[@]}" --if-exists "$DESASTRE" || fallar "no se pudo borrar $DESASTRE anterior"
createdb "${CONN[@]}" -T template0 "$DESASTRE" || fallar "createdb $DESASTRE"
[ "$(consulta -d "$DESASTRE" -c 'SELECT current_database();')" = "$DESASTRE" ] || fallar "la conexión no apunta a $DESASTRE"
pg_restore "${CONN[@]}" -d "$DESASTRE" --exit-on-error --no-owner --no-privileges "$DUMP" || fallar "pg_restore en $DESASTRE"
HUELLA_INICIAL="$(consulta -d "$DESASTRE" -f "$DIR/conteo_referencia.sql")" || fallar "huella de $DESASTRE"
[ "$HUELLA_INICIAL" = "$CONTEO_RESPALDO" ] || fallar "$DESASTRE no quedó igual al respaldo"
out "$DESASTRE creada desde el respaldo: huella igual al .conteo (11/11)"

# Último pedido que trae el respaldo: lo que se registre después tiene id mayor
MAX_PEDIDO_RESPALDO="$(consulta -d "$DESASTRE" -c 'SELECT max(id_pedido) FROM pedido;')"

# ---- Fase 1: actividad posterior al respaldo (3 pedidos) ------------------------------
# Clientes y productos elegidos por el script: los 3 primeros clientes y los 6 primeros
# productos activos con stock suficiente (los triggers de restricciones.sql rechazan
# productos dados de baja o sin stock). Cada pedido lleva 2 productos distintos.
read -r -a CLIENTES <<< "$(consulta -d "$DESASTRE" -c "SELECT string_agg(id_cliente::text, ' ') FROM (SELECT id_cliente FROM cliente ORDER BY id_cliente LIMIT 3) t;")"
read -r -a PRODUCTOS <<< "$(consulta -d "$DESASTRE" -c "SELECT string_agg(id_producto::text, ' ') FROM (SELECT id_producto FROM producto WHERE activo AND stock >= 10 ORDER BY id_producto LIMIT 6) t;")"
[ "${#CLIENTES[@]}" -eq 3 ] && [ "${#PRODUCTOS[@]}" -eq 6 ] || fallar "no hay 3 clientes y 6 productos activos con stock para la actividad"

FORMAS=(EFECTIVO TARJETA TRANSFERENCIA)
SQL_ACTIVIDAD=""
for i in 0 1 2; do
    P1="${PRODUCTOS[$((i * 2))]}"; P2="${PRODUCTOS[$((i * 2 + 1))]}"
    SQL_ACTIVIDAD+="CALL registrar_pedido(${CLIENTES[$i]}, '${FORMAS[$i]}', '[{\"id_producto\": $P1, \"cantidad\": 1}, {\"id_producto\": $P2, \"cantidad\": 2}]'::jsonb);
"
done
SQL_DESASTRE="DELETE FROM detalle_pedido;"   # el error humano del escenario: sin WHERE
# Pedidos y líneas posteriores al respaldo (id_pedido mayor que el último del respaldo)
EXPR_NUEVOS="(SELECT count(*) FROM pedido WHERE id_pedido > $MAX_PEDIDO_RESPALDO),
             (SELECT count(*) FROM detalle_pedido WHERE id_pedido > $MAX_PEDIDO_RESPALDO)"

out ""
out "--- Fase 1: actividad posterior al respaldo ---"
out "Clientes: ${CLIENTES[*]} | productos: ${PRODUCTOS[*]} | último pedido del respaldo: $MAX_PEDIDO_RESPALDO"

# ---- MODO ensayo: todo dentro de BEGIN … ROLLBACK, sin restaurar ----------------------
if [ "$MODO" = "ensayo" ]; then
    SALIDA="$(consulta -d "$DESASTRE" 2>&1 <<SQL
BEGIN;
$GUARDA
$SQL_ACTIVIDAD
SELECT 'actividad', $EXPR_NUEVOS;
$SQL_DESASTRE
SELECT 'desastre', (SELECT count(*) FROM detalle_pedido), (SELECT count(*) FROM pedido);
ROLLBACK;
SQL
)" || { out "$SALIDA"; fallar "el ensayo falló dentro de la transacción"; }
    out "$SALIDA"
    HUELLA_DESPUES="$(consulta -d "$DESASTRE" -f "$DIR/conteo_referencia.sql")" || fallar "huella de $DESASTRE"
    [ "$HUELLA_DESPUES" = "$CONTEO_RESPALDO" ] || fallar "el ROLLBACK no dejó $DESASTRE igual al respaldo"
    out "ROLLBACK verificado: $DESASTRE volvió a la huella del respaldo (11/11)"
    HUELLA_PROD_DESPUES="$(consulta -d "$PRODUCCION" -f "$DIR/conteo_referencia.sql")" || fallar "huella de $PRODUCCION"
    [ "$HUELLA_PROD_DESPUES" = "$HUELLA_PROD_ANTES" ] || fallar "la huella de $PRODUCCION cambió"
    out "$PRODUCCION sin cambios: huella antes = después (11/11)"
    out "RESULTADO: ENSAYO OK (no se restauró nada; correr con MODO=real)"
    echo "$(hora) | ENSAYO_OK | dump=$(basename "$DUMP") | evidencia=$(basename "$EVID")" >> "$LOG"
    exit 0
fi

# ---- MODO real ------------------------------------------------------------------------
# BEGIN … COMMIT explícitos en el SQL, en lugar de la opción psql -1: así la transacción
# se lee en el guion igual que el BEGIN … ROLLBACK del ensayo.
# Con ON_ERROR_STOP, si algo falla psql sale sin llegar al COMMIT y la transacción se descarta.
# Sin ON_ERROR_STOP, psql terminaría con código 0 aunque haya errores (comprobado en el motor).
consulta -d "$DESASTRE" >> "$EVID" 2>&1 <<SQL || fallar "no se pudo registrar la actividad"
BEGIN;
$GUARDA
$SQL_ACTIVIDAD
COMMIT;
SQL
T_ACTIVIDAD="$(hora)"
read -r PEDIDOS_NUEVOS LINEAS_NUEVAS <<< "$(consulta -d "$DESASTRE" -c "SELECT $EXPR_NUEVOS;")"
out "[$T_ACTIVIDAD] Actividad registrada: $PEDIDOS_NUEVOS pedidos y $LINEAS_NUEVAS líneas que NO están en el respaldo"

# ---- Fase 2: el desastre --------------------------------------------------------------
out ""
out "--- Fase 2: desastre ---"
consulta -d "$DESASTRE" >> "$EVID" 2>&1 <<SQL || fallar "no se pudo provocar el desastre"
BEGIN;
$GUARDA
$SQL_DESASTRE
COMMIT;
SQL
EPOCH_DESASTRE=$(date +%s); T_DESASTRE="$(date -d "@$EPOCH_DESASTRE" '+%Y-%m-%d %H:%M:%S')"
out "[$T_DESASTRE] Ejecutado en $DESASTRE: $SQL_DESASTRE"

# ---- Fase 3: detección (arranca el reloj) ---------------------------------------------
# Control de salud: pedidos que no tienen ninguna línea de detalle.
read -r DETALLES PEDIDOS_VACIOS <<< "$(consulta -d "$DESASTRE" -c \
    "SELECT (SELECT count(*) FROM detalle_pedido),
            (SELECT count(*) FROM pedido p WHERE NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido));")"
[ "$DETALLES" = "0" ] && [ "$PEDIDOS_VACIOS" -gt 0 ] || fallar "la detección no encontró el desastre (detalles=$DETALLES)"
T0=$(date +%s.%N); T_DETECCION="$(hora)"
out ""
out "--- Fase 3: detección ---"
out "[$T_DETECCION] Detectado: detalle_pedido tiene $DETALLES filas y hay $PEDIDOS_VACIOS pedidos sin líneas. Arranca el reloj."

# ---- Fases 4 y 5: recuperación y validación con restore_test.sh -----------------------
out ""
out "--- Fases 4 y 5: recuperación en $RECUPERACION con restore_test.sh ---"
CONFIRMAR="$RECUPERACION" bash "$DIR/restore_test.sh" >> "$EVID" 2>&1
RC_RESTORE=$?
T1=$(date +%s.%N); T_VALIDADO="$(hora)"
EVID_RESTORE="$(ls -t "$DIR"/evidencias/restore_test_*.txt 2>/dev/null | head -n 1)"
[ "$RC_RESTORE" -eq 0 ] || fallar "restore_test.sh terminó con FAIL (ver $(basename "$EVID_RESTORE"))"
grep -q "Respaldo usado: $(basename "$DUMP")" "$EVID_RESTORE" \
    || fallar "restore_test.sh no usó el mismo respaldo que el simulacro"
out "[$T_VALIDADO] restore_test.sh: PASS (huella 11/11 y 8 indicadores en 0). Para el reloj. Evidencia: $(basename "$EVID_RESTORE")"

# ---- Fase 6: pérdida de datos ---------------------------------------------------------
# Lo que había en producción después del respaldo y no volvió con la restauración.
MAX_PEDIDO_RECUPERADO="$(consulta -d "$RECUPERACION" -c 'SELECT max(id_pedido) FROM pedido;')"
PEDIDOS_PERDIDOS="$(consulta -d "$DESASTRE" -c "SELECT count(*) FROM pedido WHERE id_pedido > $MAX_PEDIDO_RECUPERADO;")"
out ""
out "--- Fase 6: pérdida de datos ---"
out "Pedidos de $DESASTRE que no están en la base recuperada: $PEDIDOS_PERDIDOS (líneas registradas en la fase 1: $LINEAS_NUEVAS)"

# ---- Medición y criterios -------------------------------------------------------------
RTO=$(awk "BEGIN{printf \"%.2f\", $T1 - $T0}")
RPO_SEG=$(( EPOCH_DESASTRE - EPOCH_DUMP ))
HUELLA_PROD_DESPUES="$(consulta -d "$PRODUCCION" -f "$DIR/conteo_referencia.sql")" || fallar "huella de $PRODUCCION"

out ""
out "--- Línea de tiempo ---"
out "  Respaldo (tarea programada)  $(date -d "@$EPOCH_DUMP" '+%Y-%m-%d %H:%M:%S')"
out "  Actividad posterior          $T_ACTIVIDAD"
out "  Desastre                     $T_DESASTRE"
out "  Detección (inicio del reloj) $T_DETECCION"
out "  Validado (fin del reloj)     $T_VALIDADO"
out ""
out "RTO observado (detección -> validado): ${RTO} s   meta <= ${RTO_META} s"
out "RPO observado (respaldo -> desastre):  ${RPO_SEG} s (~$(( RPO_SEG / 60 )) min)   meta <= ${RPO_META} s"
out "Datos perdidos: $PEDIDOS_PERDIDOS pedidos y $LINEAS_NUEVAS líneas (registrados después del respaldo)"

OK=1
cumple() { if [ "$2" = "si" ]; then out "  [OK]    $1"; else out "  [FALLA] $1"; OK=0; fi; }
out ""
out "--- Criterios de aceptación (SPEC_simulacro_desastre.md) ---"
cumple "1. $DESASTRE = respaldo + 3 pedidos antes del desastre" "$([ "$PEDIDOS_NUEVOS" = "3" ] && echo si || echo no)"
cumple "2. detalle_pedido en 0 tras el desastre y detectado"    "$([ "$DETALLES" = "0" ] && echo si || echo no)"
cumple "3. restore_test.sh en PASS"                              "$([ "$RC_RESTORE" -eq 0 ] && echo si || echo no)"
cumple "4. RTO <= 15 min y RPO <= 24 h" "$(awk "BEGIN{print ($RTO <= $RTO_META && $RPO_SEG <= $RPO_META) ? \"si\" : \"no\"}")"
cumple "5. pérdida = actividad de la fase 1 (3 pedidos)"         "$([ "$PEDIDOS_PERDIDOS" = "$PEDIDOS_NUEVOS" ] && echo si || echo no)"
cumple "6. $PRODUCCION sin cambios (huella antes = después)"     "$([ "$HUELLA_PROD_DESPUES" = "$HUELLA_PROD_ANTES" ] && echo si || echo no)"

if [ "$OK" -eq 1 ]; then
    out "RESULTADO: PASS"
    echo "$(hora) | PASS | dump=$(basename "$DUMP") | rto_s=$RTO | rpo_s=$RPO_SEG | pedidos_perdidos=$PEDIDOS_PERDIDOS | lineas_perdidas=$LINEAS_NUEVAS | evidencia=$(basename "$EVID")" >> "$LOG"
    out "La base $DESASTRE queda dañada para el análisis. Para borrarla: dropdb -U postgres $DESASTRE"
    exit 0
else
    fallar "no se cumplen todos los criterios de aceptación"
fi
