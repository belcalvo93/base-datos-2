-- ============================================================
-- Pruebas de las restricciones de integridad
-- ============================================================
-- Cada caso se ejecuta dentro de BEGIN … ROLLBACK para no
-- modificar los datos de prueba. Si el trigger funciona
-- correctamente, el INSERT debe fallar y el ROLLBACK revierte
-- cualquier cambio parcial.
--
-- Correr este archivo completo contra bd2_trabajo.
-- Se espera que los casos 1 y 3 fallen (RAISE EXCEPTION)
-- y que los casos 2 y 4 se inserten exitosamente pero se
-- reviertan con el ROLLBACK final.
-- ============================================================

-- ------------------------------------------------------------
-- Caso 1 — Producto inactivo: Helado 1L (activo = FALSE)
-- Resultado esperado: RECHAZADO por la Regla 1
-- ------------------------------------------------------------
BEGIN;

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (1, 9500.00,
    (SELECT id_pedido FROM pedido LIMIT 1),
    (SELECT id_producto FROM producto WHERE nombre = 'Helado 1L'));

ROLLBACK;


-- ------------------------------------------------------------
-- Caso 2 — Producto activo con stock suficiente
-- Agua mineral 2L: cantidad 2, stock 40
-- Resultado esperado: ACEPTADO
-- ------------------------------------------------------------
BEGIN;

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (2, 1400.00,
    (SELECT id_pedido FROM pedido LIMIT 1),
    (SELECT id_producto FROM producto WHERE nombre = 'Agua mineral 2L'));

ROLLBACK;


-- ------------------------------------------------------------
-- Caso 3 — Stock insuficiente
-- Gaseosa cola 2.25L: cantidad 50, stock 1
-- Resultado esperado: RECHAZADO por la Regla 2
-- ------------------------------------------------------------
BEGIN;

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (50, 3900.00,
    (SELECT id_pedido FROM pedido LIMIT 1),
    (SELECT id_producto FROM producto WHERE nombre = 'Gaseosa cola 2.25L'));

ROLLBACK;


-- ------------------------------------------------------------
-- Caso 4 — Límite exacto de stock (cantidad = stock)
-- Medialunas x6: cantidad 3, stock 3
-- Resultado esperado: ACEPTADO (el límite es válido)
-- ------------------------------------------------------------
BEGIN;

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
VALUES (3, 3200.00,
    (SELECT id_pedido FROM pedido LIMIT 1),
    (SELECT id_producto FROM producto WHERE nombre = 'Medialunas x6'));

ROLLBACK;
