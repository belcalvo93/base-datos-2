-- ============================================================
-- Parte C -- Vista materializada de facturacion por categoria y mes
-- ============================================================
-- Reporte analitico de la Semana 4 (docs/informe_tp4_semana4.md, Consulta A).
-- Se materializa porque cada ejecucion cruza ~200.000 pedidos y ~500.000
-- lineas de detalle_pedido para devolver solo ~100 filas mensuales, con un
-- sort externo a disco. La vista guarda el resultado ya agregado: leerla es
-- leer 100 filas en fracciones de milisegundo.
--
-- La vista NO se actualiza sola: el dato queda congelado hasta el proximo
-- REFRESH MATERIALIZED VIEW. Frecuencia justificada en
-- informe_mediciones.md (Parte C).
--
-- Idempotente: DROP antes de CREATE (no existe CREATE OR REPLACE para
-- vistas materializadas), segun la convencion del repo.
-- ============================================================

DROP MATERIALIZED VIEW IF EXISTS mv_facturacion_cat_mes CASCADE;

CREATE MATERIALIZED VIEW mv_facturacion_cat_mes AS
SELECT
    c.id_categoria,
    c.nombre AS categoria,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria c
JOIN producto p       ON p.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
JOIN pedido pe        ON pe.id_pedido = dp.id_pedido
WHERE c.activo = TRUE AND p.activo = TRUE
GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', pe.fecha);

-- Indice unico: condicion obligatoria para poder usar
-- REFRESH MATERIALIZED VIEW CONCURRENTLY, que refresca sin bloquear a los
-- lectores. Sin el, el REFRESH toma un ACCESS EXCLUSIVE y el reporte queda
-- inaccesible mientras dura.
-- (id_categoria, mes) identifica una fila univocamente: el GROUP BY produce
-- exactamente una fila por combinacion categoria mes, sin nulos.
CREATE UNIQUE INDEX uq_mv_facturacion_cat_mes
    ON mv_facturacion_cat_mes (id_categoria, mes);

-- ============================================================
-- Verificacion (criterio de aceptacion de la spec): no ejecutar en cada
-- corrida. Las dos direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT * FROM mv_facturacion_cat_mes
-- EXCEPT
-- SELECT c.id_categoria, c.nombre,
--        DATE_TRUNC('month', pe.fecha),
--        COUNT(DISTINCT pe.id_pedido),
--        SUM(dp.cantidad * dp.precio_unitario)
-- FROM categoria c
-- JOIN producto p ON p.id_categoria = c.id_categoria
-- JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
-- JOIN pedido pe ON pe.id_pedido = dp.id_pedido
-- WHERE c.activo = TRUE AND p.activo = TRUE
-- GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', pe.fecha);
--
-- SELECT c.id_categoria, c.nombre,
--        DATE_TRUNC('month', pe.fecha),
--        COUNT(DISTINCT pe.id_pedido),
--        SUM(dp.cantidad * dp.precio_unitario)
-- FROM categoria c
-- JOIN producto p ON p.id_categoria = c.id_categoria
-- JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
-- JOIN pedido pe ON pe.id_pedido = dp.id_pedido
-- WHERE c.activo = TRUE AND p.activo = TRUE
-- GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', pe.fecha)
-- EXCEPT
-- SELECT * FROM mv_facturacion_cat_mes;
--
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_cat_mes;  -- debe correr sin error
-- ============================================================