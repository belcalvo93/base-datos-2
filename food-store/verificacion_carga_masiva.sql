-- ============================================================
-- Verificación de carga masiva — consultas READ ONLY
-- ============================================================
-- Uso: ejecutar dentro de la misma transacción de la carga (antes
-- del ROLLBACK/COMMIT) o contra la base ya cargada.
-- Los LIMIT deben copiar el volumen del bloque correspondiente.
-- ============================================================

-- ------------------------------------------------------------
-- BLOQUE 1 — distribución de id_categoria SOLO entre las filas
-- recién insertadas (las últimas por id_producto).
-- Roto: una sola fila con las 10.000. (count(DISTINCT) no sirve:
-- hay 5 categorías, da 5 esté roto o arreglado.)
-- Arreglado: las 5 categorías con ~2.000 cada una.
-- ------------------------------------------------------------
WITH recientes AS (
    SELECT id_categoria
    FROM producto
    ORDER BY id_producto DESC
    LIMIT 10000
)
SELECT c.nombre, COUNT(*) AS productos
FROM recientes r
JOIN categoria c USING (id_categoria)
GROUP BY c.nombre
ORDER BY productos DESC;

-- Control de cobertura: debe sumar exactamente el volumen del
-- bloque 1 (10.000 si el número de arriba está calibrado).
SELECT COUNT(*) AS total_recientes
FROM (
    SELECT id_producto
    FROM producto
    ORDER BY id_producto DESC
    LIMIT 10000
) t;

-- ------------------------------------------------------------
-- BLOQUE 3 — salud de id_cliente entre las filas recién
-- insertadas (las últimas por id_pedido). Útil para comparar las
-- variantes A y B a igual volumen.
-- Roto (InitPlan): 1 solo cliente con las 10.000.
-- Arreglado: ~4.000 clientes distintos.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS pedidos_recientes,
    COUNT(DISTINCT id_cliente) AS clientes_distintos
FROM (
    SELECT id_cliente
    FROM pedido
    ORDER BY id_pedido DESC
    LIMIT 10000
) t;

-- Histograma: los clientes con más pedidos. Roto: una fila con
-- 10.000. Arreglado: valores chicos (~2-5 por cliente).
SELECT id_cliente, COUNT(*) AS pedidos
FROM (
    SELECT id_cliente
    FROM pedido
    ORDER BY id_pedido DESC
    LIMIT 10000
) t
GROUP BY id_cliente
ORDER BY pedidos DESC
LIMIT 10;