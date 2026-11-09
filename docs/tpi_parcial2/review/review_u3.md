# Revisión de código asistida por IA — Unidad 3 (Índices, vistas y rendimiento)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `base-datos-2`
**Base de comprobación:** `bd2_trabajo` y `bd2_tp5u5` (dentro de `BEGIN … ROLLBACK`)

---

## 1. Alcance de la revisión (6 scripts de la Unidad 3)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `food-store/indices.sql` | Creación idempotente del índice cubriente aceptado (`idx_producto_categoria_precio`) y registro documentado de los 5 índices descartados | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.1) |
| `food-store/queries.sql` | Consolidación de las 10 consultas de análisis y reporte (C1–C3, TP4 A/B, Semana 4 A/B, funciones de ventana `RANK`/`LAG` y `HAVING`) | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.2) |
| `food-store/medicion_planes.sql` | Medición reproducible con `EXPLAIN (ANALYZE, BUFFERS)` antes y después de cada índice candidato dentro de `BEGIN … ROLLBACK` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |
| `food-store/medicion_escritura.sql` | Medición de tiempo y bytes de WAL (`pg_wal_lsn_diff`) para 500 `INSERT` y 500 `UPDATE` bajo cada configuración de índices | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.4) |
| `food-store/views.sql` | 5 vistas (`vista_cliente_completo`, `vista_pedidos_cliente`, `vista_productos_vigentes`, `vista_detalle_pedido_producto`, `vista_usuario_reportes`) y `GRANT` inicial | Revisado con observación documentada (08/11/2026) | Hallazgo 14 |
| `food-store/materializadas.sql` | Vista materializada `mv_facturacion_cat_mes` con índice único `uq_mv_facturacion_cat_mes` para refresco concurrente | Revisado con propuesta descartada (08/11/2026) | Hallazgo 14 |

---

## 2. Revisión detallada de los scripts

### 2.1 `food-store/indices.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Es idempotente (`DROP INDEX IF EXISTS idx_producto_categoria_precio;` antes de `CREATE INDEX`).
  - Justifica con números medidos por qué el índice parcial cubriente `ON producto (id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo = TRUE` logra un `Index Only Scan` (`Heap Fetches: 0`, bajando de 10,5 ms / 527 buffers a 3,1 ms / 86 buffers), mientras que la variante sin `INCLUDE` es ignorada por el planificador.
  - Documenta los 5 índices descartados con su sobrepeso en WAL (+17 % a +27 %) y por qué los índices sobre `detalle_pedido` no aceleran consultas que agregan el 100 % de las 499.263 filas.

### 2.2 `food-store/queries.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Script exclusivamente de lectura (`SELECT`).
  - Las consultas respetan la semántica de negocio: usan `COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0)` en los `LEFT JOIN` para no devolver `NULL` en categorías o productos sin ventas, `NOT EXISTS` para productos nunca vendidos, y desempate determinista `ORDER BY pe.fecha, pe.id_pedido` en la ventana de `LAG(...)`.

### 2.3 `food-store/medicion_planes.sql` y `food-store/medicion_escritura.sql` — Revisados sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Ambos scripts empiezan con `\set ON_ERROR_STOP on` y `SELECT current_database()`.
  - Ninguno deja índices de prueba instalados: cada escenario corre dentro de `BEGIN; :indice; … ROLLBACK;`.
  - `medicion_escritura.sql` precalcula las 500 filas en tablas temporales fuera de la ventana cronometrada, realiza una corrida de calentamiento previa para compilar los planes de los triggers de `restricciones.sql`, ejecuta `VACUUM` después de cada `ROLLBACK` para que las tuplas abortadas no sesguen el estado siguiente y mide `base_a` (al inicio) y `base_b` (al final) junto con `pg_wal_lsn_diff()`.

### 2.4 `food-store/materializadas.sql` y `food-store/views.sql` — Hallazgo 14

- **Propuesta 1 de la IA (en `materializadas.sql`):** prescindir de la vista materializada `mv_facturacion_cat_mes` y crear en su lugar un índice expresional sobre la tabla `pedido` con `CREATE INDEX idx_pedido_mes ON pedido (DATE_TRUNC('month', fecha));`.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en el motor (`psql` sobre `bd2_trabajo` dentro de `BEGIN … ROLLBACK`):**
    ```sql
    BEGIN;
    CREATE INDEX idx_test_mes ON pedido (DATE_TRUNC('month', fecha));
    ROLLBACK;
    -- Salida del motor:
    -- ERROR:  las funciones utilizadas en expresiones de índice deben estar marcadas IMMUTABLE
    ```
  - **Motivo técnico:** en PostgreSQL, `pedido.fecha` es de tipo `TIMESTAMPTZ`. El resultado de `DATE_TRUNC('month', timestamptz)` depende de la zona horaria activa de la sesión (`TimeZone`), por lo que la función está catalogada como `STABLE` y no `IMMUTABLE` (`SQLSTATE 42P17`). Además, la consulta agrega el histórico completo de `detalle_pedido` (499.263 filas) sin filtrar por un mes puntual: un índice en `pedido` no evita el barrido ni el `HashAggregate`, mientras que la vista materializada precalcula las ~125 filas mensuales y su índice único `uq_mv_facturacion_cat_mes (id_categoria, mes)` (sobre la columna `mes` ya materializada) habilita `REFRESH MATERIALIZED VIEW CONCURRENTLY` sin bloquear lecturas.

- **Observación 2 de la IA (en `views.sql`):** el bloque final de `food-store/views.sql` (líneas 170–178) crea el rol `rol_reportes` con atributo `LOGIN PASSWORD 'reportes123'` y le otorga `GRANT SELECT ON vista_usuario_reportes TO rol_reportes;`, lo cual difiere del diseño final de seguridad de la Unidad 5 donde `rol_reportes` es un rol de grupo (`NOLOGIN`) y solo puede leer `mv_ventas_categoria_mes`.
  - **Decisión humana:** **Aceptado y resuelto en la Unidad 5 (`sql/roles.sql`), sin alterar el entregable histórico de la Unidad 3.**
  - **Comprobación en el motor (`bd2_tp5u5`, documentada en `docs/decisiones_auditoria_roles.md` bajo `H3`, `F1` y `R2`):** en la Unidad 3 ese bloque respondió al pedido puntual del TP5 Parte B (demostrar el `SELECT` sobre una vista ocultando la columna `contrasena` de la tabla base `usuario`). En la Unidad 5 (`sql/roles.sql`), el script convierte a `rol_reportes` en `NOLOGIN PASSWORD NULL`, revoca `SELECT ON vista_usuario_reportes` y separa la identidad de conexión en `rol_reportes_login`. En `docs/verificacion_roles.txt` se comprueba con `SET ROLE rol_reportes_login; SELECT count(*) FROM vista_usuario_reportes;` que el motor devuelve `ERROR: permiso denegado a la vista vista_usuario_reportes`.
