-- ============================================================================
-- indices.sql — TP5, Parte A: índices aceptados tras medir.
--
-- Base: bd2_trabajo (copia de bd2_tp3). No modifica tablas ni restricciones:
-- solo agrega índices. Idempotente (DROP INDEX IF EXISTS antes de CREATE).
-- Evidencia: food-store/informe_mediciones.md y food-store/planes_tp5_parteA.txt.
-- Especificaciones: food-store/specs/spec_indice_*.md.
--
-- Protocolo (protocolo_seguridad.md): confirmar la base con
--   SELECT current_database();
-- y probar primero dentro de BEGIN; ... ROLLBACK; antes de repetir con COMMIT.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ACEPTADO — C1: catálogo vigente de una categoría ordenado por precio.
--
-- Consulta: SELECT id_producto, nombre, precio, stock FROM producto
--           WHERE id_categoria = 5 AND activo = TRUE ORDER BY precio DESC;
--
-- Qué cambia en el plan (medido sobre 50.011 productos, 10.047 filas):
--   antes  : Bitmap Heap Scan + Sort (quicksort, 932 kB)   10,5 ms, 527 buffers
--   después: Index Only Scan, sin Sort, Heap Fetches: 0     3,1 ms,  86 buffers
--
-- Diseño:
--   * (id_categoria, precio DESC): igualdad primero, orden después, para que
--     el índice entregue las filas ya ordenadas y desaparezca el Sort.
--   * WHERE activo = TRUE: índice parcial, igual que el del TP1; excluye la
--     baja lógica (R7) y mantiene el índice chico.
--   * INCLUDE (id_producto, nombre, stock): columnas que la consulta devuelve
--     pero no filtra ni ordena. Sin ellas el planificador ignora el índice y
--     sigue con Bitmap Heap Scan + Sort (ver descartes más abajo).
--
-- Costo: 3,3 MB (el índice del TP1 pesa 360 kB). Sobre las escrituras:
--   INSERT en producto  +45 % de WAL, +32 % de tiempo
--   UPDATE de stock     +32 % de WAL, +50 % de tiempo
--   INSERT en detalle_pedido y pedido: sin efecto (no toca esas tablas).
-- Requiere autovacuum al día: el Index Only Scan solo evita el heap mientras
-- las páginas estén marcadas como visibles (Heap Fetches: 0).
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_producto_categoria_precio;
CREATE INDEX idx_producto_categoria_precio
    ON producto (id_categoria, precio DESC)
    INCLUDE (id_producto, nombre, stock)
    WHERE activo = TRUE;

-- Recomendado tras crearlo, fuera de la transacción de prueba (VACUUM no corre
-- dentro de BEGIN): actualiza estadísticas y el mapa de visibilidad.
--   VACUUM ANALYZE producto;

-- ----------------------------------------------------------------------------
-- DESCARTADOS (no se ejecutan; quedan documentados con su motivo).
-- ----------------------------------------------------------------------------

-- DESCARTADO — C1, hipótesis de la spec, sin INCLUDE:
--   CREATE INDEX idx_producto_categoria_precio_parcial
--       ON producto (id_categoria, precio DESC) WHERE activo = TRUE;
-- El planificador no lo usa: sigue eligiendo idx_producto_categoria_activo
-- (Bitmap Heap Scan + Sort). Como el índice no contiene nombre ni stock, usarlo
-- exigiría una visita al heap por fila, y ese costo estimado supera al del
-- bitmap. Tiempo idéntico al base (10,5 ms). Índice muerto que igual se
-- mantiene en cada INSERT/UPDATE de producto (+27 % de WAL).

-- DESCARTADO — C2, sobreindexación (prefijo redundante):
--   CREATE INDEX idx_pedido_cliente_fecha ON pedido (id_cliente, fecha DESC);
-- La consulta devuelve 24 filas: ordenarlas cuesta microsegundos y el
-- planificador mantiene idx_pedido_id_cliente + Sort. Tiempo idéntico al base
-- (0,15 ms). Su primera columna repite el índice existente. Cuesta +26 % de
-- WAL en cada INSERT de pedido.

-- DESCARTADO — C3, sobreindexación (prefijo redundante):
--   CREATE INDEX idx_detalle_producto_pedido ON detalle_pedido (id_producto, id_pedido);
-- Es un superconjunto de idx_detalle_pedido_id_producto: el planificador lo
-- usa, pero el plan es el mismo (Bitmap Heap Scan, 27 bloques) y no mejora el
-- tiempo (pgbench: 0,68-0,86 ms base vs 0,73-0,78 ms, rangos superpuestos).
-- Además id_pedido ya está cubierto
-- por UNIQUE (id_pedido, id_producto). Cuesta +17 % de WAL en cada INSERT de
-- detalle_pedido.

-- DESCARTADO — consultas analíticas del TP4 (Seq Scan sobre detalle_pedido):
--   CREATE INDEX idx_detalle_pedido_producto_cubriente ON detalle_pedido (id_producto)
--       INCLUDE (id_pedido, cantidad, precio_unitario);
-- Las consultas leen el 100 % de las 499.263 filas: el planificador mantiene el
-- Seq Scan y el tiempo no cambia (727 ms vs 727 ms). El índice pesaría 24 MB.

-- Nota para la Semana 6: con idx_producto_categoria_precio, el índice
-- idx_producto_categoria_activo (schema.sql, TP1) queda redundante para esta
-- consulta. No se elimina acá porque este trabajo no modifica lo heredado.
