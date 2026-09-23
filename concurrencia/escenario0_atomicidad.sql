-- ============================================================
-- Escenario 0 — Atomicidad, COMMIT y ROLLBACK
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Una sola sesion. Ejecutar sentencia por sentencia.
-- ============================================================
-- Productos usados:
--   'Pan de campo 1kg'   stock 12 en el seed.
--   'Gaseosa cola 2.25L' stock 1 en el seed.
-- El pedido del 2026-08-18 12:00 tiene una sola linea (Gaseosa cola):
-- la pareja (ese pedido, 'Pan de campo 1kg') esta libre y se usa como
-- linea de prueba. Los filtros se resuelven con subconsultas sobre
-- claves naturales; no hay id fijos.
-- ============================================================

-- ------------------------------------------------------------
-- Parte A — ROLLBACK: dos cambios se revierten juntos
-- ------------------------------------------------------------
BEGIN;

-- A1: el trigger de stock (Regla 2) valida: 2 <= 12. La linea es nueva.
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (2, 2500.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg'));

-- A2: descontar el stock (lo que haria la aplicacion).
UPDATE producto SET stock = stock - 2
WHERE nombre = 'Pan de campo 1kg';

-- A3: dentro de la transaccion todo se ve aplicado: la linea existe y
-- el stock paso de 12 a 10.
SELECT COUNT(*) AS lineas_pan_en_pedido_08_18
FROM detalle_pedido
WHERE id_pedido = (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03')
  AND id_producto = (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg');

SELECT stock
FROM producto
WHERE nombre = 'Pan de campo 1kg';

-- A4: revertir TODO junto.
ROLLBACK;

-- A5: verificar que no quedo nada: la linea no existe y el stock es 12.
SELECT COUNT(*) AS lineas_pan_en_pedido_08_18
FROM detalle_pedido
WHERE id_pedido = (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03')
  AND id_producto = (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg');

SELECT stock
FROM producto
WHERE nombre = 'Pan de campo 1kg';

-- ------------------------------------------------------------
-- Parte B — COMMIT: los mismos cambios quedan aplicados
-- ------------------------------------------------------------
BEGIN;

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (2, 2500.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg'));

UPDATE producto SET stock = stock - 2
WHERE nombre = 'Pan de campo 1kg';

-- B1: confirmar los dos cambios juntos.
COMMIT;

-- B2: verificar que ahora SI quedo: la linea esta y el stock es 10.
SELECT COUNT(*) AS lineas_pan_en_pedido_08_18
FROM detalle_pedido
WHERE id_pedido = (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03')
  AND id_producto = (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg');

SELECT stock
FROM producto
WHERE nombre = 'Pan de campo 1kg';

-- B3: dejar la base como estaba (quitar la linea de prueba y restaurar).
DELETE FROM detalle_pedido
WHERE id_pedido = (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03')
  AND id_producto = (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg');

UPDATE producto SET stock = 12
WHERE nombre = 'Pan de campo 1kg';

-- ------------------------------------------------------------
-- Parte C — Fallo parcial: el ERROR aborta toda la transaccion
-- ------------------------------------------------------------
BEGIN;

-- C1: un cambio valido.
UPDATE producto SET stock = 10
WHERE nombre = 'Pan de campo 1kg';

-- C2: una linea con cantidad 999 contra un stock de 1: el trigger de
-- stock (Regla 2) lanza ERROR. El UPDATE anterior tambien se revierte.
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (999, 3900.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Gaseosa cola 2.25L'));
--  -> ERROR: Stock insuficiente para el producto con id ...

-- C3: cerrar la transaccion abortada.
ROLLBACK;

-- C4: verificar que el UPDATE de C1 tambien se revirtio: stock 12.
SELECT stock
FROM producto
WHERE nombre = 'Pan de campo 1kg';
-- ============================================================
-- La atomicidad queda demostrada en las tres partes: todo lo de la
-- transaccion se aplica junto o no se aplica nada.
-- ============================================================