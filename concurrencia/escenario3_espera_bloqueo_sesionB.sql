-- ============================================================
-- Escenario 3 — Control de concurrencia: espera por bloqueo · SESION B
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario3_espera_bloqueo_sesionA.sql.
-- 'Gaseosa cola 2.25L' tiene stock 1 en el seed.
-- ============================================================
-- En psql conviene activar el timing para medir la espera:
--   \timing on
-- En DBeaver el tiempo queda visible al pie del resultado.
-- La espera no deja marca en el valor devuelto (es el mismo 1): la unica
-- evidencia es el tiempo transcurrido, como se midio en el informe
-- (0,316 ms sin bloqueo vs 31.170,470 ms bloqueado).

-- B1
BEGIN;

-- B2 — pedir el mismo bloqueo que la sesion A tomo en A2: la sesion
-- QUEDA ESPERANDO hasta que A ejecute el COMMIT (A3). No devuelve nada
-- ni falla mientras tanto.
SELECT stock
  FROM producto
 WHERE nombre = 'Gaseosa cola 2.25L'
   FOR UPDATE;
-- -> (se destraba cuando A hace COMMIT y devuelve 1, tras ~30 s)

-- B3
ROLLBACK;