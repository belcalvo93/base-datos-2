# Bitácora consolidada de uso de IA — TPI Parcial II (Food Store · Unidades 4 a 8)

Esta bitácora reúne las intervenciones con herramientas de inteligencia artificial durante el cierre integrador del **TPI Parcial II** (al menos 2 entradas por integrante, cada una con qué se pidió, qué se aceptó, qué se corrigió, **qué se descartó con fundamento técnico** y cómo se comprobó en el motor) y enlaza las bitácoras detalladas de cada unidad de la cursada.

---

## 1. Índice de bitácoras y registros de IA por unidad (U4 a U8)

| Unidad | Repositorio | Archivo de bitácora / contraste con IA | Contenido principal |
|---|---|---|---|
| **Unidad 4** (FNBC y desnormalización) | `base-datos-2` | [`docs/duia/duia_tp_u4.md`](../duia/duia_tp_u4.md) | Uso de Kiro, OpenCode y Claude Code en specs de FNBC, reversión, desnormalización por trigger, mediciones `EXPLAIN (ANALYZE, BUFFERS)` y auditoría. |
| **Unidad 5** (Seguridad, roles y auditoría) | `base-datos-2` | [`BITACORA.md`](../../BITACORA.md), [`docs/auditoria_roles_ia.md`](../auditoria_roles_ia.md) y [`docs/decisiones_auditoria_roles.md`](../decisiones_auditoria_roles.md) | 7 entradas de la cursada (roles, `pgcrypto`, `log_statement`, anonimización, incidente) + matriz de decisiones humanas sobre los 16 hallazgos (`H1–H5`, `F1–F4`, `R1–R3`, `M1–M4`). |
| **Unidad 6** (Mantenimiento, respaldo y DR) | `base-datos-2` | [`mantenimiento/revision_opencode.md`](../../mantenimiento/revision_opencode.md), [`mantenimiento/revision_opencode_v2.md`](../../mantenimiento/revision_opencode_v2.md) y [`mantenimiento/decisiones_revision.md`](../../mantenimiento/decisiones_revision.md) | Revisiones v1 y v2 con OpenCode (agente Plan) de `backup_foodstore.sh`, `restore_test.sh`, `maintenance.sql` y `health_check.sql`, y decisiones humanas verificadas. |
| **Unidad 7** (Modelado documental MongoDB) | `BaseDatos2-MongoDB` | [`consigna6_ia_contraste.md`](https://github.com/belcalvo93/BaseDatos2-MongoDB/blob/main/consigna6_ia_contraste.md) y [`prueba_indice_unico_ia.js`](https://github.com/belcalvo93/BaseDatos2-MongoDB/blob/main/prueba_indice_unico_ia.js) | Contraste del diseño embebido vs referenciado, descarte de `double` por `Decimal128` y refutación en `mongosh` del índice único multikey sobre `lineas.id_producto`. |
| **Unidad 8** (SQLite móvil y code review) | `BaseDatos2-MongoDB` | [`food-store/docs/bitacora_ia.md`](https://github.com/belcalvo93/BaseDatos2-MongoDB/blob/main/food-store/docs/bitacora_ia.md) y [`food-store/docs/3c_code_review_ia.md`](https://github.com/belcalvo93/BaseDatos2-MongoDB/blob/main/food-store/docs/3c_code_review_ia.md) | 13 entradas del TP8 (specs EARS en Kiro, tablas `STRICT`, `evaluacion_sync`, semáforo, idempotencia C6) y tabla de los 18 hallazgos del code review de U1 a U8. |
| **TPI · Revisiones por unidad** | Ambos repos | [`docs/tpi_parcial2/review/`](review/) (`review_u1.md` a `review_u8.md`) | Revisión completa de los 56 scripts de la cursada + 3 del TPI (0 scripts sin revisar). |

---

## 2. Entradas del cierre integrador (TPI Parcial II)

### Bloque A · Belén Calvo — Respaldo programado, retención y estructura del TPI

#### Entrada A.1 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)
- **Qué se pidió:** modificar `mantenimiento/backup_foodstore.sh` según la sección «Programación y retención» de `SPEC_U6.md`: retención de 7 días con mínimo de 3 juegos completos, ejecutada únicamente después de un `PASS`, y respaldo de roles con `pg_dumpall --globals-only --no-role-passwords`.
- **Qué se aceptó:** la función `retener()`, las 4 guardas sobre el archivo de roles (fallo de `pg_dumpall`, archivo vacío, ausencia de `CREATE ROLE`/`ALTER ROLE`, o aparición de `PASSWORD`), el cálculo de antigüedad a partir del sello del nombre (`AAAAMMDD_HHMMSS`) y no del `mtime`, y el campo `origen=manual|programada` en el log.
- **Qué se corrigió:**
  1. Un error de tipeo en una variable (`dumpsuegos`) y una variable sin inicializar bajo `set -u` cuando no había juegos previos; se declararon explícitamente `local -a dumps=() juegos=() orden=()`.
  2. El `.dump` se borraba antes que los demás archivos del juego; se invirtió el orden para que el `.dump` se borre último y solo si antes se borraron `.conteo`, `.sha256` y `_globals.sql`.
  3. `ORIGEN` no estaba exportada en la tarea programada, por lo que no llegaba al subproceso `bash`.
- **Qué se descartó:** las pruebas de retención propuestas por la IA operaban directamente sobre la carpeta real `mantenimiento/backups/`, poniendo en riesgo los respaldos verdaderos. Se **descartó** y se probó inyectando una carpeta temporal mediante la variable `BACKUP_DIR`.
- **Cómo se comprobó:** `mantenimiento/evidencias/retencion_pruebas.txt` (6 juegos antes → elimina 3 vencidos y conserva 3; `RETENCION_MIN_COPIAS=2` sale con código 2; una base inexistente registra `FAIL` y no ejecuta la retención) y `mantenimiento/evidencias/globals_pruebas.txt` (9 sentencias de roles, 0 hashes `SCRAM-SHA-256`/`md5`, y las 4 guardas abortan con `FAIL` ante fallos provocados).

#### Entrada A.2 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)
- **Qué se pidió:** generar `mantenimiento/programar_respaldo.ps1` (crea la tarea diaria `FoodStore_Backup_Diario` a las 21:00 en el Programador de tareas de Windows) y `mantenimiento/quitar_respaldo.ps1` (la elimina), sin almacenar contraseñas.
- **Qué se aceptó:** registro idempotente (`-Force`), `StartWhenAvailable`, `MultipleInstances IgnoreNew` y ejecución bajo la sesión del usuario actual usando `%APPDATA%\postgresql\pgpass.conf`.
- **Qué se corrigió:**
  1. OpenCode usó un *script block* dentro de `-replace`, sintaxis exclusiva de PowerShell 6+ que falla en Windows PowerShell 5.1; se reemplazó por `Substring` y `Replace`.
  2. PowerShell expandía `$PATH` al registrar la tarea en vez de dejarlo para `bash`, y la ruta `C:\Program Files\PostgreSQL\17\bin` iba sin comillas internas; se escapó `\$PATH` y se entrecomilló correctamente.
  3. En Git Bash, `schtasks /query` convertía `/query` en ruta MSYS (`C:/Program Files/Git/query`); se prefijó `MSYS_NO_PATHCONV=1`.
- **Qué se descartó:** la secuencia de reproducción propuesta ejecutaba `quitar_respaldo.ps1` inmediatamente después de probar la tarea, dejando al equipo sin el respaldo programado activo que necesita el Bloque C (Elías). Se **descartó** y `quitar_respaldo.ps1` quedó documentado aparte como comando opcional de desinstalación.
- **Cómo se comprobó:** `mantenimiento/evidencias/tarea_programada.txt` (estado `Listo`, diaria a las 21:00), `tarea_programada_prueba_humo.txt` (disparo con `schtasks /run`: `PASS` con `origen=programada`, `Último resultado: 0`) y `tarea_programada_segunda_corrida.txt` (2 líneas `PASS` con `origen=programada` en `logs/backup_foodstore.log`).

#### Entrada A.3 · 08/11/2026 · Belén Calvo · OpenCode (Plan y Build)
- **Qué se pidió:** corregir el código de salida de la guarda de `mantenimiento/maintenance.sql` (`\quit` salía con 0), armar `docs/tpi_parcial2/matriz_objetivos.md`, agregar las secciones de U4 y U5 al `README.md` de la raíz, actualizar `mantenimiento/README.md` y crear la plantilla `docs/tpi_parcial2/informe_tpi.html` junto con las secciones de U7 y U8.
- **Qué se aceptó:** la guarda con `DO $$ … RAISE EXCEPTION` en `maintenance.sql` (devuelve código 3 en `psql`), la tabla de los 14 objetivos con enlaces a ambos repositorios y el diseño HTML/CSS del informe.
- **Qué se corrigió:** se depuró el texto de los READMEs, se quitaron cifras de RTO preescritas en los huecos pendientes del HTML y se rehízo el índice de objetivos del informe cotejando cada ruta con `matriz_objetivos.md`.
- **Qué se descartó:** 1) En `mantenimiento/README.md`, se descartó afirmar que ese README ya cubría el simulacro de desastre (Objetivo 8, a cargo de Elías) y se descartó una prueba de retención con fechas fijas que caducaría al día siguiente, reemplazándola por fechas relativas (`date -d "-N days"`). 2) En `informe_tpi.html`, se descartó poner `break-before: page` en cada `<h2>`, porque forzaba saltos de página que hacían superar el límite de 6 páginas.
- **Cómo se comprobó:** `mantenimiento/evidencias/maintenance_v5_guarda.txt` (sobre `postgres` aborta con `RAISE EXCEPTION` y `exit_code=3`; sobre `foodstore_restore_test` finaliza con `exit_code=0`).

---

### Bloque B · Hernán González — Reversión de FNBC y decisiones de auditoría de roles

#### Entrada B.1 · 08/11/2026 · Hernán González · Kiro / OpenCode (Plan y Build)
- **Qué se pidió:** redactar la sección 9 («Plan de reversión») en `food-store/specs/spec_fnbc_descomposicion.md` y generar el script `food-store/tp_fnbc_reversion.sql` para ejecutar sobre `bd2_tp4u4` el ciclo completo `migrar → verificar → revertir → verificar` sin pérdida de datos (Objetivo 2).
- **Qué se aceptó:** la guarda inicial `DO $$ … RAISE EXCEPTION` si `current_database() <> 'bd2_tp4u4'`, la foto previa en `temp_pre_reversion`, la reconstrucción de `control_lote_almacen` desde `control_lote NATURAL JOIN responsable_deposito`, el orden de borrado `DROP VIEW v_control_lote_almacen` → `DROP TABLE control_lote` ($R_2$ hija) → `DROP TABLE responsable_deposito` ($R_1$ padre), y los cuatro `EXCEPT` (dos en la migración y dos en la reversión).
- **Qué se corrigió:** si `control_lote_almacen` conservaba las 3 filas originales y solo se ejecutaba `INSERT … ON CONFLICT DO NOTHING`, la prueba no demostraba que las tuplas se reconstruyeran realmente desde las tablas en FNBC. Se agregó `TRUNCATE TABLE control_lote_almacen;` inmediatamente después de capturar `temp_pre_reversion` y antes del `INSERT INTO control_lote_almacen SELECT … FROM control_lote NATURAL JOIN responsable_deposito`.
- **Qué se descartó:** la primera propuesta usaba `DROP TABLE IF EXISTS responsable_deposito, control_lote CASCADE;` en una sola línea. Se **descartó** porque `CASCADE` oculta el orden de dependencias por claves foráneas exigido por la consigna y puede arrastrar en silencio objetos dependientes.
- **Cómo se comprobó:** previo respaldo `pg_dump -Fc` de `bd2_tp4u4`, se ejecutó `psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -f food-store/tp_fnbc_reversion.sql` primero con `ROLLBACK` y luego con `COMMIT` vía `-v commit=1` (`food-store/tp_fnbc_reversion_salida.txt`): los 4 `EXCEPT` devolvieron `0 filas`, `to_regclass` confirmó `vista_fnbc_existe = f`, `r2_control_lote_existe = f`, `r1_responsable_deposito_existe = f` y `tabla_original_existe = t`, y `control_lote_almacen` quedó con sus 3 tuplas y sus 4 restricciones (`1 PK + 3 FK`).

#### Entrada B.2 · 08/11/2026 · Hernán González · OpenCode (Plan y Build)
- **Qué se pidió:** elaborar `docs/decisiones_auditoria_roles.md` con la decisión humana para cada hallazgo de `docs/auditoria_roles_ia.md` (`H1–H5`, `F1–F4`, `R1–R3` y `M1–M4`) y ampliar `sql/verificacion_roles.sql` para comprobar todos los casos con `SET ROLE …; <intento>; RESET ROLE;` dentro de `BEGIN … ROLLBACK;` sobre `bd2_tp5u5` (Objetivo 6).
- **Qué se aceptó:** la matriz completa documentando los 2 hallazgos aceptados (`H1`, `H4`), los 2 corregidos en `sql/roles.sql` (`R1`, `R2`), los 10 descartados con fundamento / riesgos aceptados (`H2`, `H3`, `F1`, `F2`, `F3`, `R3`, `M1–M4` y atributos de `admin_datos`) y los 2 pospuestos (`H5`, `F4`), junto con el bloque de pruebas funcionales en `sql/verificacion_roles.sql`.
- **Qué se corrigió:** en la prueba de `H4` dentro de `sql/verificacion_roles.sql`, la subconsulta propuesta para elegir un usuario no administrador bajo `SET ROLE rol_soporte` escribía `SELECT id FROM usuario WHERE rol = 'USUARIO' AND eliminado = FALSE ORDER BY id LIMIT 1`. Al correrla en `bd2_tp5u5` falló con `ERROR: permiso denegado a la tabla usuario` antes de invocar `fn_resetear_password`, porque `rol_soporte` solo tiene `GRANT SELECT (id, nombre, apellido, mail, rol) ON usuario` y no puede leer la columna `eliminado` (hallazgo `F3`). Se quitó `AND eliminado = FALSE` de la subconsulta exterior (la función `SECURITY DEFINER` ya lo valida adentro).
- **Qué se descartó:** se **descartaron** las propuestas de la IA de: 1) mover `mv_ventas_categoria_mes` a un esquema `reportes` separado (`H2`, rompe las consultas del TP sobre `public`); 2) crear `soporte_login`, dar `SELECT(eliminado)` a `rol_soporte` o crear un rol con `MAINTAIN` (`F2` y `F3`, otorgan permisos no pedidos por la spec y violan mínimo privilegio); 3) editar `food-store/procedimientos.sql` y `food-store/views.sql` o correr `REVOKE` en `bd2_tp3` (`H3`, `F1`, `R2`, no se modifica `bd2_tp3` ni entregables cerrados); y 4) reescribir `sql/roles.sql` con loops dinámicos sobre `pg_class`/`pg_proc` (`R1`, `M1–M4`, resta claridad para la defensa oral y arriesga revocar `EXECUTE` sobre `pgcrypto`).
- **Cómo se comprobó:** se ejecutó `psql -U postgres -d bd2_tp5u5 -X -f sql/verificacion_roles.sql > docs/verificacion_roles.txt 2>&1` (160 líneas): todas las operaciones permitidas y todos los rechazos esperados (`permiso denegado`, bloqueo de reseteo a `ADMIN` y rechazo de clave `< 8` caracteres) se cumplieron dentro de `BEGIN … ROLLBACK;`.

---

### Bloque C · Elías Tello — Simulacro de desastre contra reloj e informe post-incidente

> *Nota de integración:* Las entradas detalladas de la ejecución del simulacro de desastre sobre `foodstore_desastre` (`mantenimiento/SPEC_simulacro_desastre.md`, `mantenimiento/simulacro_desastre.sh` e `informe_post_incidente.md`) corresponden al Bloque C (Elías Tello), que se apoya en las entradas de mantenimiento y restauración ya registradas en `food-store/docs/bitacora_ia.md` (Entradas 10 a 12) y en `mantenimiento/decisiones_revision.md` (donde se descartó comparar el conteo restaurado contra la base `foodstore` viva y se corrigió la medición del RPO antes del `createdb`).

---

### Bloque D · Bruno Fiouchetta — Code review completo (U1 a U8) y consolidación de IA

#### Entrada D.1 · 08/11/2026 · Bruno Fiouchetta · OpenCode (agente Plan) y asistente en entorno
- **Qué se pidió:** revisar en modo de solo lectura los 30 scripts de `base-datos-2` correspondientes a las Unidades 1 a 5 que figuraban con `"—"` en `food-store/docs/inventario_scripts_u1_u8.md` (más `tp_fnbc_reversion.sql`), elaborar `docs/tpi_parcial2/review/review_u1.md` a `review_u5.md` y comprobar cada hallazgo o propuesta en PostgreSQL antes de decidir (Objetivo 13).
- **Qué se aceptó:** la validación sin observaciones de los 15 scripts que cumplen íntegramente las specs y el protocolo de seguridad, y la documentación de las observaciones de `pruebas_restricciones.sql` (U1), `verificacion_carga_masiva.sql` (U2) y `views.sql` (U3) en sus respectivos informes de revisión.
- **Qué se corrigió:** se integró en `review_u5.md` la corrección del filtro `eliminado = FALSE` en la subconsulta de `rol_soporte` dentro de `sql/verificacion_roles.sql`.
- **Qué se descartó:**
  1. **U1 (`restricciones.sql`, Hallazgo 12):** reemplazar `trg_verificar_stock_suficiente` por `CHECK (cantidad <= (SELECT stock FROM producto ...))`, porque PostgreSQL no admite subconsultas en `CHECK`.
  2. **U2 (`carga_masiva.sql`, Hallazgo 13):** quitar `+ s.i * 0` de `ORDER BY random() + s.i * 0 LIMIT 1`, porque sin correlación PostgreSQL planifica un `InitPlan` (`loops=1`) y repite una única categoría y un único cliente en todas las filas.
  3. **U3 (`materializadas.sql`, Hallazgo 14):** reemplazar `mv_facturacion_cat_mes` por un índice `CREATE INDEX ON pedido (DATE_TRUNC('month', fecha))`, porque `DATE_TRUNC` sobre `TIMESTAMPTZ` es `STABLE` y no `IMMUTABLE`.
  4. **U4 (`carga_pedidos_hoy.sql` y `medicion_top_categorias_antes.sql`, Hallazgo 15):** reemplazar el rango `fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1` por `fecha::date = CURRENT_DATE`, porque el cast sobre la columna anula el uso de índices B-tree.
  5. **U5 (`anonimizar_log.sh`, Hallazgo 16):** usar `'***'` constante para todas las contraseñas en `fn_autenticar` (impide distinguir fuerza bruta con claves distintas de reintentos con la misma clave) y usar una regex de mail sin punto en el dominio (pisa `app_web@bd2_tp5u5`).
- **Cómo se comprobó:** se ejecutaron las 4 pruebas en `psql` 17.11 sobre `bd2_trabajo` y `bd2_tp4u4` dentro de `BEGIN … ROLLBACK;`, obteniendo los errores literales (`ERROR: no se pueden usar subconsultas en una restricción «check»`, `ERROR: las funciones utilizadas en expresiones de índice deben estar marcadas IMMUTABLE`) y los planes de `EXPLAIN` (`InitPlan 1` vs `SubPlan 1`, y `Parallel Seq Scan` de costo `3882.76` vs `Index Only Scan` de costo `8.45`).

#### Entrada D.2 · 08/11/2026 · Bruno Fiouchetta · OpenCode (agente Plan) y asistente en entorno
- **Qué se pidió:** revisar los 7 scripts pendientes de las Unidades 7 y 8 en `BaseDatos2-MongoDB` (`seleccion_pedidos.sql`, `consultas_postgresql.sql`, `importar_catalogo.sql`, `pruebas_sqlite.sql`, `casos_servidor.sql`, `casos_sqlite.sql` y `consulta_final.sql`), redactar `review_u7.md` y `review_u8.md`, actualizar `3c_code_review_ia.md` e `inventario_scripts_u1_u8.md` para que ningún script quede en `"—"`, y consolidar `bitacora_ia_tpi.md`, `DUIA_tpi.md` y la sección 3 del informe técnico.
- **Qué se aceptó:** los informes `review_u7.md` y `review_u8.md`, las filas 12 a 18 en `3c_code_review_ia.md` y la actualización completa de `inventario_scripts_u1_u8.md` cubriendo el 100 % de los scripts.
- **Qué se corrigió:** se corrigió la ruta de referencia del documento de IA de la Unidad 7 (`consigna6_ia_contraste.md` en la raíz de `BaseDatos2-MongoDB`) tras verificar el árbol real del repositorio antes de enlazarlo.
- **Qué se descartó:**
  1. **U7 (`seleccion_pedidos.sql` y `consultas_postgresql.sql`, Hallazgo 17):** incluir `'subtotal'` dentro de `lineas[]` en el JSON de migración (contradice `modelo_documental.md`) y filtrar `WHERE eliminado = FALSE` en `consultas_postgresql.sql` (columna inexistente en esas tablas).
  2. **U8 (`importar_catalogo.sql`, Hallazgo 18):** reemplazar el upsert de `producto_cache` por `DELETE FROM producto_cache; INSERT …` y eliminar `WHERE true` antes de `ON CONFLICT (producto_id) DO UPDATE`.
- **Cómo se comprobó:**
  - En `psql` (`bd2_trabajo`), `information_schema.columns` confirmó `0 filas` para la columna `eliminado` en `pedido`, `detalle_pedido`, `cliente` y `producto`.
  - En SQLite 3.49.1 sobre `foodstore_movil.db` (`PRAGMA foreign_keys = ON`, en transacción revertida), `DELETE FROM producto_cache` arrojó `sqlite3.IntegrityError: FOREIGN KEY constraint failed`.
  - En SQLite 3.49.1 (`:memory:`), quitar `WHERE true` antes de `ON CONFLICT(id) DO UPDATE` arrojó `sqlite3.OperationalError: near "DO": syntax error`.
  - `Select-String -Pattern "\|\s*—\s*\|"` sobre `inventario_scripts_u1_u8.md` devolvió `0` coincidencias.
