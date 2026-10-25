-- =====================================================================
-- simulacro_limpieza.sql — Food Store, TP Unidad 5 (Parte C)
-- Deja bd2_tp5u5 y el servidor como estaban antes del simulacro.
-- Ejecutar como postgres DESPUÉS de extraer y anonimizar el log.
--   psql -U postgres -d bd2_tp5u5 -X -f sql/simulacro_limpieza.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Protocolo de seguridad: confirmar contra qué base estamos conectados
SELECT current_database();

-- 1) Volver el log al nivel de la Parte B ('mod').
ALTER SYSTEM SET log_statement = 'mod';
SELECT pg_reload_conf();

-- 2) Si el escalamiento NO hubiera fallado, retirar la membresía.
--    (Si no existe, no hace nada.)
DO $$
BEGIN
    IF pg_has_role('app_web', 'admin_datos', 'MEMBER') THEN
        REVOKE admin_datos FROM app_web;
        RAISE NOTICE 'Se retiró admin_datos de app_web: el escalamiento había funcionado (hallazgo).';
    END IF;
END $$;

-- 3) Borrar los usuarios de prueba (todos del dominio reservado .test).
DELETE FROM usuario WHERE mail LIKE '%@example.test';

SELECT count(*) AS usuarios_de_prueba_restantes
FROM usuario WHERE mail LIKE '%@example.test';   -- se espera 0

SHOW log_statement;                               -- se espera mod
