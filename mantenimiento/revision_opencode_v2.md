# Revisión OpenCode v2 — TP Unidad 6 (mantenimiento)

**Revisor:** OpenCode (rol: revisar y proponer, no ejecutar) · **Fecha:** 2026-11-07
**Contra:** `mantenimiento/SPEC_U6.md` (versión nueva), `AGENTS.md`, `README.md`
**Evidencia usada:** `logs/backup_foodstore.log`, `logs/restore_test.log`, `evidencias/restore_test_20261107_223233.txt`, `evidencias/restore_test_20261107_223501.txt`, `evidencias/maintenance_v3_foodstore.txt`, `evidencias/maintenance_v3_restore_test.txt`, más los artefactos en `backups/` (`.conteo` y `.sha256`).

**Método:** revisión estática de los 4 archivos + comprobaciones locales inocuas (bytes iniciales y fin de línea de los 4 archivos, `bash -n` de los dos `.sh` en Git Bash, lectura del `.conteo`/`.sha256` en disco). **Sin `psql`, `pg_dump`, `pg_restore`, `createdb` ni `dropdb`.** Lo que solo se ve en el motor se contrastó con la evidencia ya ejecutada.

**Severidad:** [Alto] rompe el SPEC o pone en riesgo `foodstore` · [Medio] debilita la evidencia o la validez del resultado · [Bajo] robustez/trazabilidad · [OK] verificado y correcto.

---

## 1. `mantenimiento/backup_foodstore.sh`

### 1.1 Cumplimiento del SPEC

| Requisito del SPEC | ¿Cumple? | Línea / evidencia |
|---|---|---|
| R1 — Formato custom `-Fc` | **Sí** | L52 `pg_dump "${CONN[@]}" -d "$DB_NAME" -Fc -f "$ARCHIVO"` |
| R2 — Nombre `foodstore_AAAAMMDD_HHMMSS.dump` | **Sí** | L27 `FECHA="$(date +%Y%m%d_%H%M%S)"` + L28-29 `"$BACKUP_DIR/${DB_NAME}_${FECHA}.dump"` (L17 `DB_NAME=foodstore` por defecto) |
| R3 — Huella `.conteo` generada **antes** del respaldo | **Sí** | L44-48 (el `psql -f conteo_referencia.sql` va antes del `pg_dump` de L52); `.conteo` real en `backups/foodstore_20261107_222858.conteo` con las 10 claves |
| R4 — Verificación inmediata `pg_restore -l` | **Sí** (y más estricto) | L57 `TOC=$(pg_restore -l ... | grep -c '^[0-9]')`; log L4 `objetos_toc=54` |
| R5 — SHA256 en `.sha256` formato `sha256sum` | **Sí** | L62-63; archivo real: `a4819d…d272e0d *foodstore_20261107_222858.dump` (el `*` es modo binario de `sha256sum`, válido para `-c`) |
| R6 — Log con PASS/FAIL, bytes, hash, objetos del TOC, nombre del `.conteo` y tiempo | **Sí, con matiz en el tiempo** | L66 `... | PASS | base= | archivo= | bytes= | sha256= | objetos_toc= | conteo= | segundos=` (log L4/L6). El `segundos` mide solo `pg_dump` (L51-53), no el script completo |
| R7 — Si falla: `FAIL`, borra incompletos, exit ≠ 0 | **Sí** | L35-42: `rm -f "$ARCHIVO" "$CONTEO" "$HASH" "$ERR_TMP"` (L38), log `FAIL` (L39), `exit 1` (L41). Evidencia: log L5/L7 |
| Sin contraseñas (pgpass / sesión) | **Sí** | L8 lo documenta; L18 `-w` (nunca pide clave); sin `PGPASSWORD` en el archivo |
| `foodstore` nunca se elimina ni reemplaza | **Sí** | Solo `pg_dump` (lectura, L52) y `psql` con un script de solo `SELECT` (L46). No hay `dropdb`/`pg_restore`/`createdb` |
| Condición de éxito (código 0 + `.dump` > 0 + `pg_restore -l` ok + `.sha256` + `PASS` con tamaño y hash) | **Sí** | L56 `[ -s "$ARCHIVO" ]`, L58 `[ "$TOC" -gt 0 ]`, L63, L66, L71 `exit 0` |

### 1.2 Problemas y riesgos reales

1. **[Medio] El detalle de error del log no es legible (encoding).** El `detalle` se copia crudo desde `stderr` (L37 → L39) y en el log versionado quedó `psql: error: fall� la conexi�n al servidor en �localhost�…` (log L2, L5, L7). El resto del log es ASCII/UTF-8, así que el archivo mezcla codificaciones y el motivo del `FAIL` —que el SPEC pide registrar— no se puede citar tal cual en el informe. *Mejora:* normalizar el detalle antes de escribirlo (o forzar el encoding del cliente) y verificar en la próxima corrida.
2. **[Bajo] `segundos=` mide solo `pg_dump`.** L51/L53 envuelven únicamente el `pg_dump`; la huella (L46), el `pg_restore -l` (L57) y el hash (L62-63) quedan afuera. Evidencia: el `.dump` se llamó `…222858` y el `PASS` se registró a las `22:29:01` (log L6) → ~3 s reales contra `segundos=2`.
3. **[Bajo] `TAMANO` y `SHA` no tienen guarda.** L61 `stat -c %s` y L62 `sha256sum` no llevan `|| fallar`. Si fallan, el script escribe `PASS` con `bytes=`/`sha256=` vacíos y sale con 0: la condición de éxito del SPEC se informa, no se verifica.
4. **[Bajo] Colisión en el mismo segundo.** El sello tiene resolución de segundos (L27) y `ERR_TMP` usa el mismo sello (L32). Dos corridas en el mismo segundo comparten nombre y, peor, el `rm -f` de L38 de la corrida fallida borra el `.dump`/`.conteo`/`.sha256` de la corrida buena anterior. No es teórico que dos corridas caigan en el mismo segundo: el log L6 y L7 son ambas de `22:29:01` (con bases distintas).
5. **[Bajo] La comprobación de L58 es inalcanzable.** `grep -c` imprime `0` pero devuelve estado 1, y con `pipefail` (L11) eso dispara el `fallar pg_restore_l` de L57; el `[ "$TOC" -gt 0 ]` de L58 nunca se evalúa. El resultado es un `FAIL` correcto con un `paso=` que puede no ser el real.
6. **[Bajo] Ventana entre la huella y el dump.** El SPEC manda generar el `.conteo` antes del respaldo y el script lo hace (L46 → L52), pero si `foodstore` recibe escrituras en ese intervalo, el `.conteo` deja de representar el `.dump` y el simulacro fallará por `DIFERENTE` sin que la restauración tenga la culpa. Hoy no se manifestó (mismo segundo: `22:28:58`), y `foodstore` es una copia de laboratorio. *Mejora:* recalcular el conteo después del dump y avisar si cambió.
7. **[Bajo] Sin retención.** Sigue sin rotación (ya señalado en la v1). Con 9.428.332 bytes por corrida (log L4/L6) y frecuencia diaria son ~3,4 GB al año.
8. **[Bajo] Falta evidencia de las ramas de fallo de `pg_dump` y `pg_restore -l`.** Los dos `FAIL` del log son `paso=conteo` (L5, L7). La rama comparte `fallar` (L35-42), así que el comportamiento es el mismo, pero para la defensa oral conviene una prueba controlada (por ejemplo, `pg_restore -l` sobre una copia truncada del `.dump`) registrada en el informe.
9. **[OK] Compatibilidad Git Bash/Windows verificada:** `stat -c %s`, `sha256sum` y `date +%Y%m%d_%H%M%S` funcionan (evidencia del log); rutas entrecomilladas y `DIR` resuelto desde la ubicación del script (L21) → corre desde cualquier carpeta (L9); el `.sha256` se genera con `cd "$BACKUP_DIR"` (L63), así que `sha256sum -c` funciona sin importar el cwd; los dos `.sh` están en LF y sin BOM (comprobado byte a byte) y `.gitattributes` fija `*.sh text eol=lf`.
10. **[OK] `DB_NAME` configurable (L17) no rompe la trazabilidad:** el log registra `base=$DB_NAME` (L66) y `restore_test.sh` solo levanta `foodstore_*.dump` (su L41), así que un respaldo de otra base no se confunde con el de `foodstore`.

### 1.3 Mejora concreta

Que `PASS` signifique "todo medido y verificado", no solo "`pg_dump` salió 0":

```bash
INICIO=$(date +%s)                       # antes del conteo, no antes del dump
# ...
TAMANO=$(stat -c %s "$ARCHIVO") || fallar stat_tamano 1
SHA=$(sha256sum "$ARCHIVO" | cut -d' ' -f1) || fallar sha256 1
[ -n "$SHA" ] || fallar sha256_vacio 1
```

Y, si se puede sumar una línea, `[ -e "$ARCHIVO" ] && fallar ya_existe 1` antes del `pg_dump` para cerrar el hallazgo 4.

---

## 2. `mantenimiento/restore_test.sh`

### 2.1 Cumplimiento del SPEC

| Requisito del SPEC (L13 y reglas L27-30) | ¿Cumple? | Línea / evidencia |
|---|---|---|
| Verificación SHA256 **antes** de restaurar | **Sí** | L52-54: `sha256sum -c --quiet` en el directorio del dump, mucho antes del `dropdb` (L69); evidencia L3 de ambos `.txt` |
| Autorización escrita registrada en el log | **Sí** | L61-66; `restore_test.log` L5 `… | AUTORIZADO | usuario=beluu | accion=dropdb foodstore_restore_test` |
| `current_database()` del destino confirmada | **Sí en código, no en la evidencia** | L76-77 compara contra el motor; el `.txt` de la corrida buena no contiene esa confirmación |
| `pg_restore --exit-on-error` | **Sí** | L78-79 `--exit-on-error --no-owner --no-privileges` |
| Huella restaurada = respaldo | **Sí** | L57 (lee el `.conteo` **del respaldo**, no la base viva), L83, L106-108, L129; evidencia L7-16, 10/10 `OK` |
| 8 indicadores de integridad en 0 | **Sí** | L86-99 (los 8 exactos del SPEC) + L111; evidencia L18-25, todos `OK` |
| Destructivos solo sobre `foodstore_restore_test` | **Sí** | L17 constante no configurable por entorno; `dropdb` L69, `createdb` L74, `pg_restore -d` L78 |
| `foodstore` nunca se toca ni se consulta | **Sí** | L5-6; `ORIGEN` (L16) solo se usa en el guard L38 — no hay ninguna conexión a `foodstore` |
| RTO desde antes de `createdb` hasta pasar las validaciones | **Sí** | L72 `T0` inmediatamente antes de L74; L101 `T1` después de las dos validaciones; L114-115. Evidencia L27-28: 5,97 s (< 15 min) |
| RPO = antigüedad del respaldo usado | **Sí, con matiz** | L118-121 deriva del **nombre** del archivo (correcto, no del `mtime`); evidencia L29: 435 s (< 24 h) — ver 2.2.2 |
| Sin contraseñas | **Sí** | L7, L18 `-w`, sin `PGPASSWORD` |
| Exit ≠ 0 ante cualquier falla | **Sí** | L31-35 (todas las ramas pasan por `fallar`) |

### 2.2 Problemas y riesgos reales

1. **[Medio] La confirmación de `current_database()` no queda en la evidencia.** Es el único ítem de la columna "evidencia" del SPEC que no se puede mostrar: L76-77 lo chequea, pero `restore_test_20261107_223501.txt` no tiene ninguna línea con la base confirmada. Quien lea el `.txt` no puede verificar que `pg_restore` apuntó al destino correcto; solo lo puede deducir del código.
2. **[Bajo] El RPO informado incluye la espera de autorización.** Se calcula al final (L121), después de las validaciones, y entre el inicio (`22:35:01`, evidencia L1) y la autorización (`22:36:06`, L4) pasaron 65 s. De los 435 s informados, ~72 s son espera humana: la línea lo aclara (L29), pero infla la métrica que el SPEC define como "antigüedad al momento del simulacro". *Mejora:* capturar la edad junto con `T0` y mostrar ambas.
3. **[Bajo] `dropdb … 2>/dev/null` (L69) oculta la causa.** Si falla por una conexión abierta (DBeaver, el gotcha conocido del proyecto), el mensaje es "no se pudo borrar" y hay que adivinar. *Mejora:* mandar `stderr` a `EVID`/temporal y concatenarlo al motivo.
4. **[Bajo] "Último respaldo" por `mtime`, no por el sello.** `ls -t` (L41) elige el archivo más recientemente tocado: si alguien copia un dump viejo a `backups/`, pasa a ser "el último". *Mejora:* `ls -1 ... | sort -r | head -1` (los nombres ya son ordenables).
5. **[Bajo] El parseo del nombre no está defendido.** L118-121 asume `foodstore_AAAAMMDD_HHMMSS`; si no coincide, `date -d` devuelve vacío y `$(( … - EPOCH_DUMP ))` aborta con un error de aritmética de bash, **sin** línea `FAIL` en el log. *Mejora:* validar con `[[ "$STAMP" =~ ^[0-9]{8}_[0-9]{6}$ ]]` y `fallar` si no cumple.
6. **[Bajo] La autorización no distingue humano de variable de entorno.** Con `CONFIRMAR=foodstore_restore_test` (L61) el script no pregunta y el log igual escribe "autorizado por beluu" (L65-66). Está documentado (L8), pero para el SPEC ("autorización escrita") conviene registrar el origen: `origen=interactivo|variable`.
7. **[Bajo] El orden de los 8 indicadores no es determinista.** L86-98 es un `UNION ALL` sin `ORDER BY`; la evidencia (L18-25) los muestra en un orden distinto al del SQL. No afecta el veredicto (etiqueta y valor viajan juntos) pero desconcierta al comparar evidencia contra código. *Mejora:* `ORDER BY 1`, o dejarlo y explicarlo.
8. **[Bajo] El simulacro no pone a prueba el RPO de 24 h.** El respaldo usado tenía 7 minutos (evidencia L2 y L29), así que el objetivo se cumple de forma trivial; además el log de respaldos muestra corridas solo el 2026-10-28 y el 2026-11-07. *Mejora:* aclarar en el informe que 435 s es una cota inferior, o correr el simulacro con el respaldo más viejo de la ventana.
9. **[OK] La protección de seguridad funciona de verdad.** `DESTINO` es constante y no toma valor del entorno (L17), la autorización se registra **antes** del `dropdb` (L66 vs L69) y la corrida no autorizada dejó `FAIL` en el log (L4) con evidencia (`restore_test_20261107_223233.txt` L4). El guard L38 compara dos constantes (es tautológico), pero la protección real es que el destino no es configurable.
10. **[OK] `psql | tr -d '\r'` con `pipefail` propaga el error real.** L10 + L28: si `psql` falla, la función `consulta` devuelve ≠ 0 y los `|| fallar` de L83/L99 disparan. Es lo que evita el error enmascarado que marcaba la v1.
11. **[OK] Ya no hay falso negativo por escrituras posteriores.** La huella se compara contra el `.conteo` que se generó junto al `.dump` (L43, L57, L129), no contra `foodstore` viva: el hallazgo [Medio] 4.2.1 de la v1 quedó resuelto.
12. **[OK] Git Bash:** `date +%s.%N`, `paste <(...)`, `sha256sum -c`, `read -r -p` y `stat -c` están todos confirmados por la corrida real; `.sh` en LF y sin BOM (comprobado byte a byte).

### 2.3 Mejora concreta

Cerrar el único ítem de evidencia que falta (hallazgo 1), con una línea:

```bash
BASE_ACTUAL="$(consulta -d "$DESTINO" -c 'SELECT current_database();')" || fallar "no se pudo consultar $DESTINO"
[ "$BASE_ACTUAL" = "$DESTINO" ] || fallar "el destino no es $DESTINO (es $BASE_ACTUAL)"
out "Destino confirmado por el motor: current_database() = $BASE_ACTUAL"
```

---

## 3. `mantenimiento/maintenance.sql`

### 3.1 Cumplimiento del SPEC

| Requisito del SPEC (L12, L32-36) | ¿Cumple? | Línea / evidencia |
|---|---|---|
| Registra tuplas muertas | **Sí** | L26 `s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze`; L90, L99; evidencia `maintenance_v3_foodstore.txt` L14-21 y L37-45 |
| Registra último autovacuum/autoanalyze (y vacuum/analyze) | **Sí** | L27 `s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze`; L126 |
| Registra la acción tomada **con su justificación** en la salida | **Sí** | L75-83 (`\echo 'Decision: ANALYZE justificado…'` / `'sin accion, estadisticas al dia'`) y L109-118; evidencia `maintenance_v3_restore_test.txt` L35-38 y `…_foodstore.txt` L35 |
| `ANALYZE`/`VACUUM` solo si las métricas superan el umbral (`threshold + scale_factor * filas`) | **Parcial** | Umbrales correctos en L43-44 y L91-92; `VACUUM` es **por tabla** (L111-115). `ANALYZE` es condicional pero analiza **las 6** (L80) y además dispara por "SIN ESTADISTICAS" (L47) aunque `n_mod` no supere el umbral (ver 3.2.1 y 3.2.2) |
| Nunca `VACUUM FULL` | **Sí** | L4, L87 y L119 lo declaran; el único verbo ejecutable es `format('VACUUM (VERBOSE) %I', …)` (L111) — no hay ninguna sentencia `VACUUM FULL` |
| Estado antes y después con los 4 timestamps | **Sí** | Antes L24-30, después L123-129; evidencia `…_restore_test.txt` L14-22 vs L71-78 (se ve el `last_analyze` nuevo) |
| Guard de base (`SELECT current_database()`) | **Sí** | L8-12 `NOT IN ('foodstore','foodstore_restore_test')` + `\if`/`\quit`; evidencia L1 de ambos `.txt` |

### 3.2 Problemas y riesgos reales

1. **[Medio] El `ANALYZE` no es selectivo.** El diagnóstico marca 2 tablas pendientes y la acción analiza las 6 (L80 `ANALYZE VERBOSE categoria, cliente, producto, pedido, detalle_pedido, usuario;`). En la evidencia (`maintenance_v3_restore_test.txt` L35) el script decide "2 de 6" y sin embargo re-analiza `cliente`, `producto`, `pedido` y `detalle_pedido`, que están `OK` con `n_mod_since_analyze = 0` (L27-30). Contra el SPEC L34 ("se ejecutan solo cuando las métricas superan los umbrales"), esas 4 tablas no justifican la acción. El `VACUUM` ya resuelve esto bien con `\gexec` (L111-115): es el patrón a copiar.
2. **[Medio] La regla "SIN ESTADISTICAS" agrega un criterio que el SPEC no enuncia.** L47 (y L64) deciden `ANALYZE` cuando nunca se analizó, aunque `n_mod_since_analyze` esté por debajo del umbral: en la evidencia, `categoria` y `usuario` tienen `n_mod` 5 y 3 contra umbrales 50,5 y 50,3 (L31-32). Es defendible (sin estadísticas no hay estimaciones) y está documentado en el encabezado (L34-37), pero un corrector estricto puede leerlo como "acción sin superar el umbral". *Decisión:* o se agrega esa regla al SPEC/informe, o se restringe la acción al umbral.
3. **[Medio] No hay `\set ON_ERROR_STOP on`.** No aparece en el archivo (verificado con grep). Si `ANALYZE`/`VACUUM` falla (permisos, lock, `VACUUM` dentro de transacción), `psql` sigue, la sección 4 muestra los timestamps viejos y el proceso sale con 0: una tarea semanal no detectaría el fallo y la evidencia parecería válida. Es el único de los cuatro archivos sin esa protección (el backup la tiene en L46 y el restore en L28).
4. **[Bajo] El aborto del guard sale con código 0.** `\quit` (L11) termina `psql` con estado 0: "abortado por base no permitida" es indistinguible de "corrió bien" para un programador de tareas.
5. **[Bajo] `\echo 'Base:' :DBNAME` (L13) muestra el dato del cliente, no el del motor.** `:DBNAME` es lo que se pasó con `-d`; si alguien se conecta sin `-d`, es el nombre de usuario. El valor del servidor ya se consultó en L8: conviene capturarlo con `\gset` y usar ese.
6. **[Bajo] No se verifica que existan las 6 tablas.** Si el esquema está incompleto, la subconsulta de L62-72 devuelve 0 filas, `coalesce(bool_or(...), false)` (L59) da `f` y el script informa "sin accion, estadisticas al dia" con `total = 0`. Un esquema roto se ve sano.
7. **[Bajo] Sin aviso sobre transacciones.** `VACUUM` y `ANALYZE` no corren dentro de un bloque de transacción, y `AGENTS.md` (protocolo, paso 2) pide ensayar los scripts de escritura con `BEGIN…ROLLBACK`. Si alguien corre `psql -1 -f maintenance.sql` o lo envuelve en `BEGIN`, el `VACUUM` de L115 falla y, sin `ON_ERROR_STOP`, el script sigue como si nada. *Mejora:* una línea en el encabezado: "sin `-1` y sin `BEGIN`".
8. **[Bajo] Cosmético:** `SELECT pg_stat_clear_snapshot();` (L122) imprime una tabla de una fila en la evidencia (L50-53) y el `\echo` de L76 deja "2 de 6 )" con espacio antes del paréntesis (evidencia L35).
9. **[OK] El guard de base es correcto y es el que exige el SPEC.** Toma `current_database()` del motor (no una constante), permite exactamente `foodstore` y `foodstore_restore_test`, y la evidencia muestra las dos corridas legítimas (L1 de cada `.txt`). Cualquier otra base, incluida `bd2_tp3` o `bd2_proyecto`, cae en el `\quit`.
10. **[OK] El `VACUUM` condicional está bien resuelto:** se construye con `format('VACUUM (VERBOSE) %I', s.relname)` (L111) para citar identificadores, se ejecuta solo sobre las tablas sobre el umbral (L114-115) y **no** se ejecuta cuando no hace falta (evidencia `…_foodstore.txt` L47 y `…_restore_test.txt` L63).
11. **[OK] El "después" es real, no una foto cacheada:** `pg_stat_clear_snapshot()` (L122) + la comparación entre L14-22 y L71-78 de la evidencia muestran el `last_analyze` nuevo tras la acción de L80.
12. **[OK] `greatest(c.reltuples, 0)` (L44, L66, L92)** evita umbrales negativos en tablas nunca analizadas (`reltuples = -1`), sin maquillar el dato que se muestra en la columna `filas_estimadas`.
13. **Nota de método:** los umbrales usan los `current_setting` globales; si alguna tabla definiera `reloptions` de autovacuum, el cálculo no las respetaría. Verifiqué `food-store/schema.sql` y hoy no define ninguna, así que no afecta el resultado.

### 3.3 Mejora concreta

Alinear el `ANALYZE` con la regla del SPEC, reutilizando el patrón que ya usa el `VACUUM`:

```sql
\if :dec_hay_pendientes
  \echo 'Decision: ANALYZE justificado (tablas pendientes:' :dec_pendientes 'de' :dec_total ')'
  SELECT format('ANALYZE VERBOSE %I', s.relname)
  FROM pg_stat_user_tables s JOIN pg_class c ON c.oid = s.relid
  WHERE s.relname IN ('categoria','cliente','producto','pedido','detalle_pedido','usuario')
    AND ( (s.last_analyze IS NULL AND s.last_autoanalyze IS NULL)
          OR s.n_mod_since_analyze > current_setting('autovacuum_analyze_threshold')::numeric
             + current_setting('autovacuum_analyze_scale_factor')::numeric * greatest(c.reltuples,0) ) \gexec
\else
```

Y `\set ON_ERROR_STOP on` como primera línea ejecutable (después del encabezado).

---

## 4. `mantenimiento/conteo_referencia.sql`

### 4.1 Cumplimiento del SPEC

| Requisito del SPEC (L19) | ¿Cumple? | Línea / evidencia |
|---|---|---|
| Filas por tabla | **Parcial: 5 de 6** | L9-13 cuenta `categoria`, `cliente`, `producto`, `pedido`, `detalle_pedido`; **falta `usuario`** (3 filas según `maintenance_v3_foodstore.txt` L21) |
| Total facturado = `sum(cantidad * precio_unitario)` | **Sí** | L16 `coalesce(sum(cantidad * precio_unitario), 0)::text FROM detalle_pedido`; `.conteo` L6 `total_facturado 629621805.75` = evidencia L12 |
| Estructura: tablas, vistas, restricciones, índices | **Sí** | L18-24 (`pg_tables`, `pg_views`+`pg_matviews`, `pg_constraint` join `pg_namespace`, `pg_indexes`, todo filtrado a `public`) |
| Orden determinista (comparación línea a línea) | **Sí** | L26 `ORDER BY orden`; es lo que hace válido el `=` de `restore_test.sh` L129 |
| Solo lectura (se ejecuta sobre `foodstore`) | **Sí** | Todas las ramas son `SELECT`; no hay DML ni DDL |

### 4.2 Problemas y riesgos reales

1. **[Medio] La huella no incluye `usuario`.** El SPEC dice "filas por tabla" y la base tiene 6 tablas (`tablas 6` en el propio `.conteo`, L7; `maintenance_v3_foodstore.txt` L21 muestra `usuario` con 3 filas), pero L9-13 solo cuentan 5. Un restore que perdiera las 3 filas de `usuario` pasaría la validación: la tabla sigue existiendo (`tablas 6`) y los demás contadores no cambian. Es el mismo tipo de omisión que la v1 marcó para el `ANALYZE` (3.2.1) y que ya se corrigió en `maintenance.sql` (L55); acá quedó.
2. **[Bajo] Los 4 contadores de estructura no cubren triggers, funciones ni secuencias.** En este esquema las reglas R1/R2 viven en triggers (`food-store/restricciones.sql`): un restore al que le falten los triggers pasaría la huella y también los 8 indicadores (que son consultas de datos, no de comportamiento). *Mejora:* sumar `count(*) FROM pg_trigger WHERE NOT tgisinternal`.
3. **[Bajo] No hay marca de formato/versión.** En `backups/` convive un `.conteo` de 5 líneas (`foodstore_20261028_211058.conteo`) con los nuevos de 10. Si `restore_test.sh` llegara a emparejar un `.conteo` viejo con la salida actual, el `paste` de L106-107 desalinea columnas y el resultado es un `DIFERENTE` confuso (el script falla igual, pero no explica por qué). *Mejora:* primera línea `formato 2` y validarla, o verificar la cantidad de líneas antes de comparar.
4. **[OK] `coalesce(sum(...), 0)` (L16)** mantiene la huella comparable si `detalle_pedido` estuviera vacía (sin `NULL` que rompa el `=`).
5. **[OK] Filtrado a `public` en los 4 contadores (L18-24).** Evita que objetos de otros esquemas (o de extensiones) ensucien la huella y la vuelvan dependiente del entorno.
6. **Nota:** `indices` incluye los índices que respaldan PK/unique, así que solapa con `restricciones`. Para una huella no es un problema (solo tiene que ser estable en ambos lados), pero conviene saberlo si alguien pregunta por los números `13` y `18`.

### 4.3 Mejora concreta

Agregar la tabla que falta (una línea, renumerando el resto):

```sql
UNION ALL SELECT 6, 'usuario', count(*)::text FROM usuario
```

---

## 5. Lo que la v2 ya resolvió de la revisión anterior

| Hallazgo v1 | Estado en la versión nueva |
|---|---|
| El conteo previo lo hacía el README a mano | **Resuelto:** el script genera el `.conteo` (L44-48) y lo nombra en el log (L66) |
| No validaba `.dump` > 0 | **Resuelto:** L56 |
| No verificaba el archivo con `pg_restore -l` | **Resuelto:** L57-58 |
| La línea de `FAIL` no decía qué archivo falló | **Resuelto:** L39 incluye `archivo=` |
| No había SHA256 | **Resuelto:** L62-63 y verificación previa en `restore_test.sh` L52-54 |
| El simulacro comparaba contra `foodstore` viva (falso negativo) | **Resuelto:** compara contra el `.conteo` del respaldo (L57, L83, L129) |
| Faltaba `current_database()` del destino | **Implementado** (L76-77), pero no queda en la evidencia (2.2.1) |
| `pg_restore` sin `--exit-on-error` | **Resuelto:** L78 |
| `ANALYZE` se olvidaba de `usuario` | **Resuelto:** L55 y L80 |
| `ANALYZE` incondicional | **Resuelto:** L75-83 (condicional) — queda el matiz 3.2.1/3.2.2 |
| No había camino de `VACUUM` | **Resuelto:** L109-118, por tabla y con `%I` |
| La justificación estaba solo en comentarios | **Resuelto:** `\echo` (L76-78, L110, L117) |
| `ERR_TMP` fijo / evidencia truncada | **Mejorado:** sello de fecha en `ERR_TMP` (L32) y la evidencia lleva timestamp (L22-23); la colisión queda solo si dos corridas caen en el mismo segundo (1.2.4) |
| Sin `ON_ERROR_STOP` | **Resuelto en los dos `.sh`** (backup L46, restore L28); **pendiente en `maintenance.sql`** |
| Sin rotación de respaldos | **Pendiente** (1.2.7) |

---

## 6. Tabla resumen

| Archivo | ¿Cumple el SPEC? | Hallazgos |
|---|---|---|
| `backup_foodstore.sh` | **Sí** — R1-R7 + reglas de seguridad | [Medio] el `detalle=` del `FAIL` queda ilegible por encoding (log L2/L5/L7) · [Bajo] `segundos` mide solo `pg_dump` (L51-53) · [Bajo] `stat`/`sha256sum` sin guarda (L61-62) · [Bajo] colisión en el mismo segundo y `rm -f` (L27/L32/L38) · [Bajo] L58 inalcanzable por `grep -c`+`pipefail` · [Bajo] ventana huella→dump (L46 vs L52) · [Bajo] sin rotación · [Bajo] sin evidencia de la rama de fallo de `pg_dump`/`pg_restore -l` · **[OK]** `-Fc`, nombre con sello, `.conteo` antes, `pg_restore -l`, SHA256, `FAIL`+borrado+`exit 1`, `-w`/pgpass |
| `restore_test.sh` | **Sí** — los 6 ítems de evidencia + seguridad | [Medio] `current_database()` se chequea (L76) pero no se registra en el `.txt` · [Bajo] el RPO incluye la espera de autorización (L121) · [Bajo] `dropdb 2>/dev/null` oculta la causa (L69) · [Bajo] `ls -t` elige por `mtime` (L41) · [Bajo] parseo del sello sin validar (L118-121) · [Bajo] la autorización no registra su origen (L61-66) · [Bajo] orden no determinista de los 8 indicadores (L86-98) · [Bajo] el RPO medido no pone a prueba las 24 h · **[OK]** SHA antes del `dropdb`, autorización previa en el log, `--exit-on-error --no-owner --no-privileges`, huella contra el `.conteo`, 8 indicadores en 0, RTO 5,97 s |
| `maintenance.sql` | **Sí, parcial en "solo si el umbral lo justifica"** | [Medio] `ANALYZE` de las 6 tablas aunque solo 2 estén pendientes (L80) · [Medio] regla extra "SIN ESTADISTICAS" fuera del texto del SPEC (L47/L64) · [Medio] sin `ON_ERROR_STOP` → fallo silencioso con exit 0 · [Bajo] `\quit` aborta con código 0 (L11) · [Bajo] `Base:` sale de `:DBNAME`, no del motor (L13) · [Bajo] no verifica que existan las 6 tablas (L59-73) · [Bajo] sin aviso de "no usar `-1`/`BEGIN`" · **[OK]** guard `current_database()`, tuplas muertas + 4 timestamps antes y después, `VACUUM` condicional por tabla con `%I`, sin `VACUUM FULL` |
| `conteo_referencia.sql` | **Sí, con una omisión** | [Medio] faltan las filas de `usuario`: 5 de 6 tablas (L9-13) · [Bajo] no cuenta triggers/funciones/secuencias (L18-24) · [Bajo] sin marca de formato/versión · **[OK]** total facturado con la fórmula del SPEC (L16), estructura de 4 componentes, `ORDER BY` determinista (L26), solo lectura |

---

## 7. Notas transversales (para el informe)

- **Frecuencia:** el SPEC titula la tabla "Tareas automatizadas" con frecuencia diaria/semanal, pero no hay ningún artefacto de programación en el repo (ni `cron`, ni Programador de tareas, ni contenedor). La evidencia son corridas manuales (log de respaldos: 2026-10-28 y 2026-11-07). No es un defecto de los cuatro archivos, pero conviene decirlo explícitamente antes de que lo pregunte un corrector.
- **Formato del log:** `backup_foodstore.log` y `restore_test.log` mezclan el formato viejo (`OK`/`ERROR`, L1-L3) con el nuevo (`PASS`/`FAIL`, L4+). Un `grep PASS` no ve las corridas del 28/10. Vale una nota en el informe o rotar el log al cambiar de formato.
- **Duplicación de IA:** este documento es la revisión v2; la v1 (`revision_opencode.md`) y `decisiones_revision.md` quedan como registro de qué se aceptó y qué se pospuso. Los hallazgos [Medio] 3.2.1, 2.2.1 y 4.2.1 de esta revisión son los únicos que tocan el cumplimiento literal del SPEC; el resto son robustez y trazabilidad.
