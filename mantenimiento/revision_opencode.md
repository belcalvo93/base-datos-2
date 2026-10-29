# Revisión OpenCode — TP Unidad 6 (mantenimiento)

**Revisor:** OpenCode (rol: revisar y proponer, no ejecutar)
**Fecha:** 2026-10-28
**Contra:** `mantenimiento/SPEC_U6.md`, `AGENTS.md` y `mantenimiento/README.md`

## Alcance y método

- Revisión **estática** de los 4 archivos. **No se ejecutó nada contra la base**: ni `psql`, ni `pg_dump`, ni `createdb`, ni `dropdb`.
- Para verificar afirmaciones sobre Windows/Git Bash se corrieron solo pruebas de shell inocuas (`date -d`, `date +%s.%N`, `stat -c`, `ls -t` sin coincidencias, `$?` en rama `else`) en Git Bash 5.3 (Cygwin), más `git ls-files --eol` y `git ls-files -s`.
- Para lo que solo se puede ver corriendo contra el motor, usé la evidencia ya commiteada en `mantenimiento/evidencias/` y `mantenimiento/logs/`.
- **No se modificó ninguno de los 4 archivos.** Este informe es el único archivo creado.

Leyenda de severidad: **[Alto]** rompe el SPEC o pone en riesgo `foodstore` · **[Medio]** debilita la evidencia o la validez del resultado · **[Bajo]** robustez/trazabilidad · **[OK]** verificado y correcto.

---

## 1. `mantenimiento/backup_foodstore.sh`

### 1.1 Cumplimiento del SPEC

| Requisito del SPEC | ¿Cumple? | Evidencia (línea) |
|---|---|---|
| R1 — Formato custom `-Fc` para restaurar con `pg_restore` | **Sí** | L28: `pg_dump ... -Fc -w -f "$ARCHIVO"` |
| R2 — Nombre `foodstore_AAAAMMDD_HHMMSS.dump` | **Sí** | L21 `FECHA="$(date +%Y%m%d_%H%M%S)"` + L22 `"$BACKUP_DIR/${DB_NAME}_${FECHA}.dump"` (con `DB_NAME=foodstore` por defecto, L12) |
| R3 — Una línea por ejecución en `logs/backup_foodstore.log` con fecha, archivo, tamaño y resultado | **Sí, parcial en el caso ERROR** | L31 (OK): `fecha \| OK \| base \| archivo= \| bytes= \| segundos=` — tiene los 4 campos. L39 (ERROR): `fecha \| ERROR \| base \| codigo \| detalle` — **falta `archivo` y `bytes`** |
| R4 — Si `pg_dump` falla: registra `ERROR`, borra el archivo incompleto y sale con código ≠ 0 | **Sí** | L38 `rm -f "$ARCHIVO" "$ERR_TMP"` · L39 log `ERROR` · L41 `exit 1` |
| Condición de éxito: código 0 + archivo con tamaño > 0 + log `OK` | **Código 0 sí (L28/L34), archivo sí, `OK` sí (L31), pero el tamaño > 0 no se valida** | L30 solo *mide* (`stat -c %s`) y lo escribe en el log; nunca lo compara con 0 antes de declarar `OK` |
| Sin contraseñas en el script (pgpass / `PGPASSWORD` de sesión) | **Sí** | L3 lo documenta; `grep -i 'PGPASSWORD\|password\|postgres:'` sobre los `.sh` → sin resultados; L28 `-w` (nunca pide contraseña) |
| `foodstore` nunca se elimina ni se reemplaza | **Sí** | Solo lectura: `pg_dump` no escribe en la base (L28). No hay `dropdb`/`pg_restore`/`createdb` en el archivo |
| Antes del respaldo se guarda el conteo de filas por tabla (SPEC L27) | **No lo hace el script** — se hace a mano | `README.md` L29-34 lo genera hacia `evidencias/conteo_antes_respaldo.txt` (existe y está versionado). El script no lo produce ni lo referencia |
| `*.dump` no versionado | **Sí** | `.gitignore` tiene `*.dump`; `git ls-files mantenimiento` no lista ningún `.dump` (solo `backups/foodstore_20261028_200259.dump` en disco, 9.428.332 bytes, ignorado) |

### 1.2 Problemas y riesgos

1. **[Bajo] No valida que el dump no esté vacío.** La condición de éxito del SPEC exige tamaño > 0. En L30, si `stat` fallara o el archivo quedara en 0 bytes, el script igual loguea `OK` (con `bytes=` vacío o `bytes=0`) y sale con 0. La evidencia en el log (`bytes=9428332`) es correcta, pero es *suerte*, no *control*.
2. **[Bajo] El log de ERROR no permite reconstruir qué archivo falló** (L39): no incluye `archivo=` ni el tamaño. El SPEC (L19) pide fecha, archivo, tamaño y resultado en *cada* línea. Como el archivo se borra (L38), el nombre solo sobrevive si estaba en el log.
3. **[Bajo] Sin rotación/retención.** Un dump diario de ~9,4 MB (evidencia: `bytes=9428332`) son ~3,4 GB al año. Nada purga respaldos viejos.
4. **[Bajo] `ERR_TMP` con nombre fijo** (L23): dos ejecuciones concurrentes (p. ej. cron + manual) comparten el mismo archivo temporal y pueden pisarse el mensaje de error.
5. **[Bajo] `CODIGO=$?` (L36) funciona pero es frágil.** Verifiqué el comportamiento en bash 5.3: en la rama `else` de un `if comando`, `$?` conserva el código del comando de la condición. Es correcto hoy, pero cualquier línea que se agregue antes de L36 lo rompe en silencio.
6. **[Bajo] `DB_NAME` configurable (L12) permite respaldar otra base** y el nombre del archivo lo refleja (bien), pero `restore_test.sh` solo busca `foodstore_*.dump` (su L36): si alguien corre `DB_NAME=bd2_tp3 ./backup_foodstore.sh`, el simulacro seguirá usando un dump viejo de `foodstore` sin avisar. El README ya lo usa como prueba de error (L38), así que el riesgo es real.
7. **[Bajo] No se verifica la integridad del archivo generado.** Un `pg_restore -l` sobre el dump recién creado detectaría un archivo corrupto en el momento del respaldo y no una semana después, en pleno simulacro.
8. **[OK] Compatibilidad Git Bash / Windows:** verifiqué que `stat -c %s`, `date +%Y%m%d_%H%M%S` y `mkdir -p` funcionan; todas las rutas con posible espacio están entrecomilladas (L15-22); `.gitattributes` fuerza `*.sh text eol=lf` y `git ls-files --eol` confirma `i/lf w/lf` → sin riesgo de CRLF en el shebang. `-w` evita que una tarea programada quede colgada esperando contraseña.
9. **[OK] El log va a `logs/backup_foodstore.log` relativo a la ubicación del script** (L15-18), tal como pide el SPEC, y funciona "desde cualquier carpeta" (L4).

### 1.3 Mejora concreta

Validar el resultado antes de declarar `OK` y unificar el formato del log en ambos caminos:

```bash
if pg_dump ... -Fc -w -f "$ARCHIVO" 2> "$ERR_TMP" && [ -s "$ARCHIVO" ] \
   && pg_restore -l "$ARCHIVO" > /dev/null 2>&1; then
    TAMANO=$(stat -c %s "$ARCHIVO")
    echo "... | OK | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | bytes=$TAMANO | ..." >> "$LOG"
else
    CODIGO=$?
    echo "... | ERROR | base=$DB_NAME | archivo=$(basename "$ARCHIVO") | codigo=$CODIGO | detalle=$MENSAJE" >> "$LOG"
    rm -f "$ARCHIVO" "$ERR_TMP"; exit 1
fi
```

Con eso la condición de éxito del SPEC (L10) queda *verificada*, no solo *informada*, y el log es homogéneo. Complemento barato: retención de N días (`find "$BACKUP_DIR" -name 'foodstore_*.dump' -mtime +30 -delete`) y `mktemp` para el archivo de error.

---

## 2. `mantenimiento/health_check.sql`

### 2.1 Cumplimiento del SPEC

El SPEC (L11) pide que la salida muestre **4 controles**. Están los 4:

| Control exigido | ¿Cumple? | Evidencia (línea) |
|---|---|---|
| 1. Tamaño | **Sí** | L9 tamaño de la base · L11-14 tamaño por tabla (`pg_total_relation_size`) |
| 2. Conexiones | **Sí** | L17-20 `numbackends`, commits/rollbacks, cache hit · L22-25 conexiones por `state` |
| 3. Estado de las tablas | **Sí** | L28-32 `n_live_tup`, `n_dead_tup`, `%` muertas, `last_autovacuum`, `last_autoanalyze` |
| 4. Consultas activas | **Sí** | L35-39 `pg_stat_activity` con `state <> 'idle'` y excluyendo la propia sesión |
| Solo lectura | **Sí** | Todos son `SELECT`; no hay DDL ni DML |
| Confirmación de base | **Parcial (aceptable)** | L6 imprime `current_database()` en el control 0; no hay guard que aborte. Al ser de solo lectura no viola la regla del SPEC L25 (que apunta a comandos destructivos) |

La salida real confirma los 4 bloques: `evidencias/health_check_salida.txt` L1 (§0), L7 (§1), L23 (§2), L34 (§3), L45 (§4), sobre `foodstore` 17.11.

### 2.2 Problemas y riesgos

1. **[Medio] El control 3 es engañoso justo en el escenario del TP.** `foodstore` se crea con `createdb -T bd2_tp3`, y los contadores de actividad **no se copian**. Resultado real (evidencia L37-42): `n_live_tup = 0` y `last_autovacuum`/`last_autoanalyze` vacíos para las 6 tablas, cuando `detalle_pedido` tiene 499.263 filas. Quien lea solo el health check concluye "la base está vacía". El dato correcto sí existe en el catálogo (`reltuples`), como muestra `maintenance_salida.txt` L15-19 (499263, 200005, …). **Esto no es un bug del script, es un riesgo de interpretación de la evidencia** — pero es exactamente lo que un revisor va a preguntar.
2. **[Bajo] `pct_muertas` sale vacío en vez de `0`** cuando `n_live_tup + n_dead_tup = 0`, por el `NULLIF(...,0)` de L29 (evidencia L37-42). Un `coalesce(round(...), 0)` lo deja legible.
3. **[Bajo] No hay `\set ON_ERROR_STOP on`.** Si una consulta falla (p. ej. cambio de nombre de una vista del sistema), `psql` sigue con las siguientes y **termina con código 0**: el archivo de evidencia queda incompleto y parece completo. Para una tarea diaria automatizada conviene que falle ruidoso.
4. **[Bajo] Muestra números, pero no emite veredicto.** No hay umbral ni columna de estado (`OK`/`REVISAR`). Eso obliga a interpretar a ojo y, peor, deja sin insumo objetivo la regla del SPEC L26 ("un `VACUUM`/`ANALYZE` manual solo si hay tuplas muertas o estadísticas desactualizadas").
5. **[OK] El filtro de consultas activas está bien pensado:** `state <> 'idle'` incluye `idle in transaction` (que sí importa para locks) y excluye la propia sesión (L39). Los `state` NULL (procesos de fondo) quedan afuera por la lógica de NULL, que es lo deseable.
6. **[OK] Textos en ASCII sin tildes** (`Tamano`, `sesion`, L8/L27/L34) → cero riesgo de mojibake en consolas Windows. El uso documentado incluye `-X` (L2), así que un `.psqlrc` no contamina la salida.

### 2.3 Mejora concreta

Agregar la estimación del catálogo al control 3 y un veredicto por umbral:

```sql
SELECT s.relname AS tabla, s.n_live_tup, s.n_dead_tup,
       coalesce(round(100.0 * s.n_dead_tup / NULLIF(s.n_live_tup + s.n_dead_tup, 0), 2), 0) AS pct_muertas,
       c.reltuples::bigint AS filas_estimadas,   -- sobrevive al createdb -T
       s.last_autovacuum, s.last_autoanalyze,
       CASE WHEN s.n_live_tup + s.n_dead_tup = 0 THEN 'SIN CONTADORES (correr ANALYZE)'
            WHEN 100.0 * s.n_dead_tup / (s.n_live_tup + s.n_dead_tup) > 20 THEN 'REVISAR'
            ELSE 'OK' END AS veredicto
FROM pg_stat_user_tables s JOIN pg_class c ON c.oid = s.relid
ORDER BY s.n_dead_tup DESC;
```

Más `\set ON_ERROR_STOP on` al inicio (después del comentario de cabecera) y `\echo` con el veredicto final.

---

## 3. `mantenimiento/maintenance.sql`

### 3.1 Cumplimiento del SPEC

| Requisito del SPEC (L12) | ¿Cumple? | Evidencia (línea) |
|---|---|---|
| Registra tuplas muertas | **Sí** | L23 `s.n_dead_tup` (también `n_live_tup` y `n_mod_since_analyze`) |
| Registra último autovacuum / autoanalyze | **Sí** | L24 `s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze` |
| Registra la acción tomada | **Sí** | L35 `ANALYZE VERBOSE categoria, cliente, producto, pedido, detalle_pedido;` (y el "DESPUÉS" en L38-45) |
| Registra la justificación | **Parcial** | L29-33: la justificación está **como comentario del script**, no en la salida. La evidencia se genera con `>` de stdout (`README.md` L42), así que la justificación **no queda en `maintenance_salida.txt`** |
| Guard: solo sobre `foodstore` | **Sí, y la lógica es correcta** | L6 `SELECT current_database() <> 'foodstore' AS no_es_foodstore \gset` + L7-10 `\if`/`\quit`. Verificado el razonamiento: `\gset` guarda `t`/`f` y `\if` interpreta `t`/`f` |
| No usa `VACUUM FULL` | **Sí** | L3 lo declara; `grep -i vacuum` en `*.sql` solo devuelve ese comentario: no hay `VACUUM` de ningún tipo |

### 3.2 Problemas y riesgos

1. **[Medio] `usuario` queda fuera del `ANALYZE`** (L35 lista 5 tablas, la base tiene 6). El comentario de L34 dice "las tablas de Food Store", así que el script promete más de lo que hace. Evidencia inequívoca: `maintenance_salida.txt` L48 → `usuario | -1 | 0 | 0 | 0 | (sin fecha de analyze)`, mientras las otras 5 quedaron con `last_analyze` (L43-47). `usuario` es la tabla del TP5 Parte B, no es un descarte.
2. **[Medio] El `ANALYZE` corre incondicionalmente, contra el SPEC L26.** El SPEC dice que un `ANALYZE` manual "solo se ejecuta si `maintenance.sql` muestra tuplas muertas o estadísticas desactualizadas". La justificación de L30-32 (contadores en 0 tras `createdb -T`) es **válida para la primera corrida**; a partir de la segunda, el script vuelve a analizar sin mirar el estado. La propia evidencia del "DESPUÉS" muestra que no había nada que justificara la acción: `n_dead_tup` = 0/1/2 (0,00 %) frente al umbral de autovacuum vigente (`autovacuum_vacuum_threshold = 50` + `scale_factor = 0.2`, evidencia L8-9). Es defendible oralmente la primera vez; como tarea *semanal* repetida, no.
3. **[Bajo] No existe camino condicional de `VACUUM`.** Si algún día `n_dead_tup` supera el umbral, el script lo muestra pero no hace nada: solo `ANALYZE`. El SPEC no exige automatizar el `VACUUM`, pero el archivo se presenta como "mantenimiento justificado" (L1) y no cierra el circuito.
4. **[Bajo] El aborto sale con código 0.** `\quit` (L9) termina `psql` con estado 0, así que una tarea programada no distingue "abortado porque la base no era `foodstore`" de "ejecutado bien". Sumado a la ausencia de `ON_ERROR_STOP`, un fallo del `ANALYZE` tampoco cambia el código de salida.
5. **[Bajo] `filas_estimadas = -1`** para tablas nunca analizadas (evidencia L20 y L48, `usuario`). Es el valor real de `reltuples` sin `ANALYZE`, no un error — pero conviene aclararlo en el informe para que no se lea como un defecto.
6. **[OK] `SELECT pg_stat_clear_snapshot();` (L38) es correcto y necesario**: sin eso, el "DESPUÉS" repetiría la foto de estadísticas cacheada por la sesión. La evidencia lo confirma: L15-19 (antes, `n_live_tup=0`) vs L43-47 (después, 499263/200005/…).
7. **[OK] El guard de base es el único de los cuatro scripts que cumple literalmente el SPEC L25** ("se confirma con `SELECT current_database()`"). Es el patrón a copiar en `restore_test.sh`.
8. **[OK] No viola el protocolo de `AGENTS.md`:** `ANALYZE` no modifica datos ni estructura (solo `pg_statistic`), no requiere respaldo previo ni `BEGIN…ROLLBACK`.

### 3.3 Mejora concreta

Que la justificación quede **en la evidencia** y que la acción sea **condicional**:

```sql
\echo '=== 3. Decision ==='
SELECT CASE
         WHEN sum(n_dead_tup) > 0
           OR sum(n_mod_since_analyze) > 0
           OR bool_or(last_analyze IS NULL)
         THEN 'ANALYZE justificado: hay tuplas muertas, cambios sin analizar o tablas sin estadisticas'
         ELSE 'Sin accion: estadisticas al dia'
       END AS justificacion
FROM pg_stat_user_tables;

-- ANALYZE de TODA la base (no una lista fija que se olvida de `usuario`)
ANALYZE VERBOSE;
```

Si se prefiere mantener la acción incondicional, entonces el texto del informe debe decir explícitamente "se ejecuta siempre porque `foodstore` se recrea con `createdb -T`", para que no choque con el SPEC L26.

---

## 4. `mantenimiento/restore_test.sh`

### 4.1 Cumplimiento del SPEC

| Requisito del SPEC | ¿Cumple? | Evidencia (línea) |
|---|---|---|
| `foodstore_restore_test` tiene las mismas filas por tabla que `foodstore` | **Sí** | L52-56 conteo de las 5 tablas · L61-62 conteo en destino y en origen · L91 comparación final |
| 0 productos y 0 detalles inválidos | **Sí** | L58-59 `producto(precio<0 OR stock<0)` y `detalle_pedido(cantidad<=0 OR precio_unitario<0)` · L91 |
| Destructivos (`dropdb`, `pg_restore`) solo contra `foodstore_restore_test` | **Sí** | L14 `DESTINO="foodstore_restore_test"` (constante, no configurable por entorno) · L43 `dropdb --if-exists "$DESTINO"` · L48 `createdb "$DESTINO"` · L49 `pg_restore -d "$DESTINO"` · guard L33 |
| `foodstore` nunca se toca | **Sí** | Solo lectura en L62 (`consulta -d "$ORIGEN"`) |
| RTO: cronómetro desde antes de `createdb` hasta pasar las validaciones | **Sí** | L46 `T0` inmediatamente antes de L48 `createdb` · L65 `T1` después de las 3 validaciones (L61-63) · L78 cálculo |
| RPO observado = antigüedad del respaldo usado | **Sí** | L80-84 deriva la fecha del **nombre del archivo** (no del `mtime`, que es lo correcto) |
| Sin contraseñas | **Sí** | L6 lo documenta; L15 `-w`; sin `PGPASSWORD` en el archivo |
| Usa el último respaldo | **Sí** | L36 `ls -t .../foodstore_*.dump \| head -n 1` |
| Salida como evidencia | **Sí** | L19-22 `tee -a "$EVID"` a `evidencias/restore_test_salida.txt` (existe, con RTO 3,19 s y RPO 680 s) |

### 4.2 Problemas y riesgos

1. **[Medio] Compara contra la `foodstore` viva, no contra el conteo guardado antes del respaldo.** El SPEC L27 dice que el conteo previo "es la referencia para validar la restauración", y ese archivo existe (`evidencias/conteo_antes_respaldo.txt`, con `current_database=foodstore` y fecha 20:01:20). El script lo ignora y compara con el estado actual (L62). Consecuencia: si `foodstore` recibe escrituras entre el respaldo y el simulacro, la validación da `DIFERENTE` **aunque la restauración sea perfecta** (falso negativo que arruina el RTO/RPO del simulacro). Hoy no se manifestó porque el respaldo es de 20:02:59 y el simulacro de 20:10/20:14 sin cambios intermedios — es una bomba de tiempo, no un error actual.
2. **[Medio] No confirma con `SELECT current_database()` sobre el destino antes de `pg_restore`.** El SPEC L25 lo pide explícitamente. El guard de L33 compara dos constantes del propio script (útil, pero no consulta al motor), y `maintenance.sql` sí lo hace (su L6). Un `consulta -d "$DESTINO" -c "SELECT current_database()"` entre L48 y L49 cerraría el requisito.
3. **[Bajo] La consulta de inválidos no está protegida con `|| fallar`** (L63). Si la conexión falla o falta una tabla en el destino, `PROD_INV`/`DET_INV` quedan vacíos y el script reporta "las validaciones no coinciden" (L96) en lugar de la causa real. Las otras dos consultas (L61-62) sí están protegidas — la inconsistencia es lo que llama la atención.
4. **[Bajo] El log de fallo no dice qué respaldo falló** (L28: solo `FALLA | motivo`), a diferencia del de OK (L93: `dump=... | rto_s=... | edad_respaldo_s=...`). Si un simulacro falla, no se puede correlacionar con el dump.
5. **[Bajo] `pg_restore` sin `--exit-on-error`** (L49): ante un error de restauración sigue procesando el resto del archivo antes de fallar. Agregarlo hace que el `fallar` llegue antes y con el error original.
6. **[Bajo] El "último respaldo" puede no ser el último generado.** `ls -t foodstore_*.dump` (L36) ignora cualquier dump con otro nombre; combinado con `DB_NAME` configurable en `backup_foodstore.sh` (su L12), el RPO informado puede corresponder a un archivo más viejo sin que nada lo advierta. También depende del `mtime`, que cambia si alguien copia o toca el archivo.
7. **[Bajo] El parseo del nombre no está defendido** (L81-84): si el nombre no respeta `foodstore_AAAAMMDD_HHMMSS`, `date -d` devuelve vacío y `$(( ... - EPOCH_DUMP ))` aborta con un error de aritmética poco claro. El glob de L36 hace que hoy sea improbable, pero es un supuesto no verificado.
8. **[Bajo] `: > "$EVID"` (L21) trunca la evidencia del run anterior** al arrancar. Si el run nuevo falla temprano (p. ej. L43), se pierde la evidencia buena previa. Nombrar la evidencia con timestamp lo evita.
9. **[OK] El `tr -d '\r'` de L24 resuelve un bug real y está documentado.** `evidencias/restore_test_intento1_crlf.txt` muestra el síntoma (mismo resultado, con `\r` incrustado entre columnas); la salida corregida está en `restore_test_salida.txt`. La solución es la correcta para `psql` en Windows.
10. **[OK] Compatibilidad Git Bash verificada:** `date +%s.%N` (sí), `stat -c %s` (sí), `ls -t` con glob sin coincidencias (devuelve rc=2 y salida vacía, pero L37 lo maneja bien), `paste` con sustitución de procesos `<(...)` (sí, el shebang es `bash`, no `sh`). `.gitattributes` fija `*.sh` en LF. Los dos `.sh` están en el índice como `100644`, pero en Git Bash de esta máquina son ejecutables (`test -x` → sí, `core.filemode=false`); un clon en Linux/macOS necesitaría `chmod +x`.
11. **[OK] La restauración no arrastra `CREATE DATABASE`** (no se usa `pg_dump -C`), así que `pg_restore -d` sobre una base recién creada es la secuencia correcta, y `--no-owner --no-privileges` evita fallos por roles inexistentes en otra PC.

### 4.3 Mejora concreta

Comparar contra la referencia correcta y confirmar la base destino:

```bash
createdb "${CONN[@]}" "$DESTINO" || fallar "createdb $DESTINO"

# SPEC L25: confirmar contra el motor, no contra una constante
BASE_ACTUAL="$(consulta -d "$DESTINO" -c 'SELECT current_database();')" || fallar "no se pudo consultar $DESTINO"
[ "$BASE_ACTUAL" = "$DESTINO" ] || fallar "el destino no es $DESTINO (es $BASE_ACTUAL)"

pg_restore "${CONN[@]}" -d "$DESTINO" --no-owner --no-privileges --exit-on-error "$DUMP" || fallar "pg_restore"

read -r PROD_INV DET_INV <<< "$(consulta -d "$DESTINO" -c "$SQL_INVALIDOS")" || fallar "validacion de invalidos"
```

Y para el falso negativo: si existe `evidencias/conteo_antes_respaldo.txt`, comparar contra ese conteo (el del momento del respaldo) y usar la `foodstore` viva solo como dato informativo adicional.

---

## 5. Tabla resumen

| Archivo | ¿Cumple el SPEC? | Hallazgos principales |
|---|---|---|
| `backup_foodstore.sh` | **Sí (4/4 requisitos de respaldo)** con observaciones | [Bajo] no valida tamaño > 0 antes de loguear `OK` (L30-31) · [Bajo] la línea de ERROR no incluye `archivo`/`bytes` (L39) · [Bajo] sin rotación (~3,4 GB/año) · [Bajo] `ERR_TMP` fijo (L23) · [Bajo] `CODIGO=$?` frágil (L36) · [Bajo] `DB_NAME` configurable desalinea a `restore_test.sh` · conteo previo de filas: lo hace el README a mano, no el script · **[OK]** `-Fc`, nombre con fecha, `-w`/pgpass, borrado del incompleto y `exit 1` |
| `health_check.sql` | **Sí (4/4 controles)** | [Medio] el control 3 muestra `n_live_tup=0` y autovacuum vacío en una base copiada con `createdb -T` → parece vacía (falta `reltuples`) · [Bajo] `pct_muertas` sale vacío en vez de 0 (L29) · [Bajo] sin `ON_ERROR_STOP` (sale 0 con salida incompleta) · [Bajo] no emite veredicto/umbral · **[OK]** solo lectura, filtro de `pg_stat_activity` correcto, textos ASCII |
| `maintenance.sql` | **Sí, parcial en "justificación"** | [Medio] `usuario` fuera del `ANALYZE` (L35; evidencia: sigue con `reltuples=-1` y sin `last_analyze`) · [Medio] `ANALYZE` incondicional contra el SPEC L26 (el DESPUÉS muestra `n_dead_tup` 0-2, muy por debajo del umbral) · [Bajo] la justificación está en un comentario, no en la evidencia · [Bajo] `\quit` aborta con código 0 · [Bajo] sin camino condicional de `VACUUM` · **[OK]** guard `current_database()` correcto, `pg_stat_clear_snapshot()`, sin `VACUUM FULL` |
| `restore_test.sh` | **Sí, con observaciones** | [Medio] valida contra la `foodstore` viva y no contra `conteo_antes_respaldo.txt` (SPEC L27) → falso negativo si hay escrituras post-respaldo · [Medio] falta `SELECT current_database()` sobre el destino antes del `pg_restore` (SPEC L25) · [Bajo] L63 sin `\|\| fallar` (error real enmascarado como "no coinciden") · [Bajo] el log de FALLA no incluye el dump · [Bajo] sin `--exit-on-error` · [Bajo] RPO depende de un glob/`mtime` · **[OK]** RTO/RPO bien medidos, destructivos acotados a `foodstore_restore_test`, `tr -d '\r'` correcto, `-w`/pgpass |

## 6. Cosas que revisé y están bien (para no inventar problemas)

- **Contraseñas:** ninguno de los 4 archivos contiene credenciales; los dos `.sh` usan `-w` y dependen de `pgpass.conf`, y el README (L20-23) genera ese archivo fuera del repo con `read -s`. `.gitignore` cubre `.env`, `*.dump`, `*.backup`.
- **`foodstore`:** en los cuatro scripts no hay una sola operación que escriba o elimine la base principal. Los destructivos de `restore_test.sh` usan una constante hardcodeada (`foodstore_restore_test`), no una variable de entorno, lo que impide apuntarlos mal por accidente.
- **CRLF:** `.gitattributes` (`*.sh text eol=lf`) previene el fallo de shebang en Git Bash; los `.sql` se sirven con CRLF y `psql` los procesa sin problema (lo confirma la evidencia). No es un problema.
- **`CODIGO=$?` en la rama `else`:** funciona (verificado en bash 5.3). Solo lo marco como frágil, no como error.
- **`\gset` + `\if` en `maintenance.sql`:** la lógica del guard es correcta (`t`/`f` son valores válidos para `\if`), y `psql` 17 los soporta.
- **`ls -t` sin coincidencias:** devuelve código 2 y salida vacía; el script lo detecta por la cadena vacía (L37) y no por el código, así que no hay falso OK.
