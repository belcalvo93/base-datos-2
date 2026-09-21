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

-- Consultas analíticas del TP4 (hacen Seq Scan sobre detalle_pedido). Se
-- especificaron en Kiro y se le pidió a OpenCode una propuesta por consulta
-- (specs spec_indice_facturacion_categoria*.md y spec_indice_productos_nunca_vendidos.md).
-- En las tres, OpenCode concluyó «ningún índice»; la medición lo confirma.

-- DESCARTADO — P4-A, facturación por categoría (727 ms):
--   CREATE INDEX idx_detalle_pedido_producto_cubriente ON detalle_pedido (id_producto)
--       INCLUDE (id_detalle, cantidad, precio_unitario);
-- Es el índice cubriente que la consulta necesita (usa id_detalle en COUNT, por
-- eso lo incluye). El planificador lo ignora y sigue con Seq Scan (misma corrida: 743 ms sin
-- índice vs 735 ms con él). La consulta agrega el 100 % de las 499.263 filas y el
-- índice pesa 24 MB frente a los 33 MB de la tabla, así que leerlo no ahorra
-- lectura. Cuesta además +21 % de WAL en cada INSERT de detalle_pedido.
-- No cumple las condiciones 1 (el Seq Scan no desaparece) ni 2 (mejora < 30 %).

-- DESCARTADO — P4-B, productos nunca vendidos (259 ms): sin índice nuevo.
-- Ya existe idx_detalle_pedido_id_producto (4,5 MB) y permite un Index Only Scan.
-- El planificador no lo elige por sus estimaciones de costo (17.586 contra
-- 18.338, casi empate): con random_page_cost = 1.1 lo usa solo y la consulta baja
-- a 110 ms (2,3×), y forzando enable_seqscan = off da 112 ms. No falta un índice;
-- un segundo índice sobre id_producto sería una copia del existente. No se
-- cambia random_page_cost: es un parámetro del servidor, fuera de esta parte.

-- DESCARTADO — S4-A, facturación por categoría y mes (2.219 ms):
--   CREATE INDEX idx_detalle_pedido_producto_cubriente ON detalle_pedido (id_producto)
--       INCLUDE (id_pedido, cantidad, precio_unitario);
-- Este índice sí contiene todas las columnas que S4-A usa de detalle_pedido.
-- Plan y tiempo no cambian (2.219 ms vs 2.246 ms): agrega todo el histórico y el
-- costo está en el Hash Join, la agregación y el ordenamiento externo (23 MB a
-- disco), no en el acceso. La mejora corresponde a la vista materializada de la
-- Parte C.

-- Nota para la Semana 6: con idx_producto_categoria_precio, el índice
-- idx_producto_categoria_activo (schema.sql, TP1) queda redundante para esta
-- consulta. No se elimina acá porque este trabajo no modifica lo heredado.
