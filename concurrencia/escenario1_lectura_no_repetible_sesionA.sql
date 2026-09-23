-- ============================================================
-- Escenario 1 — Lectura no repetible · SESION A (la que lee)
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario1_lectura_no_repetible_sesionB.sql.
-- 'Agua mineral 2L' tiene stock 40 en el seed.
-- ============================================================

-- ------------------------------------------------------------
-- Fase 1 — READ COMMITTED (nivel por defecto)
-- ------------------------------------------------------------
-- A1
BEGIN;

-- A2 — leer el stock: debe dar 40.
SELECT stock
  FROM producto
 WHERE nombre = 'Agua mineral 2L';

-- ESPERAR el paso B1 de la sesion B (UPDATE a 99 y confirmado).
-- Sin esa espera la prueba no reproduce la anomalia.

-- A3 — repetir la MISMA lectura dentro de la MISMA transaccion.
-- READ COMMITTED toma una foto nueva por sentencia: debe dar 99.
SELECT stock
  FROM producto
 WHERE nombre = 'Agua mineral 2L';

-- A4
ROLLBACK;

-- ------------------------------------------------------------
-- Fase 2 — REPEATABLE READ
-- ------------------------------------------------------------
-- A5
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- A6 — leer el stock: debe dar 40 (B2 ya lo restauro en el seed).
SELECT stock
  FROM producto
 WHERE nombre = 'Agua mineral 2L';

-- ESPERAR el paso B3 de la sesion B (UPDATE a 7 y confirmado).

-- A7 — repetir la lectura: REPEATABLE READ congelo la foto al inicio,
-- debe seguir dando 40 pese al UPDATE confirmado de B.
SELECT stock
  FROM producto
 WHERE nombre = 'Agua mineral 2L';

-- A8
ROLLBACK;