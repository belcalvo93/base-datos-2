-- =====================================================================
-- mv_ventas_categoria_mes.sql — Food Store, TP Unidad 5 (Parte A.2)
-- Orden: 2. Crea el agregado del panel gerencial. Sin GRANT/REVOKE:
-- el SELECT para rol_reportes se otorga en roles.sql (último).
-- =====================================================================

-- No existe CREATE OR REPLACE para vistas materializadas: se recrea.
DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_mes;

-- Agregado por categoría y mes. Sin filtro de activo: el histórico de ventas
-- debe conservarse aunque hoy la categoría o el producto estén dados de baja.
CREATE MATERIALIZED VIEW mv_ventas_categoria_mes AS
SELECT
    c.nombre                              AS categoria,
    DATE_TRUNC('month', pe.fecha)         AS mes,
    SUM(dp.cantidad * dp.precio_unitario) AS total_ventas,
    COUNT(DISTINCT pe.id_pedido)          AS cantidad_pedidos,
    SUM(dp.cantidad)                      AS unidades_vendidas
FROM categoria c
JOIN producto p        ON p.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
JOIN pedido pe         ON pe.id_pedido = dp.id_pedido
GROUP BY c.nombre, DATE_TRUNC('month', pe.fecha)
WITH DATA;
