-- ============================================================
-- Escenario 2 — Lectura fantasma · SESION A (la que cuenta)
-- TPI, objetivo 8. Base: bd2_trabajo (schema + data + restricciones).
-- Ejecutar sentencia por sentencia, en orden, alternando con
-- escenario2_lectura_fantasma_sesionB.sql.
-- La categoria Bebidas tiene 2 productos activos en el seed.
-- ============================================================

-- ------------------------------------------------------------
-- Fase 1 — READ COMMITTED (nivel por defecto)
-- ------------------------------------------------------------
-- A1
BEGIN;

-- A2 — contar los productos de Bebidas: debe dar 2.
SELECT COUNT(*) AS productos_bebidas
  FROM producto
 WHERE id_categoria =
       (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');

-- ESPERAR el paso B1 de la sesion B (INSERT 'Cerveza 1L' confirmado).

-- A3 — repetir el conteo: READ COMMITTED ve la fila que B confirmo en
-- el medio. Debe dar 3: aparece una fila que no estaba (fantasma).
SELECT COUNT(*) AS productos_bebidas
  FROM producto
 WHERE id_categoria =
       (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');

-- A4
ROLLBACK;

-- ------------------------------------------------------------
-- Fase 2 — REPEATABLE READ
-- ------------------------------------------------------------
-- A5
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- A6 — contar: debe dar 2 (B2 ya limpio la fila de la fase 1).
SELECT COUNT(*) AS productos_bebidas
  FROM producto
 WHERE id_categoria =
       (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');

-- ESPERAR el paso B3 de la sesion B (INSERT 'Agua saborizada 1.5L'
-- confirmado).

-- A7 — repetir el conteo: la foto se tomo al inicio, la fila nueva no
-- aparece. Debe seguir dando 2: el fantasma no aparece en REPEATABLE
-- READ (difiere del estandar, que lo deja para SERIALIZABLE).
SELECT COUNT(*) AS productos_bebidas
  FROM producto
 WHERE id_categoria =
       (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');

-- A8 — cerrar la transaccion.
COMMIT;

-- A9 — fuera de la transaccion el conteo debe dar 3: la fila de B estuvo
-- confirmada todo el tiempo; el snapshot la ocultaba a proposito.
SELECT COUNT(*) AS productos_bebidas
  FROM producto
 WHERE id_categoria =
       (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');