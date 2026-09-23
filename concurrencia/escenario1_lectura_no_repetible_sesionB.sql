-- ============================================================
-- Escenario 1 — Lectura no repetible · SESION B (la que modifica)
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario1_lectura_no_repetible_sesionA.sql.
-- 'Agua mineral 2L' tiene stock 40 en el seed.
-- B no abre transaccion explicita: PostgreSQL aplica autocommit y cada
-- UPDATE queda confirmado al terminar (mismo metodo que el informe).
-- ============================================================

-- ------------------------------------------------------------
-- Fase 1 — READ COMMITTED
-- ------------------------------------------------------------
-- B1 — despues de que A ejecuto A2: modificar el stock a 99.
UPDATE producto SET stock = 99
WHERE nombre = 'Agua mineral 2L';

-- B2 — restaurar el stock del seed (40) antes de la fase 2.
UPDATE producto SET stock = 40
WHERE nombre = 'Agua mineral 2L';

-- ------------------------------------------------------------
-- Fase 2 — REPEATABLE READ
-- ------------------------------------------------------------
-- B3 — despues de que A ejecuto A6: modificar el stock a 7.
UPDATE producto SET stock = 7
WHERE nombre = 'Agua mineral 2L';

-- B4 — dejar la base como estaba.
UPDATE producto SET stock = 40
WHERE nombre = 'Agua mineral 2L';