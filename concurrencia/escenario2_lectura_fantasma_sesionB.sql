-- ============================================================
-- Escenario 2 — Lectura fantasma · SESION B (la que inserta)
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario2_lectura_fantasma_sesionA.sql.
-- Las filas que inserta este script son de prueba: se eliminan al
-- terminar cada fase para que la corrida sea reejecutable sin recrear
-- la base.
-- ============================================================

-- ------------------------------------------------------------
-- Fase 1 — READ COMMITTED
-- ------------------------------------------------------------
-- B1 — despues de que A ejecuto A2: insertar un producto nuevo en
-- Bebidas (autocommit: queda confirmado).
INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria)
VALUES ('Cerveza 1L', 'Producto de prueba del escenario 2', 4500.00, 10, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'));

-- B2 — despues de que A ejecuto A4: quitar la fila de prueba.
DELETE FROM producto WHERE nombre = 'Cerveza 1L';

-- ------------------------------------------------------------
-- Fase 2 — REPEATABLE READ
-- ------------------------------------------------------------
-- B3 — despues de que A ejecuto A6: insertar otra fila de prueba.
INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria)
VALUES ('Agua saborizada 1.5L', 'Producto de prueba del escenario 2', 2600.00, 22, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'));

-- B4 — despues de que A ejecuto A9: quitar la fila de prueba.
DELETE FROM producto WHERE nombre = 'Agua saborizada 1.5L';