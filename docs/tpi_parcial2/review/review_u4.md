# Revisión de código asistida por IA — Unidad 4 (FNBC y desnormalización controlada)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `base-datos-2`
**Base de comprobación:** `bd2_tp4u4` (dentro de `BEGIN … ROLLBACK`)

---

## 1. Alcance de la revisión (9 scripts de la Unidad 4)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `food-store/tp_fnbc_control_lote.sql` | Esquema `control_lote_almacen`, demostración de las 3 anomalías con `SAVEPOINT`, descomposición en FNBC (`responsable_deposito` + `control_lote`), vista y `EXCEPT` en ambos sentidos | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.1) |
| `food-store/tp_fnbc_reversion.sql` | Plan y script de reversión transaccional desde FNBC hacia `control_lote_almacen` en orden de FK sin `CASCADE` y doble `EXCEPT` | Revisado con propuesta descartada (08/11/2026) | Hallazgo 15 |
| `food-store/carga_pedidos_hoy.sql` | Carga idempotente de 10.000 pedidos y ~20.000 detalles del día actual en `bd2_tp4u4` | Revisado con propuesta descartada (08/11/2026) | Hallazgo 15 |
| `food-store/medicion_top_categorias_antes.sql` | 6 corridas (1 warm-up + 5 medidas) de `EXPLAIN (ANALYZE, BUFFERS)` antes de desnormalizar | Revisado con propuesta descartada (08/11/2026) | Hallazgo 15 |
| `food-store/tp_desnormalizacion_top_categorias.sql` | Tabla `resumen_ventas_categoria_dia`, función `fn_resumen_ventas_aplicar_linea` y triggers de sincronización | Revisado y corregido | Hallazgo 3 |
| `food-store/medicion_top_categorias_despues.sql` | 6 corridas de `EXPLAIN (ANALYZE, BUFFERS)` sobre `resumen_ventas_categoria_dia` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |
| `food-store/medicion_escritura_top_categorias.sql` | Medición de sobrecosto de escritura (ms y WAL) en 500 `INSERT` con y sin trigger | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |
| `food-store/auditoria_top_categorias.sql` | Auditoría bidireccional (`EXCEPT` en ambos sentidos) del resumen contra el recálculo histórico sobre todos los días | Revisado con propuesta descartada (08/11/2026) | Hallazgo 15 |
| `food-store/tp_desnormalizacion_reversion.sql` | Reversión completa de la tabla resumen, triggers y funciones verificando conteos de `pedido` y `detalle_pedido` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.4) |

---

## 2. Revisión detallada de los scripts pendientes

### 2.1 `food-store/tp_fnbc_control_lote.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Comienza con `\set ON_ERROR_STOP on`, `BEGIN;` y `SELECT current_database();`, terminando en `ROLLBACK;` por omisión.
  - Usa `OVERRIDING SYSTEM VALUE` y `ON CONFLICT DO NOTHING` para insertar los usuarios de prueba `801` y `802` en la columna `GENERATED ALWAYS AS IDENTITY` de `usuario`.
  - Aísla cada una de las 3 anomalías (inserción, borrado y actualización) mediante `SAVEPOINT` y `ROLLBACK TO SAVEPOINT` para no contaminar la instancia antes de migrar a `responsable_deposito` ($R_1$) y `control_lote` ($R_2$).
  - Comprueba la descomposición sin pérdida con `EXCEPT` en ambas direcciones contra `v_control_lote_almacen` (`0 filas`).

### 2.2 `food-store/carga_pedidos_hoy.sql`, `medicion_top_categorias_antes.sql`, `auditoria_top_categorias.sql` y `tp_fnbc_reversion.sql` — Hallazgo 15

- **Propuesta 1 de la IA (en `carga_pedidos_hoy.sql` y `medicion_top_categorias_antes.sql`):** simplificar el predicado de rango `WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1` por `WHERE ped.fecha::date = CURRENT_DATE`, y en `auditoria_top_categorias.sql` cambiar `INNER JOIN` por `LEFT JOIN` desde `categoria`.
  - **Decisión humana:** **Descartado en ambos puntos.**
  - **Comprobación en el motor (`psql` sobre `bd2_tp4u4` dentro de `BEGIN … ROLLBACK`):**
    ```sql
    BEGIN;
    CREATE INDEX idx_tmp_fecha ON pedido(fecha);

    -- 1) Con cast sobre la columna (propuesta de la IA):
    EXPLAIN SELECT count(*) FROM pedido WHERE fecha::date = CURRENT_DATE;
    -- Plan: Parallel Seq Scan on pedido (cost=0.00..3882.76 rows=647 width=0)
    --       Filter: ((fecha)::date = CURRENT_DATE)

    -- 2) Con rango semiabierto (código actual del repo):
    EXPLAIN SELECT count(*) FROM pedido
    WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1;
    -- Plan: Index Only Scan using idx_tmp_fecha on pedido (cost=0.43..8.45 rows=1 width=0)
    --       Index Cond: ((fecha >= CURRENT_DATE) AND (fecha < (CURRENT_DATE + 1)))
    ROLLBACK;
    ```
  - **Motivo técnico:** aplicar `::date` sobre la columna `TIMESTAMPTZ` invalida cualquier índice B-tree sobre `pedido(fecha)` y obliga a convertir cada fila durante un `Seq Scan`, mientras que el rango `[CURRENT_DATE, CURRENT_DATE + 1)` bajo `SET timezone = 'America/Argentina/Mendoza'` es *sargable*. En cuanto a `auditoria_top_categorias.sql`, la tabla `resumen_ventas_categoria_dia` elimina las filas cuando `cantidad_lineas` llega a `0` y no guarda filas para categorías sin ventas; un `LEFT JOIN` produciría filas con `total_vendido = NULL` y `cantidad_lineas = 0` para `Congelados` (inactiva), haciendo fallar el `EXCEPT` o escondiendo discrepancias si no se cruza en ambos sentidos.

- **Propuesta 2 de la IA (en `tp_fnbc_reversion.sql`):** utilizar `DROP TABLE IF EXISTS responsable_deposito, control_lote CASCADE;` en el paso de reversión de FNBC y hacer `INSERT INTO control_lote_almacen ... ON CONFLICT DO NOTHING` sin vaciar antes `control_lote_almacen`.
  - **Decisión humana:** **Descartado y corregido** (registrado también en la bitácora del Bloque B).
  - **Comprobación en el motor (`food-store/tp_fnbc_reversion_salida.txt`):** se exige eliminar sin `CASCADE` respetando el árbol de dependencias (`1º DROP VIEW v_control_lote_almacen;` → `2º DROP TABLE control_lote;` que tiene la FK a $R_1$ → `3º DROP TABLE responsable_deposito;`), y se agregó `TRUNCATE TABLE control_lote_almacen;` tras tomar la foto `temp_pre_reversion` para demostrar que las 3 tuplas se reconstruyen íntegramente desde `control_lote NATURAL JOIN responsable_deposito`.

### 2.3 `food-store/medicion_top_categorias_despues.sql` y `medicion_escritura_top_categorias.sql` — Revisados sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - `medicion_top_categorias_despues.sql` fija `SET timezone = 'America/Argentina/Mendoza'`, corre en `BEGIN … ROLLBACK`, descarta la primera corrida (warm-up) y mide 5 corridas con `EXPLAIN (ANALYZE, BUFFERS)`.
  - `medicion_escritura_top_categorias.sql` crea la función de prueba en `pg_temp.medir_500_inserts()` para no ensuciar el esquema `public`, alterna 5 rondas `sin trigger` (`ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle` dentro de `BEGIN … ROLLBACK`) y `con trigger`, y mide tanto milisegundos como `pg_wal_lsn_diff()`.

### 2.4 `food-store/tp_desnormalizacion_reversion.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Captura con `\gset` el conteo de `pedido` y `detalle_pedido` antes de revertir, elimina primero los triggers (`trg_resumen_ventas_detalle` y `trg_resumen_ventas_pedido_borrado`), luego las funciones de trigger, la función dueña `fn_resumen_ventas_aplicar_linea` y finalmente la tabla `resumen_ventas_categoria_dia`, comprobando que `to_regclass('resumen_ventas_categoria_dia') IS NOT NULL` da `f` y que las tablas fuente conservan exactamente la misma cantidad de filas (`t`).
