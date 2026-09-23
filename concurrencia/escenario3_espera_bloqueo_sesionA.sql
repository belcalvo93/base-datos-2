-- ============================================================
-- Escenario 3 — Control de concurrencia: espera por bloqueo · SESION A
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario3_espera_bloqueo_sesionB.sql.
-- 'Gaseosa cola 2.25L' tiene stock 1 en el seed.
-- ============================================================

-- A1
BEGIN;

-- A2 — leer y BLOQUEAR la fila: FOR UPDATE reserva la fila hasta el fin
-- de la transaccion. Devuelve 1.
SELECT stock
  FROM producto
 WHERE nombre = 'Gaseosa cola 2.25L'
   FOR UPDATE;

-- A3 — AVISAR a la sesion B que ejecute B2 (queda esperando) y esperar
-- unos segundos. Recien entonces liberar la fila:
COMMIT;

-- A4 — opcional: verificar el estado final (nadie modifico el stock:
-- ambas sesiones solo leyeron con FOR UPDATE).
SELECT stock
  FROM producto
 WHERE nombre = 'Gaseosa cola 2.25L';