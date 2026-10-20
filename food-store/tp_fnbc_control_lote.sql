-- ============================================================
-- TP U4 — Parte 1 — FNBC Control de Lote
-- ============================================================
-- Consigna TP U4:
--   4.1  contexto: tablas e instancia
--   4.2  a) DFs en notación formal
--        b) clausuras, claves candidatas, atributos primos/no primos
--        c) determinación de FNBC, DF violatoria y por qué
--        d) un escenario concreto por cada anomalía (inserción,
--           borrado, actualización)
--        e) descomposición en FNBC (responsable_deposito y control_lote),
--           análisis de pérdida de información y preservación de DFs
--        f) migración de datos, vista v_control_lote_almacen (NATURAL JOIN)
--           y verificación de equivalencia en ambas direcciones con EXCEPT
--
-- Specs:
--   food-store/specs/spec_fnbc_control_lote.md (puntos a-d)
--   food-store/specs/spec_fnbc_descomposicion.md (puntos e-f)
--   Donde la spec y la consigna difieren, manda la consigna:
--   control_lote_almacen NO tiene columnas id ni cantidad, la PK es
--   (lote_id, deposito_id), los tipos son BIGINT y
--   responsable_control_id es FK de usuario(id).
--
-- Base de trabajo: bd2_tp4u4 — NO correr contra bd2_proyecto ni bd2_tp3.
--
-- Idempotente: DROP ... IF EXISTS ... CASCADE antes de cada CREATE.
-- Seguridad: todo corre dentro de BEGIN; ... ROLLBACK; y no deja
--   cambios en la base. El ROLLBACK final pasa a COMMIT recién
--   después de inspeccionar la salida (protocolo paso 2).
--   OJO: si la segunda mitad de este archivo (descomposición, puntos
--   e y f) ya quedó COMMITeada, correr este script solo con ROLLBACK
--   (el DROP ... CASCADE de lote/deposito borraría las FKs que esas
--   tablas le declararon) o re-ejecutar esa segunda mitad.
--
-- Uso (Git Bash):
--   psql -U postgres -d bd2_tp4u4 -X -v ON_ERROR_STOP=1 -f food-store/tp_fnbc_control_lote.sql
--   (no usar psql -1: el script abre su propia transacción)
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- Protocolo de seguridad paso 3: confirmar contra qué base corremos.
SELECT current_database();

-- Pre-flight: antes de correr el script no debe haber rastro de los
-- usuarios 801/802 (esperado: 0 filas). Si devuelve filas, una
-- corrida anterior quedó COMMITeada: revisar antes de continuar.
-- SELECT id, mail FROM usuario
-- WHERE id IN (801, 802)
--    OR mail IN ('admin801@test.com', 'supervisor802@test.com');

-- ============================================================
-- CONTEXTO — consigna 4.1
-- ============================================================
-- DROP en orden inverso al CREATE (primero la vista y tablas con FK).
DROP VIEW IF EXISTS v_control_lote_almacen;
DROP TABLE IF EXISTS control_lote CASCADE;
DROP TABLE IF EXISTS responsable_deposito CASCADE;
DROP TABLE IF EXISTS control_lote_almacen CASCADE;
DROP TABLE IF EXISTS lote CASCADE;
DROP TABLE IF EXISTS deposito CASCADE;

-- Tablas mínimas de apoyo. Los id van en BIGINT para igualar el
-- tipo de las FK de la consigna 4.1 (la spec decía INTEGER).
CREATE TABLE lote (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL
);

CREATE TABLE deposito (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL
);

-- DDL textual de la consigna 4.1: PK compuesta (lote_id, deposito_id),
-- tres FK (incluida responsable_control_id -> usuario(id)), sin
-- columnas id ni cantidad y sin constraint que imponga la DF F2
-- (agregarla haría imposible demostrar las anomalías del punto d).
CREATE TABLE control_lote_almacen (
    lote_id BIGINT NOT NULL REFERENCES lote(id),
    deposito_id BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO lote (id, nombre) VALUES
    (501, 'Lote A'),
    (502, 'Lote B'),
    (503, 'Lote C');

INSERT INTO deposito (id, nombre) VALUES
    (30, 'Depósito Centro'),
    (31, 'Depósito Norte');

-- usuario.id es GENERATED ALWAYS AS IDENTITY: sin OVERRIDING SYSTEM
-- VALUE el motor rechaza los 801/802 explícitos. celular se omite
-- (nullable), created_at toma su DEFAULT. ON CONFLICT DO NOTHING
-- sin objetivo cubre cualquier conflicto (PK id o UNIQUE mail).
INSERT INTO usuario (id, nombre, apellido, mail, contrasena, rol, eliminado)
OVERRIDING SYSTEM VALUE
VALUES
    (801, 'Usuario', 'Admin',      'admin801@test.com',      'hash801', 'ADMIN',   FALSE),
    (802, 'Usuario', 'Supervisor', 'supervisor802@test.com', 'hash802', 'USUARIO', FALSE)
ON CONFLICT DO NOTHING;

-- Instancia textual de la consigna 4.1.
INSERT INTO control_lote_almacen VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- ============================================================
-- a) DEPENDENCIAS FUNCIONALES — notación formal
-- ============================================================
-- Conjunto F de DFs del universo de la relación:
--
--   F1: {lote_id, deposito_id} → {responsable_control_id}
--       Clave primaria: la garantiza el motor (ver restricciones
--       declaradas abajo), no la buena voluntad de quien carga.
--
--   F2: {responsable_control_id} → {deposito_id}
--       Regla de negocio: un responsable controla un solo depósito.
--       La instancia la respeta: 801 → 30 y 802 → 31.
-- ============================================================

SELECT pg_get_constraintdef(oid) AS restriccion_declarada
FROM pg_constraint
WHERE conrelid = 'control_lote_almacen'::regclass
  AND contype IN ('p', 'f')
ORDER BY contype DESC, conname;

-- ============================================================
-- b) CLAUSURAS, CLAVES CANDIDATAS Y ATRIBUTOS PRIMOS
-- ============================================================
-- cl({lote_id, deposito_id})
--     = {lote_id, deposito_id, responsable_control_id}  (F1)  = R
--     → clave candidata (la PK declarada)
--
-- cl({lote_id, responsable_control_id})
--     = {lote_id, responsable_control_id, deposito_id}  (F2)
--     = R
--     → clave candidata
--
-- cl({responsable_control_id})
--     = {responsable_control_id, deposito_id}  (F2)  ≠ R
--     → {responsable_control_id} NO es superclave
--
-- cl({lote_id}) = {lote_id} ≠ R
-- cl({deposito_id}) = {deposito_id} ≠ R
-- cl({deposito_id, responsable_control_id})
--     = {deposito_id, responsable_control_id} ≠ R  (F1 exige lote_id)
--
-- Claves candidatas: {lote_id, deposito_id} y
--                    {lote_id, responsable_control_id}
-- Atributos primos:    lote_id, deposito_id, responsable_control_id
-- Atributos no primos: ninguno
-- ============================================================

-- ============================================================
-- c) DETERMINACIÓN DE FNBC
-- ============================================================
-- Definición: R está en FNBC si para toda DF no trivial X → A,
-- X es superclave de R (es decir, todo determinante es clave
-- candidata).
--
--   F1: determinante {lote_id, deposito_id} = PK → es clave
--       candidata → cumple.
--   F2: determinante {responsable_control_id}; cl({responsable_control_id})
--       = {responsable_control_id, deposito_id} ≠ R → NO es superclave
--       → F2 VIOLA la FNBC.
--
-- ¿Por qué igual cumple 3FN? 3FN exige que X sea superclave O que A
-- sea atributo primo. Acá deposito_id es primo (forma parte de la
-- clave candidata {lote_id, deposito_id}) y no hay atributos no
-- primos. Por eso la tabla está en 3FN pero NO en FNBC.
-- ============================================================

-- Verificación de F2 en la instancia: agrupa por responsable y
-- cuenta los depósitos distintos. Si un responsable tuviera más de
-- un depósito, sería contraejemplo de F2. Esperado: 0 filas.
-- (Los datos pueden REFUTAR una DF —basta un contraejemplo— pero
-- nunca demostrarla: ver food-store/verificacion_normalizacion.sql.)
SELECT responsable_control_id
FROM control_lote_almacen
GROUP BY responsable_control_id
HAVING COUNT(DISTINCT deposito_id) > 1;

-- ============================================================
-- d) ANOMALÍAS — un escenario concreto por cada una (consigna 4.2.d)
-- ============================================================
-- Cada demo se aísla con SAVEPOINT / ROLLBACK TO SAVEPOINT dentro de
-- la transacción única: PostgreSQL no anida BEGIN (el segundo solo
-- emite un warning), y así la basura de una demo no contamina la
-- consulta de evidencia de la siguiente.
-- ============================================================

-- --- d.1) Inserción --------------------------------------------------
-- Registrar un control del lote 501 en el depósito 31 a cargo de 801,
-- que en los datos habituales controla el depósito 30: mismo
-- responsable, depósito diferente al habitual → violaría F2.
-- No hay constraint que imponga F2, así que el INSERT ENTRA y la
-- instancia queda inconsistente: esa es la anomalía de inserción.
SAVEPOINT anom_insercion;

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES (501, 31, 801);

-- Evidencia: 801 con depósitos 30 y 31 (esperado: 0 filas antes,
-- 1 fila —801— después).
SELECT responsable_control_id
FROM control_lote_almacen
GROUP BY responsable_control_id
HAVING COUNT(DISTINCT deposito_id) > 1;

ROLLBACK TO SAVEPOINT anom_insercion;

-- --- d.2) Borrado ----------------------------------------------------
-- Borrar el único registro del responsable 802: desaparece la
-- información de que 802 controla el depósito 31 (no está registrada
-- en ninguna otra fila) → pérdida de información.
SAVEPOINT anom_borrado;

SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
ORDER BY lote_id;                                   -- antes: 802 presente

DELETE FROM control_lote_almacen
WHERE lote_id = 503 AND deposito_id = 31;           -- única fila de 802

SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
ORDER BY lote_id;                                   -- después: 802 ausente

ROLLBACK TO SAVEPOINT anom_borrado;

-- --- d.3) Actualización ----------------------------------------------
-- En los datos, el depósito del responsable 801 está repetido en las
-- filas (501, 30) y (502, 30): moverlo al depósito 31 tocando solo
-- una de sus dos filas deja a 801 en los depósitos 31 y 30 a la vez
-- → viola F2. Para cambiar el depósito de un responsable hay que
-- actualizar TODAS sus filas; la tabla no lo obliga a hacerlo.
SAVEPOINT anom_actualizacion;

UPDATE control_lote_almacen
SET deposito_id = 31
WHERE lote_id = 501 AND deposito_id = 30 AND responsable_control_id = 801;

-- Evidencia: 801 con depósitos 30 y 31 (esperado: 0 filas antes,
-- 1 fila —801— después).
SELECT responsable_control_id
FROM control_lote_almacen
GROUP BY responsable_control_id
HAVING COUNT(DISTINCT deposito_id) > 1;

ROLLBACK TO SAVEPOINT anom_actualizacion;

-- ============================================================
-- e) DESCOMPOSICIÓN EN FNBC — sin pérdida de información
-- ============================================================
-- Se aplica descomposición de Boyce-Codd a partir de la DF que
-- violaba FNBC (F2: {responsable_control_id} → {deposito_id}):
--
--   R1: responsable_deposito (responsable_control_id PK, deposito_id)
--       DF que rige en R1: F2 ({responsable_control_id} → {deposito_id}).
--       Única clave candidata: {responsable_control_id}.
--       El único determinante no trivial es superclave → R1 está en FNBC.
--
--   R2: control_lote (lote_id, responsable_control_id) — PK compuesta
--       No tiene DFs no triviales propias (su única clave candidata es
--       la tupla completa {lote_id, responsable_control_id}) → R2 está en FNBC.
--
-- ¿Por qué la descomposición es SIN PÉRDIDA (Teorema de Heath)?
--   R1 ∩ R2 = {responsable_control_id}, y en R1 se cumple
--   {responsable_control_id} → {deposito_id}, por lo que el atributo
--   común (R1 ∩ R2) es superclave de R1. Eso garantiza que
--   R1 ⋈ R2 reconstruye exactamente R sin tuplas espurias.
--
-- ¿Se preservan las dependencias funcionales?
--   - F2 ({responsable_control_id} → {deposito_id}) SÍ se preserva:
--     la impone la PK de responsable_deposito.
--   - F1 ({lote_id, deposito_id} → {responsable_control_id}) NO se
--     preserva en una sola tabla porque lote_id quedó en R2 y
--     deposito_id en R1. Es el trade-off clásico de FNBC: dos
--     responsables distintos del mismo depósito podrían registrar el
--     mismo lote en control_lote sin que las PKs individuales lo impidan.
-- ============================================================

DROP VIEW IF EXISTS v_control_lote_almacen;
DROP TABLE IF EXISTS control_lote CASCADE;
DROP TABLE IF EXISTS responsable_deposito CASCADE;

-- R1: Depósito asignado a cada responsable (impone F2 por PK)
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY REFERENCES usuario(id),
    deposito_id BIGINT NOT NULL REFERENCES deposito(id)
);

-- R2: Control de cada lote por su responsable
CREATE TABLE control_lote (
    lote_id BIGINT NOT NULL REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- ============================================================
-- f) MIGRACIÓN, VISTA DE COMPATIBILIDAD Y VERIFICACIÓN (EXCEPT)
-- ============================================================

-- f.1) Migración de datos desde la tabla original control_lote_almacen
-- En R1 usamos DISTINCT porque cada responsable puede aparecer en
-- varios lotes dentro de control_lote_almacen (ej. 801 en 501 y 502).
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen;

INSERT INTO control_lote (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen;

-- f.2) Vista de compatibilidad con NATURAL JOIN
-- La única columna con el mismo nombre entre control_lote y
-- responsable_deposito es responsable_control_id (superclave de R1).
CREATE OR REPLACE VIEW v_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote
NATURAL JOIN responsable_deposito;

-- f.3) Inspección de las tablas nuevas y de la vista reconstruida
SELECT responsable_control_id, deposito_id
FROM responsable_deposito
ORDER BY responsable_control_id;

SELECT lote_id, responsable_control_id
FROM control_lote
ORDER BY lote_id, responsable_control_id;

SELECT lote_id, deposito_id, responsable_control_id
FROM v_control_lote_almacen
ORDER BY lote_id, deposito_id;

-- f.4) Verificación de conteo de filas
SELECT
    (SELECT COUNT(*) FROM control_lote_almacen)   AS filas_original,
    (SELECT COUNT(*) FROM responsable_deposito)   AS filas_r1_responsable_deposito,
    (SELECT COUNT(*) FROM control_lote)           AS filas_r2_control_lote,
    (SELECT COUNT(*) FROM v_control_lote_almacen) AS filas_vista_reconstruida;

-- f.5) Verificación de equivalencia en ambas direcciones con EXCEPT
-- Dirección 1: original EXCEPT vista (esperado: 0 filas)
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM v_control_lote_almacen;

-- Dirección 2: vista EXCEPT original (esperado: 0 filas)
SELECT lote_id, deposito_id, responsable_control_id
FROM v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen;

-- ============================================================
-- Cierre: nada de lo anterior queda en la base. Cambiar por COMMIT
-- solo después de inspeccionar la salida (protocolo paso 2).
-- ============================================================
ROLLBACK;
