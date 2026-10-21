-- ============================================================
-- TP U4 — Parte 2 (d): medición DESPUÉS de desnormalizar
-- Spec: food-store/specs/spec_top_categorias_desnormalizacion.md
-- Base de ejecución: bd2_tp4u4, con tp_desnormalizacion_top_categorias.sql
-- ya confirmado y VACUUM ANALYZE resumen_ventas_categoria_dia hecho.
-- Solo lectura (SELECT), dentro de BEGIN…ROLLBACK.
-- ============================================================
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/medicion_top_categorias_despues.sql
-- Mismo formato que medicion_top_categorias_antes.sql: 6 corridas, la 1.ª
-- es warm-up y se descarta; la mediana sale de las otras 5. Hay que
-- correrlo el mismo día que el "antes".
-- ============================================================

\set ON_ERROR_STOP on

SELECT current_database();

SET timezone = 'America/Argentina/Mendoza';

BEGIN;

-- Contexto: tamaño del resumen contra el de la tabla que recorría la consulta original
SELECT (SELECT count(*) FROM resumen_ventas_categoria_dia) AS filas_resumen,
       (SELECT count(*) FROM detalle_pedido)               AS detalles_total;

-- Corrida 1 (warm-up, se descarta)
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

-- Corrida 2
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

-- Corrida 3
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

-- Corrida 4
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

-- Corrida 5
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

-- Corrida 6
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;

ROLLBACK;
