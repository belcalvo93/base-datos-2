-- ============================================================
-- TP U4 — Carga de pedidos de HOY (insumo de la Parte 2)
-- Spec: food-store/specs/spec_carga_pedidos_hoy.md
-- Base de ejecución: bd2_tp4u4 (copia de bd2_tp3). NUNCA bd2_tp3 ni bd2_proyecto.
-- ============================================================
-- Protocolo (protocolo_seguridad.md):
--   1. Backup antes del COMMIT:
--        pg_dump -U postgres -F c -f "food-store/backups/bd2_tp4u4_YYYYMMDD.dump" bd2_tp4u4
--   2. Primera corrida con ROLLBACK (como está). Inspeccionar la salida.
--   3. Segunda corrida: cambiar el ROLLBACK final por COMMIT.
--   4. Ejecutar el VACUUM ANALYZE del final (fuera de la transacción).
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/carga_pedidos_hoy.sql
-- ============================================================

\set ON_ERROR_STOP on

-- Verificar que estamos en la base correcta (debe decir bd2_tp4u4)
SELECT current_database();

-- Zona horaria explícita: define qué es "hoy" (Argentina)
SET timezone = 'America/Argentina/Mendoza';

BEGIN;

-- ------------------------------------------------------------
-- 0. Idempotencia: borrar SOLO los pedidos de hoy.
--    Los detalles caen por ON DELETE CASCADE (detalle_pedido.id_pedido).
--    La carga masiva del TP3 distribuyó pedidos en 2 años, así que
--    el rango de hoy es el único afectado.
-- ------------------------------------------------------------
DELETE FROM pedido
 WHERE fecha >= CURRENT_DATE
   AND fecha <  CURRENT_DATE + 1;

-- ------------------------------------------------------------
-- 1. PEDIDOS: 10.000 pedidos entre las 00:00 de hoy y ahora.
--    - fecha: medianoche local + fracción aleatoria de lo transcurrido
--      (nunca en el futuro).
--    - forma_pago: reparto uniforme (~33% cada una).
--    - id_cliente: subquery correlacionado con "+ s.i * 0" para que se
--      evalúe por fila (si no, se repite el mismo cliente; ver
--      carga_masiva.sql).
-- ------------------------------------------------------------
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT
    CURRENT_DATE + random() * (now() - CURRENT_DATE),
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA']::forma_pago_enum[])[floor(random() * 3 + 1)],
    (SELECT id_cliente FROM cliente ORDER BY random() + s.i * 0 LIMIT 1)
FROM generate_series(1, 10000) AS s(i);

-- ------------------------------------------------------------
-- 2. DETALLES: 1 a 3 líneas por pedido (promedio ~2).
--    - Solo productos vendibles: activo = TRUE y stock >= 3, para no
--      disparar trg_verificar_producto_activo ni
--      trg_verificar_stock_suficiente (cantidad máxima = 3).
--    - precio_unitario = precio actual (valor histórico congelado, R4).
--    - Sorteo de producto: se numera la lista de vendibles una vez
--      (tabla temporal) y se elige un número al azar por línea. Evita
--      ordenar los ~50k productos por cada pedido.
--    - Puede salir el mismo producto dos veces en un pedido:
--      ON CONFLICT DO NOTHING respeta UNIQUE (id_pedido, id_producto)
--      y deja ese pedido con una línea menos.
--    - Se inserta directo (sin registrar_pedido), por lo que el stock
--      NO se descuenta. Documentar en el informe.
-- ------------------------------------------------------------
CREATE TEMP TABLE tmp_vendibles ON COMMIT DROP AS
SELECT ROW_NUMBER() OVER (ORDER BY id_producto) AS rn,
       id_producto,
       precio
  FROM producto
 WHERE activo = TRUE
   AND stock >= 3;

WITH
pedidos_hoy AS (
    SELECT id_pedido, (random() * 2 + 1)::INTEGER AS n_lineas
      FROM pedido
     WHERE fecha >= CURRENT_DATE
       AND fecha <  CURRENT_DATE + 1
),
lineas AS MATERIALIZED (
    SELECT ph.id_pedido,
           1 + floor(random() * (SELECT count(*) FROM tmp_vendibles))::BIGINT AS rn
      FROM pedidos_hoy ph
     CROSS JOIN LATERAL generate_series(1, ph.n_lineas) AS g(k)
)
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
SELECT (random() * 2 + 1)::INTEGER,   -- cantidad 1..3
       v.precio,
       l.id_pedido,
       v.id_producto
  FROM lineas l
  JOIN tmp_vendibles v ON v.rn = l.rn
ON CONFLICT (id_pedido, id_producto) DO NOTHING;

-- ------------------------------------------------------------
-- 3. VERIFICACIÓN (inspeccionar antes de pasar a COMMIT)
-- ------------------------------------------------------------
-- 3.1 Pedidos de hoy: esperado 10000
SELECT count(*) AS pedidos_hoy
  FROM pedido
 WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1;

-- 3.2 Detalles de hoy: esperado ~20000
SELECT count(*) AS detalles_hoy
  FROM detalle_pedido dp
  JOIN pedido ped ON ped.id_pedido = dp.id_pedido
 WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1;

-- 3.3 Variedad: productos y categorías distintos vendidos hoy
SELECT count(DISTINCT dp.id_producto) AS productos_distintos,
       count(DISTINCT pr.id_categoria) AS categorias_distintas
  FROM detalle_pedido dp
  JOIN pedido ped  ON ped.id_pedido   = dp.id_pedido
  JOIN producto pr ON pr.id_producto  = dp.id_producto
 WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1;

-- 3.4 Reparto de forma_pago (~33% cada una)
SELECT forma_pago, count(*) AS cantidad
  FROM pedido
 WHERE fecha >= CURRENT_DATE AND fecha < CURRENT_DATE + 1
 GROUP BY forma_pago
 ORDER BY forma_pago;

-- 3.5 Consulta adaptada del punto 5.1: debe devolver EXACTAMENTE 5 filas
SELECT c.nombre AS categoria,
       SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
  FROM detalle_pedido dp
  JOIN producto  pr  ON pr.id_producto  = dp.id_producto
  JOIN categoria c   ON c.id_categoria  = pr.id_categoria
  JOIN pedido    ped ON ped.id_pedido   = dp.id_pedido
 WHERE ped.fecha >= CURRENT_DATE
   AND ped.fecha <  CURRENT_DATE + 1
 GROUP BY c.nombre
 ORDER BY total_vendido DESC
 LIMIT 5;

-- Primera corrida: ROLLBACK. Para aplicar de verdad, cambiar por COMMIT.
COMMIT;

-- ------------------------------------------------------------
-- 4. Después del COMMIT (descomentar y correr aparte; VACUUM no corre
--    dentro de una transacción). Necesario para planes representativos.
-- ------------------------------------------------------------
-- VACUUM ANALYZE pedido;
-- VACUUM ANALYZE detalle_pedido;
