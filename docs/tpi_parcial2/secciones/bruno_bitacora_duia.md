# Bitácora y DUIA del TPI — Bruno Fiouchetta (Bloque D: Code review completo de U1 a U8 y consolidación de Bitácora/DUIA)

Material integrado en `docs/tpi_parcial2/bitacora_ia_tpi.md` y `docs/tpi_parcial2/DUIA_tpi.md`.

## Bitácora

Formato: fecha · quién · herramienta · qué se pidió · qué se aceptó · qué se corrigió o descartó y por qué · cómo se comprobó.

---

### Entrada 1 · 08/11/2026 · Bruno Fiouchetta · OpenCode (agente Plan) y asistente en entorno

**Qué se pidió:** revisar en modo de solo lectura los 30 scripts de `base-datos-2` correspondientes a las Unidades 1, 2, 3, 4 y 5 que figuraban con `"—"` en `food-store/docs/inventario_scripts_u1_u8.md` (además del nuevo `food-store/tp_fnbc_reversion.sql`), elaborar los informes `docs/tpi_parcial2/review/review_u1.md` a `review_u5.md` y comprobar en el motor PostgreSQL cada observación o sugerencia antes de tomar una decisión humana.

**Qué se aceptó:**
- La verificación de cumplimiento sin observaciones de los scripts que respetan íntegramente las especificaciones y el protocolo de seguridad (`schema.sql`, `data.sql`, `verificacion_normalizacion.sql`, `carga_masiva_bloque3_B.sql`, `indices.sql`, `queries.sql`, `medicion_planes.sql`, `medicion_escritura.sql`, `tp_fnbc_control_lote.sql`, `medicion_top_categorias_despues.sql`, `medicion_escritura_top_categorias.sql`, `tp_desnormalizacion_reversion.sql`, `mv_ventas_categoria_mes.sql`, `simulacro_incidente.sql` y `simulacro_limpieza.sql`).
- Documentar como observaciones para la defensa el `SELECT id_pedido FROM pedido LIMIT 1` sin `ORDER BY` en `pruebas_restricciones.sql` (U1), la calibración de `LIMIT 10000` en `verificacion_carga_masiva.sql` (U2) y la transición del rol `rol_reportes` desde `views.sql` (U3) hacia `sql/roles.sql` (U5).

**Qué se corrigió:**
- Al verificar la ampliación de `sql/verificacion_roles.sql` (U5), se constató que filtrar `WHERE rol = 'USUARIO' AND eliminado = FALSE` dentro de la subconsulta ejecutada bajo `SET ROLE rol_soporte` fallaba con `ERROR: permiso denegado a la tabla usuario` porque `rol_soporte` no posee `SELECT(eliminado)` (`F3` de `decisiones_auditoria_roles.md`), quedando corregida la subconsulta sin esa columna y comprobada en `docs/verificacion_roles.txt`.

**Qué se descartó:**
1. **En U1 (`restricciones.sql`, Hallazgo 12):** se descartó la propuesta de reemplazar `trg_verificar_stock_suficiente` por `CHECK (cantidad <= (SELECT stock FROM producto p WHERE p.id_producto = id_producto))`, porque PostgreSQL prohíbe subconsultas en restricciones `CHECK` (`SQLSTATE 0A000`).
2. **En U2 (`carga_masiva.sql`, Hallazgo 13):** se descartó eliminar `+ s.i * 0` de los subqueries `ORDER BY random() + s.i * 0 LIMIT 1`, porque sin la referencia externa el optimizador planifica un `InitPlan` (`loops=1`) y asigna la misma categoría y el mismo cliente a todas las filas.
3. **En U3 (`materializadas.sql`, Hallazgo 14):** se descartó reemplazar `mv_facturacion_cat_mes` por un índice `CREATE INDEX ON pedido (DATE_TRUNC('month', fecha))`, porque `DATE_TRUNC` sobre `TIMESTAMPTZ` es `STABLE` (depende de `TimeZone`) y PostgreSQL exige funciones `IMMUTABLE` en expresiones de índice (`SQLSTATE 42P17`).
4. **En U4 (`carga_pedidos_hoy.sql` y `medicion_top_categorias_antes.sql`, Hallazgo 15):** se descartó cambiar el filtro de rango `fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1` por `fecha::date = CURRENT_DATE`, porque el cast sobre la columna impide usar índices sobre `pedido(fecha)` y fuerza un `Parallel Seq Scan`.
5. **En U5 (`anonimizar_log.sh`, Hallazgo 16):** se descartó enmascarar todas las claves fallidas con una constante única `'***'` (impide distinguir un reintento de red de un ataque de fuerza bruta con claves distintas; se mantuvo `CLAVE_REDACTADA_N`) y usar una regex de mail sin punto en el dominio (pisaría `app_web@bd2_tp5u5`).

**Cómo se comprobó:** cada propuesta descartada se ejecutó en `psql` (PostgreSQL 17.11) sobre `bd2_trabajo` y `bd2_tp4u4` dentro de `BEGIN … ROLLBACK;`:
- `ALTER TABLE detalle_pedido ADD CONSTRAINT chk_stock CHECK (...)` devolvió `ERROR: no se pueden usar subconsultas en una restricción «check»`.
- `EXPLAIN SELECT (SELECT id_categoria FROM categoria ORDER BY random() LIMIT 1) FROM generate_series(1, 10) s(i);` mostró `InitPlan 1` (`loops=1`), mientras que con `+ s.i * 0` mostró `SubPlan 1`.
- `CREATE INDEX idx_test_mes ON pedido (DATE_TRUNC('month', fecha));` devolvió `ERROR: las funciones utilizadas en expresiones de índice deben estar marcadas IMMUTABLE`.
- `EXPLAIN SELECT count(*) FROM pedido WHERE fecha::date = CURRENT_DATE;` con un índice sobre `pedido(fecha)` produjo `Parallel Seq Scan on pedido (cost=0.00..3882.76)`, mientras que el rango `[CURRENT_DATE, CURRENT_DATE + 1)` produjo `Index Only Scan using idx_tmp_fecha on pedido (cost=0.43..8.45)`.

---

### Entrada 2 · 08/11/2026 · Bruno Fiouchetta · OpenCode (agente Plan) y asistente en entorno

**Qué se pidió:** completar el code review de los 7 scripts pendientes de las Unidades 7 y 8 en `BaseDatos2-MongoDB` (`seleccion_pedidos.sql`, `consultas_postgresql.sql`, `importar_catalogo.sql`, `pruebas_sqlite.sql`, `casos_servidor.sql`, `casos_sqlite.sql` y `consulta_final.sql`), generar `review_u7.md` y `review_u8.md`, actualizar `3c_code_review_ia.md` e `inventario_scripts_u1_u8.md` para que ningún script quede en `"—"`, y consolidar `bitacora_ia_tpi.md`, `DUIA_tpi.md` y la sección 3 del informe técnico.

**Qué se aceptó:**
- La estructura de los informes `review_u7.md` y `review_u8.md`, la incorporación de los Hallazgos 12 a 18 en `food-store/docs/3c_code_review_ia.md` y la actualización completa de `food-store/docs/inventario_scripts_u1_u8.md` (56 scripts de la cursada + 3 scripts nuevos del TPI, con 0 celdas en `"—"`).
- La integración en `bitacora_ia_tpi.md` y `DUIA_tpi.md` de las entradas de los 4 integrantes junto con la tabla de trazabilidad hacia las bitácoras y DUIA de U4 a U8.

**Qué se corrigió:**
- Al verificar las rutas de las bitácoras previas en `BaseDatos2-MongoDB` antes de enlazarlas en `bitacora_ia_tpi.md`, se detectó que en la raíz de la Unidad 7 el archivo no se llamaba `DUIA.md` sino `consigna6_ia_contraste.md` (mientras que `food-store/docs/DUIA.md` corresponde a la Unidad 8). Se corrigió el enlace antes de escribir el archivo consolidado.

**Qué se descartó:**
1. **En U7 (`seleccion_pedidos.sql` y `consultas_postgresql.sql`, Hallazgo 17):** se descartó agregar `'subtotal', dp.cantidad * dp.precio_unitario` dentro de `lineas[]` en el JSON de migración (contradice `modelo_documental.md`, donde solo se almacena `total` en cabecera como `Decimal128`) y agregar `WHERE eliminado = FALSE` en `consultas_postgresql.sql` (ni `pedido` ni `detalle_pedido` tienen esa columna).
2. **En U8 (`importar_catalogo.sql`, Hallazgo 18):** se descartó reemplazar el upsert de `producto_cache` por `DELETE FROM producto_cache; INSERT INTO producto_cache SELECT ...` y quitar la cláusula `WHERE true` antes de `ON CONFLICT (producto_id) DO UPDATE`.

**Cómo se comprobó:**
- En PostgreSQL (`bd2_trabajo`), `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('pedido','detalle_pedido','cliente','producto') AND column_name='eliminado';` devolvió `0 filas`.
- En SQLite 3.49.1 sobre `food-store/movil/foodstore_movil.db` (dentro de una transacción revertida con `PRAGMA foreign_keys = ON`), ejecutar `DELETE FROM producto_cache` cuando existen borradores en `item_borrador` falló con `sqlite3.IntegrityError: FOREIGN KEY constraint failed`.
- En SQLite 3.49.1 en memoria (`:memory:`), ejecutar `INSERT INTO t SELECT id, v FROM s ON CONFLICT(id) DO UPDATE SET v=excluded.v` sin `WHERE true` falló con `sqlite3.OperationalError: near "DO": syntax error`.
- Se verificó con `Select-String -Pattern "\|\s*—\s*\|"` sobre `inventario_scripts_u1_u8.md` que quedaron `0` filas sin revisar.

---

## DUIA

| Fecha | Herramienta | Propósito | Qué se le dio (Input) | Qué devolvió (Output) | Decisión | Motivo y comprobación |
|---|---|---|---|---|---|---|
| 08/11/2026 | OpenCode (agente Plan) / asistente en entorno | Revisar los 30 scripts con `"—"` de U1 a U5 en `base-datos-2` y redactar `review_u1.md` a `review_u5.md` | Scripts `.sql` y `.sh` de U1–U5, specs de cada unidad e `inventario_scripts_u1_u8.md` | Informes de revisión `review_u1.md`..`review_u5.md` y hallazgos 12 a 16 | **Aceptado con 5 descartes comprobados en motor** | Ver Entrada 1. Cada propuesta de la IA se probó con `EXPLAIN` o dentro de `BEGIN … ROLLBACK` en `bd2_trabajo`, `bd2_tp4u4` y `bd2_tp5u5`. |
| 08/11/2026 | OpenCode (agente Plan) / asistente en entorno | Revisar los 7 scripts con `"—"` de U7 y U8 en `BaseDatos2-MongoDB`, redactar `review_u7.md` y `review_u8.md` y actualizar `3c_code_review_ia.md` e `inventario_scripts_u1_u8.md` | Scripts de U7 y U8, `3c_code_review_ia.md` e `inventario_scripts_u1_u8.md` | Informes `review_u7.md` y `review_u8.md`, hallazgos 17 y 18 e inventario completo sin `"—"` | **Aceptado con 2 descartes comprobados en motor** | Ver Entrada 2. Comprobado en `psql` (`bd2_trabajo`) y `sqlite3` 3.49.1 (`FOREIGN KEY constraint failed` y `near "DO": syntax error`). |
| 08/11/2026 | Asistente en entorno (Antigravity / Gemini) | Consolidar `bitacora_ia_tpi.md`, `DUIA_tpi.md` y redactar la sección 3 del informe técnico (`bruno_ia_codereview.md`) | `belen_bitacora_duia.md`, `hernan_bitacora_duia.md`, bitácoras/DUIA de U4 a U8 y `3c_code_review_ia.md` | Documentos consolidados del TPI y sección 3 del informe técnico | **Aceptado con 1 corrección** | Se corrigió la referencia de U7 a `consigna6_ia_contraste.md` tras verificar las rutas con `Get-ChildItem`. |

### Apartamientos del flujo de la cátedra (declarados)

- Para agilizar la revisión transversal de los 37 scripts pendientes en ambos repositorios y la consolidación de `bitacora_ia_tpi.md` y `DUIA_tpi.md`, se utilizó el agente del entorno (Antigravity / Gemini) en conjunto con el análisis estático de solo lectura (rol de agente Plan), ejecutando todas las pruebas de contraste directamente en los motores locales (`psql` 17.11 y `sqlite3` 3.49.1) dentro de transacciones reversibles (`BEGIN … ROLLBACK`).
- Ningún script productivo de las unidades cerradas fue reescrito a ciegas ni se enviaron contraseñas ni datos personales reales a herramientas de IA.
