-- ============================================================
-- TP U4 — Parte 2 (a): medición basal, ANTES de desnormalizar
-- Spec: food-store/specs/spec_top_categorias_antes.md
-- Base de ejecución: bd2_tp4u4. Solo lectura (SELECT), dentro de BEGIN…ROLLBACK.
-- ============================================================
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/medicion_top_categorias_antes.sql
-- Se hacen 6 corridas: la 1.ª es warm-up (se descarta); la mediana se
-- calcula sobre las otras 5 ("Execution Time" de cada plan).
-- ============================================================

\set ON_ERROR_STOP on

SELECT current_database();

-- Mismo día de negocio que usará la desnormalización
SET timezone = 'America/Argentina/Mendoza';

BEGIN;

-- Contexto de la medición: volumen del día y de la tabla
SELECT count(*) AS pedidos_hoy
  FROM pedido
 WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1;

SELECT (SELECT count(*) FROM pedido)         AS pedidos_total,
       (SELECT count(*) FROM detalle_pedido) AS detalles_total;

-- Corrida 1 (warm-up, se descarta)
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

-- Corrida 2
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

-- Corrida 3
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

-- Corrida 4
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

-- Corrida 5
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

-- Corrida 6
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;

ROLLBACK;
