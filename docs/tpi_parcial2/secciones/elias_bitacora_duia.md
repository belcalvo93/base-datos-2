# Bitácora y DUIA del TPI — Elías Tello (Bloque C: simulacro de desastre y armado del informe)

Material para que Bruno lo integre en `docs/tpi_parcial2/bitacora_ia_tpi.md` y `docs/tpi_parcial2/DUIA_tpi.md`.

## Bitácora

Formato: fecha · quién · herramienta · qué se pidió · qué se aceptó · qué se corrigió o descartó y por qué · cómo se comprobó.

---

### Entrada 1 · 08/11/2026 · Elías Tello · Claude Code

**Qué se pidió:** escribir la especificación `mantenimiento/SPEC_simulacro_desastre.md` y el guion `mantenimiento/simulacro_desastre.sh` del objetivo 8. El desastre se provoca solo sobre la copia `foodstore_desastre`, se restaura desde el último respaldo de la tarea programada, se valida con la huella 11/11 y los 8 indicadores, y se miden RTO y RPO contra las metas de `SPEC_U6.md`. Primero la spec, revisada por el autor, y después el guion.

**Qué se aceptó:** el escenario `DELETE FROM detalle_pedido;` sin `WHERE`; los 3 pedidos registrados con `registrar_pedido` después del respaldo, para que el RPO se pueda medir en filas; reusar `restore_test.sh` sin cambios para la recuperación; restaurar aparte y dejar la base dañada para el análisis; el `MODO=ensayo` con la actividad y el desastre dentro de `BEGIN … ROLLBACK`; la guarda `DO $$ … RAISE EXCEPTION` si `current_database()` no es `foodstore_desastre`; pedir las autorizaciones antes de arrancar el reloj; y comprobar en `logs/backup_foodstore.log` que el respaldo sea un `PASS` con `origen=programada`.

**Qué se corrigió:** al releer el guion antes de ejecutarlo, el ensayo armaba `SELECT 'actividad', SELECT count(*) …`, que es SQL inválido y habría hecho fallar la prueba. Se reemplazó por dos subconsultas escalares (`EXPR_NUEVOS`).

**Qué se descartó:** la IA reemplazó `psql -1` por `BEGIN … COMMIT` explícitos y lo justificó diciendo que `-1` «no aplica a SQL leído de la entrada estándar». Se **descartó la justificación** porque es falsa: probado en el motor con un script que divide por cero, con entrada estándar `-1` también abre una sola transacción (el error siguiente es «transacción abortada… hasta el fin de bloque de transacción»). Se conservó `BEGIN … COMMIT` por un motivo distinto, que la transacción quede visible en el guion igual que el `ROLLBACK` del ensayo, y se corrigió el comentario del guion. La misma prueba mostró que, sin `ON_ERROR_STOP`, `psql` sale con código 0 aunque haya errores: el guion lo usa en todas las consultas. También se descartaron dos propuestas del plan inicial: borrar `pedido` (la consigna del grupo indicaba `detalle_pedido`) y usar un respaldo manual en lugar del de la tarea programada.

**Cómo se comprobó:** `MODO=ensayo` dio ENSAYO OK: 3 pedidos y 6 líneas registrados, el `DELETE` borró 499.269 líneas y el `ROLLBACK` dejó `foodstore_desastre` igual al respaldo (`evidencias/simulacro_desastre_20261108_235631.txt`). Después, `MODO=real` dio PASS con los 6 criterios en OK: RTO 6,16 s, RPO 514 s, 3 pedidos y 6 líneas perdidos y `foodstore` con la misma huella antes y después (`evidencias/simulacro_desastre_20261108_235715.txt`, `evidencias/restore_test_20261108_235721.txt`).

---

### Entrada 2 · 08–09/11/2026 · Elías Tello · Claude Code

**Qué se pidió:** redactar `mantenimiento/informe_post_incidente.md` sin culpables (línea de tiempo, impacto, detección, RTO/RPO contra las metas, datos perdidos y por qué, causa raíz, qué funcionó y qué no, acciones correctivas con responsable), la sección de reproducción en `mantenimiento/README.md` y la fila del objetivo 8 en `docs/tpi_parcial2/matriz_objetivos.md`.

**Qué se aceptó:** la estructura del informe; la causa raíz centrada en el proceso (sentencia destructiva fuera de una transacción y con una cuenta administrativa) y no en una persona; las 4 acciones correctivas con responsable, incluida la mejora de archivado de WAL para bajar el RPO.

**Qué se corrigió:** se separaron las dos mediciones de RTO, que no miden lo mismo: 6,16 s desde la detección (la del objetivo) y 3,63 s de `restore_test.sh`, que arranca en `createdb`. Se aclaró que el RPO de 514 s es bajo solo porque el respaldo tenía 8 minutos, y que el RPO real del plan con un respaldo diario es de hasta 24 h.

**Qué se descartó:** la suposición de que la sección 3 de `health_check.sql` (tuplas muertas) habría mostrado el incidente. Se descartó porque, al consultar `pg_stat_user_tables` en `foodstore_desastre`, `detalle_pedido` tenía `n_dead_tup = 0`: el autovacuum las limpió a las 23:58:33, 73 s después del `DELETE`. Pasado ese minuto, la única señal es `n_live_tup = 0`, que nadie vigila. Eso pasó a ser la acción correctiva 1 (un control de pedidos sin líneas).

**Cómo se comprobó:** cada cifra del informe se cotejó con las evidencias `.txt` y con `logs/simulacro_desastre.log`. La causa raíz se verificó en `sql/roles.sql`, línea 90: `rol_app_escritura` solo tiene `SELECT` sobre `detalle_pedido`. Los enlaces de la fila 8 de la matriz se comprobaron contra el repo (ninguno roto).

---

### Entrada 3 · 08/11/2026 · Elías Tello · Claude Code

**Qué se pidió:** revisar los PR #45 (`base-datos-2`) y #13 (`BaseDatos2-MongoDB`) de Bruno, como parte de la revisión cruzada.

**Qué se aceptó:** los informes de revisión de U1 a U8, el cierre de los objetivos 13 y 14 en la matriz, y que los commits no tuvieran líneas de autoría de IA.

**Qué se corrigió:** se pidió corregir la fila de Elías en `DUIA_tpi.md`, que daba el simulacro como hecho con Kiro y OpenCode antes de que existiera, y la mención del simulacro como especificado con Kiro en `bruno_ia_codereview.md`. La corrección H1 (`SECURITY DEFINER` en `registrar_pedido`) estaba citada en `food-store/procedimientos.sql`, pero está en `sql/roles.sql` (líneas 76 a 78).

**Qué se descartó:** aprobar el PR #13 tal como estaba, porque duplicaba en `BaseDatos2-MongoDB` los archivos del TPI que ya están en `base-datos-2` (DUIA, bitácora y `review_u1` a `review_u8`), y con dos copias las correcciones no llegan a las dos. Se pidieron cambios.

**Cómo se comprobó:** con `git grep` sobre el repo: `SPEC_simulacro_desastre.md` no existía en la rama de Bruno, y `SECURITY DEFINER` aparece en `sql/roles.sql` y no en `food-store/procedimientos.sql`.

---

## DUIA

| Fecha | Herramienta | Propósito | Qué se le dio (Input) | Qué devolvió (Output) | Decisión | Motivo y comprobación |
|---|---|---|---|---|---|---|
| 08/11/2026 | Claude Code | Escribir `mantenimiento/SPEC_simulacro_desastre.md` (objetivo 8) | Contexto del TPI del grupo, `SPEC_U6.md`, `restore_test.sh`, `conteo_referencia.sql`, `sql/roles.sql` y el esquema de `foodstore` | Spec con escenario, reglas de seguridad, secuencia con cronómetro, metas y 7 criterios de aceptación | **Aceptado** | Revisada por el autor antes de escribir el guion. |
| 08/11/2026 | Claude Code | Escribir y ejecutar `mantenimiento/simulacro_desastre.sh` | La spec anterior | Guion con `MODO=ensayo` y `MODO=real`, guardas, autorizaciones y medición de RTO, RPO y datos perdidos | **Aceptado con 1 corrección y 1 descarte** | Ver Entrada 1: se corrigió un `SELECT` inválido y se descartó la justificación falsa sobre `psql -1`. Ensayo y corrida real con PASS (evidencias `simulacro_desastre_*.txt`). |
| 08–09/11/2026 | Claude Code | Redactar `mantenimiento/informe_post_incidente.md`, la sección del README y la fila 8 de la matriz | Evidencias de las corridas, logs y `sql/roles.sql` | Informe sin culpables de 11 secciones, sección de reproducción y fila de la matriz | **Aceptado con correcciones y 1 descarte** | Ver Entrada 2: se descartó que `health_check.sql` detectara el incidente (autovacuum a los 73 s, comprobado con `pg_stat_user_tables`). |
| 08/11/2026 | Claude Code | Revisar los PR #45 y #13 de Bruno | Diff de los dos PR y el repo | 4 observaciones en el #45 y 1 en el #13 | **Aceptado** | Ver Entrada 3: se aprobó el #45 con comentarios y se pidieron cambios en el #13. |

### Apartamientos del flujo de la cátedra (declarados)

- **Claude Code en lugar de Kiro → OpenCode** para la spec, el guion y el informe del objetivo 8, por pedido del autor. Se mantuvo el orden «spec antes que código»: la spec se revisó antes de escribir el guion.
- **Ejecución por la IA bajo autorización del autor:** el ensayo y la corrida real los ejecutó Claude Code a pedido explícito del autor, después de que este revisara el guion. Las autorizaciones de borrado de las bases descartables quedaron registradas con `origen=variable` en `logs/simulacro_desastre.log`.
- **Respaldo disparado con `schtasks /run`** el 08/11/2026 a las 23:48; la tarea queda programada para las 21:00 diarias. La distinción entre corrida manual y por horario corresponde al objetivo 7 (Bloque A).
- La contraseña de PostgreSQL nunca se le dio a la IA: está en `%APPDATA%\postgresql\pgpass.conf`, creado por el autor. Ninguna prueba se corrió sobre `foodstore` ni `bd2_tp3`; `foodstore` solo se leyó para comprobar que no cambió.
