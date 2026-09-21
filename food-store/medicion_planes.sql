-- ============================================================================
-- medicion_planes.sql — TP5, Parte A, consigna 4: EXPLAIN antes y después.
--
-- Para cada consulta de queries.sql que se evaluó, imprime el plan sin el
-- índice candidato y con él. Cada "después" corre en su propia transacción
-- que termina en ROLLBACK: el índice de prueba desaparece y la base queda
-- intacta (protocolo_seguridad.md, paso 2).
--
-- Uso:
--   psql -U postgres -d bd2_trabajo -X -f food-store/medicion_planes.sql > food-store/planes_tp5_parteA.txt
--
-- Precondición: base restaurada y con estadísticas al día. Para que el
-- Index Only Scan del índice cubriente sea posible, el mapa de visibilidad de
-- producto tiene que estar actualizado:
--   VACUUM ANALYZE;
--
-- Antes de cada EXPLAIN se ejecuta la consulta una vez (calentamiento de
-- caché) para que el plan impreso corresponda a una ejecución en caliente.
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off
SELECT current_database() AS base_de_trabajo;

-- Consultas (texto idéntico al de food-store/queries.sql).
\set c1 'SELECT p.id_producto, p.nombre, p.precio, p.stock FROM producto p WHERE p.id_categoria = 5 AND p.activo = TRUE ORDER BY p.precio DESC'
\set c2 'SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente WHERE p.id_cliente = 20155 ORDER BY p.fecha DESC'
\set c3 'SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha FROM detalle_pedido dp JOIN pedido ped ON ped.id_pedido = dp.id_pedido WHERE dp.id_producto = 49112 ORDER BY ped.fecha DESC'

-- Índices candidatos.
\set i1_parcial   'CREATE INDEX idx_producto_categoria_precio_parcial ON producto (id_categoria, precio DESC) WHERE activo = TRUE'
\set i1_cubriente 'CREATE INDEX idx_producto_categoria_precio ON producto (id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo = TRUE'
\set i2           'CREATE INDEX idx_pedido_cliente_fecha ON pedido (id_cliente, fecha DESC)'
\set i3           'CREATE INDEX idx_detalle_producto_pedido ON detalle_pedido (id_producto, id_pedido)'

-- ---------------------------------------------------------------------------
-- C1 — productos vigentes de la categoría 5 (spec_indice_productos_categoria_precio.md)
-- ---------------------------------------------------------------------------
\echo
\echo '=== C1 ANTES (índices existentes del TP1) ==='
SELECT count(*) AS filas FROM (:c1) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c1;

\echo
\echo '=== C1 DESPUÉS: i1_parcial = (id_categoria, precio DESC) WHERE activo — hipótesis de la spec ==='
BEGIN;
:i1_parcial;
SELECT count(*) AS filas FROM (:c1) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c1;
ROLLBACK;

\echo
\echo '=== C1 DESPUÉS: i1_cubriente = i1_parcial + INCLUDE (id_producto, nombre, stock) — variante propuesta ==='
BEGIN;
:i1_cubriente;
SELECT count(*) AS filas FROM (:c1) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c1;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- C2 — historial de pedidos del cliente 20155 (spec_indice_pedidos_cliente_fecha.md)
-- ---------------------------------------------------------------------------
\echo
\echo '=== C2 ANTES (índices existentes del TP1) ==='
SELECT count(*) AS filas FROM (:c2) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c2;

\echo
\echo '=== C2 DESPUÉS: i2 = (id_cliente, fecha DESC) ==='
BEGIN;
:i2;
SELECT count(*) AS filas FROM (:c2) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c2;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- C3 — pedidos donde se vendió el producto 49112 (spec_indice_detalle_producto_pedido.md)
-- ---------------------------------------------------------------------------
\echo
\echo '=== C3 ANTES (índices existentes del TP1) ==='
SELECT count(*) AS filas FROM (:c3) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c3;

\echo
\echo '=== C3 DESPUÉS: i3 = (id_producto, id_pedido) ==='
BEGIN;
:i3;
SELECT count(*) AS filas FROM (:c3) q;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) :c3;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- Consultas analíticas del TP4: son las que hoy sí resuelven con Seq Scan
-- sobre detalle_pedido. Se prueba si un índice cubriente lo evita.
-- ---------------------------------------------------------------------------
\set t4a 'SELECT c.nombre AS nombre_categoria, COUNT(dp.id_detalle) AS cantidad_lineas_venta, COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS monto_total_facturado FROM categoria c LEFT JOIN producto p ON p.id_categoria = c.id_categoria AND p.activo = TRUE LEFT JOIN detalle_pedido dp ON dp.id_producto = p.id_producto WHERE c.activo = TRUE GROUP BY c.id_categoria, c.nombre ORDER BY monto_total_facturado DESC'
\set t4b 'SELECT id_producto, nombre, precio, stock FROM producto WHERE activo = TRUE AND NOT EXISTS (SELECT 1 FROM detalle_pedido WHERE id_producto = producto.id_producto) ORDER BY nombre ASC'
\set s4a 'SELECT c.nombre AS categoria, DATE_TRUNC(''month'', pe.fecha) AS mes, COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos, SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total FROM categoria AS c JOIN producto AS p ON p.id_categoria = c.id_categoria JOIN detalle_pedido AS dp ON dp.id_producto = p.id_producto JOIN pedido AS pe ON pe.id_pedido = dp.id_pedido WHERE c.activo = TRUE AND p.activo = TRUE GROUP BY c.id_categoria, c.nombre, DATE_TRUNC(''month'', pe.fecha) ORDER BY mes, facturacion_total DESC'
\set s4b 'WITH total_por_pedido AS (SELECT dp.id_pedido, SUM(dp.cantidad * dp.precio_unitario) AS total_pedido FROM detalle_pedido AS dp GROUP BY dp.id_pedido) SELECT c.id_cliente, c.nombre, c.apellido, COUNT(*) AS cantidad_pedidos, SUM(tpp.total_pedido) AS gasto_total FROM total_por_pedido AS tpp JOIN pedido AS pe ON pe.id_pedido = tpp.id_pedido JOIN cliente AS c ON c.id_cliente = pe.id_cliente GROUP BY c.id_cliente, c.nombre, c.apellido ORDER BY gasto_total DESC'
\set i4 'CREATE INDEX idx_detalle_pedido_producto_cubriente ON detalle_pedido (id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)'

\echo
\echo '=== TP4 Consulta A (facturación por categoría) — ANTES ==='
SELECT count(*) AS filas FROM (:t4a) q;
EXPLAIN (ANALYZE, BUFFERS) :t4a;
\echo
\echo '=== TP4 Consulta B (productos nunca vendidos) — ANTES ==='
SELECT count(*) AS filas FROM (:t4b) q;
EXPLAIN (ANALYZE, BUFFERS) :t4b;
\echo
\echo '=== TP4 Semana 4 Consulta A (facturación por categoría y mes) — ANTES ==='
SELECT count(*) AS filas FROM (:s4a) q;
EXPLAIN (ANALYZE, BUFFERS) :s4a;
\echo
\echo '=== TP4 Semana 4 Consulta B (ranking de clientes por gasto) — ANTES ==='
SELECT count(*) AS filas FROM (:s4b) q;
EXPLAIN (ANALYZE, BUFFERS) :s4b;

\echo
\echo '=== TP4 Consulta B — con enable_seqscan = off (qué haría el índice existente si se lo obligara) ==='
BEGIN;
SET LOCAL enable_seqscan = off;
SELECT count(*) AS filas FROM (:t4b) q;
EXPLAIN (ANALYZE, BUFFERS) :t4b;
ROLLBACK;

\echo
\echo '=== TP4 Consulta A y Semana 4 A — DESPUÉS de i4 = (id_producto) INCLUDE (id_pedido, cantidad, precio_unitario) ==='
BEGIN;
:i4;
SELECT count(*) AS filas FROM (:t4a) q;
EXPLAIN (ANALYZE, BUFFERS) :t4a;
SELECT count(*) AS filas FROM (:s4a) q;
EXPLAIN (ANALYZE, BUFFERS) :s4a;
ROLLBACK;
