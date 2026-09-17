-- queries.sql — Consolidación de consultas del proyecto Food Store.
-- Extraídas textualmente de los informes en docs/. No reformuladas.
-- Cada bloque indica nombre, propósito y TP/informe de origen.

-- ==========================================================================
-- TP2 — Parte 2: laboratorio de índices  (docs/informe_parte2_indices.md)
-- ==========================================================================

-- C1 — Productos vigentes de la categoría 5.
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.id_categoria = 5 AND p.activo = TRUE
ORDER BY p.precio DESC;

-- C2 — Historial de pedidos del cliente 20155.
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.id_cliente = 20155
ORDER BY p.fecha DESC;

-- C3 — Pedidos donde se vendió el producto 49112.
SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE dp.id_producto = 49112
ORDER BY ped.fecha DESC;

-- ==========================================================================
-- TP4 — Parte 4: consultas resumen y subconsultas bajo especificación
-- (docs/informe_parte4_consultas.md)
-- ==========================================================================

-- Consulta A — Facturación por categoría (versión aceptada: LEFT JOIN + GROUP BY).
SELECT
    c.nombre AS nombre_categoria,
    COUNT(dp.id_detalle) AS cantidad_lineas_venta,
    COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS monto_total_facturado
FROM categoria c
LEFT JOIN producto p ON p.id_categoria = c.id_categoria AND p.activo = TRUE
LEFT JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE c.activo = TRUE
GROUP BY c.id_categoria, c.nombre
ORDER BY monto_total_facturado DESC;

-- Consulta B — Productos nunca vendidos (versión aceptada: NOT EXISTS).
SELECT id_producto, nombre, precio, stock
FROM producto
WHERE activo = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM detalle_pedido
      WHERE id_producto = producto.id_producto
  )
ORDER BY nombre ASC;

-- ==========================================================================
-- TP4 — Semana 4: consultas analíticas con JOIN  (docs/informe_tp4_semana4.md)
-- ==========================================================================

-- Consulta A — Facturación por categoría y mes (versión original; la reescritura se rechazó).
SELECT
    c.nombre AS categoria,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria AS c
JOIN producto AS p
    ON p.id_categoria = c.id_categoria
JOIN detalle_pedido AS dp
    ON dp.id_producto = p.id_producto
JOIN pedido AS pe
    ON pe.id_pedido = dp.id_pedido
WHERE c.activo = TRUE
  AND p.activo = TRUE
GROUP BY
    c.id_categoria,
    c.nombre,
    DATE_TRUNC('month', pe.fecha)
ORDER BY
    mes,
    facturacion_total DESC;

-- Consulta B — Ranking de clientes por gasto (reescritura aceptada, CTE por pedido).
WITH total_por_pedido AS (
    SELECT
        dp.id_pedido,
        SUM(dp.cantidad * dp.precio_unitario) AS total_pedido
    FROM detalle_pedido AS dp
    GROUP BY dp.id_pedido
)
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    COUNT(*) AS cantidad_pedidos,
    SUM(tpp.total_pedido) AS gasto_total
FROM total_por_pedido AS tpp
JOIN pedido AS pe
    ON pe.id_pedido = tpp.id_pedido
JOIN cliente AS c
    ON c.id_cliente = pe.id_cliente
GROUP BY
    c.id_cliente,
    c.nombre,
    c.apellido
ORDER BY
    gasto_total DESC;
