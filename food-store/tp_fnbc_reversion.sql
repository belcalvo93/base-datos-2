-- ============================================================
-- TP U4 / TPI Parcial II (Objetivo 2) — Reversión de la migración a FNBC
-- ============================================================
-- Deshace la descomposición en FNBC (responsable_deposito R1,
-- control_lote R2 y vista v_control_lote_almacen) y restituye todos
-- los datos en la tabla original control_lote_almacen sin pérdida de
-- información, respetando el orden de dependencias y claves foráneas
-- sin usar CASCADE en el bloque de reversión.
--
-- Spec: food-store/specs/spec_fnbc_descomposicion.md (sección 9: Plan de reversión)
-- Base permitida: bd2_tp4u4 (nunca bd2_tp3, bd2_proyecto ni foodstore).
--
-- El script ejecuta dentro de una transacción el ciclo completo:
--   1. Migrar a FNBC (o partir del estado migrado) y verificar con EXCEPT (0 filas).
--   2. Vaciar control_lote_almacen para demostrar que la reversión reconstruye
--      las tuplas íntegramente desde R1 (responsable_deposito) y R2 (control_lote).
--   3. Reconstruir control_lote_almacen desde control_lote NATURAL JOIN responsable_deposito
--      y verificar equivalencia con EXCEPT en ambas direcciones contra la vista (0 filas).
--   4. Eliminar en orden estricto de dependencias (sin CASCADE):
--        1º DROP VIEW v_control_lote_almacen;
--        2º DROP TABLE control_lote;          (hija: tiene FK a responsable_deposito)
--        3º DROP TABLE responsable_deposito;  (padre)
--   5. Verificar que los objetos de FNBC ya no existen, que control_lote_almacen
--      conserva sus 4 restricciones (PK + 3 FK) y que el EXCEPT en ambas direcciones
--      contra la foto previa a la reversión devuelve 0 filas.
--
-- Ejecución por omisión con ROLLBACK (pruebas no destructivas).
-- Para confirmar sobre la copia bd2_tp4u4 sin editar el script, pasar -v commit=1:
--   psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -f food-store/tp_fnbc_reversion.sql
--   psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -v commit=1 -f food-store/tp_fnbc_reversion.sql
-- ============================================================

\set ON_ERROR_STOP on

-- Guarda de base: aborta de inmediato si no se corre sobre bd2_tp4u4
DO $$
BEGIN
    IF current_database() <> 'bd2_tp4u4' THEN
        RAISE EXCEPTION 'Guarda de seguridad: tp_fnbc_reversion.sql solo se ejecuta sobre bd2_tp4u4 (base actual: %)', current_database();
    END IF;
END $$;

SELECT current_database();

BEGIN;

-- ============================================================
-- PASO 1 — Estado migrado a FNBC y verificación previa
-- ============================================================
\echo '=== PASO 1: Estado migrado a FNBC (responsable_deposito + control_lote + v_control_lote_almacen) ==='

CREATE TABLE IF NOT EXISTS lote (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL
);

CREATE TABLE IF NOT EXISTS deposito (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL
);

CREATE TABLE IF NOT EXISTS control_lote_almacen (
    lote_id BIGINT NOT NULL REFERENCES lote(id),
    deposito_id BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO lote (id, nombre) VALUES
    (501, 'Lote A'),
    (502, 'Lote B'),
    (503, 'Lote C')
ON CONFLICT (id) DO NOTHING;

INSERT INTO deposito (id, nombre) VALUES
    (30, 'Depósito Centro'),
    (31, 'Depósito Norte')
ON CONFLICT (id) DO NOTHING;

INSERT INTO usuario (id, nombre, apellido, mail, contrasena, rol, eliminado)
OVERRIDING SYSTEM VALUE
VALUES
    (801, 'Usuario', 'Admin',      'admin801@test.com',      'hash801', 'ADMIN',   FALSE),
    (802, 'Usuario', 'Supervisor', 'supervisor802@test.com', 'hash802', 'USUARIO', FALSE)
ON CONFLICT DO NOTHING;

TRUNCATE TABLE control_lote_almacen;
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- Limpieza previa si existían de una corrida anterior para crear el estado FNBC limpio
DROP VIEW IF EXISTS v_control_lote_almacen;
DROP TABLE IF EXISTS control_lote;
DROP TABLE IF EXISTS responsable_deposito;

-- R1: Depósito del responsable
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY REFERENCES usuario(id),
    deposito_id BIGINT NOT NULL REFERENCES deposito(id)
);

-- R2: Control de lote por responsable (FK hacia R1)
CREATE TABLE control_lote (
    lote_id BIGINT NOT NULL REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen;

INSERT INTO control_lote (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen;

CREATE OR REPLACE VIEW v_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote
NATURAL JOIN responsable_deposito;

-- Verificación de la migración a FNBC (0 filas en ambos sentidos)
\echo '--- 1.1 Conteos tras migrar a FNBC ---'
SELECT
    (SELECT COUNT(*) FROM control_lote_almacen)   AS filas_original,
    (SELECT COUNT(*) FROM responsable_deposito)   AS filas_r1_responsable_deposito,
    (SELECT COUNT(*) FROM control_lote)           AS filas_r2_control_lote,
    (SELECT COUNT(*) FROM v_control_lote_almacen) AS filas_vista_reconstruida;

\echo '--- 1.2 EXCEPT migración: original EXCEPT vista (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen;

\echo '--- 1.3 EXCEPT migración: vista EXCEPT original (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen;

-- ============================================================
-- PASO 2 — Reversión desde FNBC hacia control_lote_almacen
-- ============================================================
\echo '=== PASO 2: Reconstrucción de control_lote_almacen desde las tablas en FNBC ==='

-- Foto de referencia del estado en FNBC antes de revertir
CREATE TEMP TABLE temp_pre_reversion ON COMMIT DROP AS
SELECT lote_id, deposito_id, responsable_control_id
FROM v_control_lote_almacen;

SELECT COUNT(*) AS filas_antes_reversion FROM temp_pre_reversion \gset

-- Vaciamos control_lote_almacen antes de volcar desde R1 y R2 para comprobar
-- que la reversión reconstruye las filas íntegramente a partir de la descomposición
TRUNCATE TABLE control_lote_almacen;

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
SELECT cl.lote_id, rd.deposito_id, cl.responsable_control_id
FROM control_lote cl
NATURAL JOIN responsable_deposito rd;

\echo '--- 2.1 Verificación previa al DROP: control_lote_almacen EXCEPT v_control_lote_almacen (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen;

\echo '--- 2.2 Verificación previa al DROP: v_control_lote_almacen EXCEPT control_lote_almacen (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen;

-- ============================================================
-- PASO 3 — Eliminación de objetos en orden de FK (sin CASCADE)
-- ============================================================
\echo '=== PASO 3: DROP en orden estricto de dependencias (vista -> R2 hija -> R1 padre, sin CASCADE) ==='

-- 1º La vista que depende de control_lote y responsable_deposito
DROP VIEW v_control_lote_almacen;

-- 2º La tabla hija R2 (tiene FK responsable_control_id -> responsable_deposito)
DROP TABLE control_lote;

-- 3º La tabla padre R1 (ya sin dependientes)
DROP TABLE responsable_deposito;

-- ============================================================
-- PASO 4 — Verificación post-reversión
-- ============================================================
\echo '=== PASO 4: Verificación de estado, restricciones, conteos y equivalencia post-reversión ==='

\echo '--- 4.1 Existencia de objetos (esperado: vista=f, r2=f, r1=f, original=t, filas_iguales=t) ---'
SELECT
    to_regclass('public.v_control_lote_almacen') IS NOT NULL AS vista_fnbc_existe,
    to_regclass('public.control_lote')           IS NOT NULL AS r2_control_lote_existe,
    to_regclass('public.responsable_deposito')   IS NOT NULL AS r1_responsable_deposito_existe,
    to_regclass('public.control_lote_almacen')   IS NOT NULL AS tabla_original_existe,
    (SELECT COUNT(*) FROM control_lote_almacen) = :filas_antes_reversion AS filas_iguales;

\echo '--- 4.2 Contenido restaurado en control_lote_almacen ---'
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
ORDER BY lote_id, deposito_id;

\echo '--- 4.3 Restricciones activas en control_lote_almacen (PK + 3 FK) ---'
SELECT pg_get_constraintdef(oid) AS restriccion_declarada
FROM pg_constraint
WHERE conrelid = 'control_lote_almacen'::regclass
  AND contype IN ('p', 'f')
ORDER BY contype DESC, conname;

\echo '--- 4.4 EXCEPT post-reversión Dirección 1: control_lote_almacen EXCEPT temp_pre_reversion (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM temp_pre_reversion;

\echo '--- 4.5 EXCEPT post-reversión Dirección 2: temp_pre_reversion EXCEPT control_lote_almacen (esperado: 0 filas) ---'
SELECT lote_id, deposito_id, responsable_control_id
FROM temp_pre_reversion
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen;

-- Cierre de transacción: por omisión ROLLBACK para pruebas no destructivas.
-- Para confirmar la reversión en la base copia bd2_tp4u4 sin editar el script:
-- psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -v commit=1 -f food-store/tp_fnbc_reversion.sql
\if :{?commit}
    \echo '=== Cierre: COMMIT ejecutado (variable commit=1 detectada) ==='
    COMMIT;
\else
    \echo '=== Cierre: ROLLBACK ejecutado por defecto (pasar -v commit=1 para confirmar) ==='
    ROLLBACK;
\endif
