-- ============================================================
-- TP U5 — Parte B — Activación y prueba de la auditoría
-- ============================================================
-- Consigna TP U5 — Parte B:
--   1. Activar en la configuración del servidor de desarrollo los
--      parámetros de auditoría: log_connections, log_disconnections
--      y log_statement en un nivel que registre modificaciones ('mod'),
--      junto con log_line_prefix para identificar quién, cuándo y
--      desde dónde.
--   2. Ejecutar contra la base de Food Store una secuencia breve de
--      operaciones de prueba: al menos una lectura, una inserción,
--      una actualización y un intento de inicio de sesión fallido.
--
-- Base de trabajo: bd2_tp5u5 (copia de bd2_tp4u4).
-- NO correr contra bd2_proyecto ni bd2_tp3.
--
-- Uso (PowerShell / Git Bash):
--   1. Crear base de trabajo (una sola vez):
--      createdb -U postgres -T bd2_tp4u4 bd2_tp5u5
--   2. Ejecutar este script:
--      psql -U postgres -d bd2_tp5u5 -X -v ON_ERROR_STOP=1 -f sql/auditoria_test.sql
--   3. Provocar un intento de inicio de sesión fallido:
--      psql "host=localhost dbname=bd2_tp5u5 user=postgres password=clave_incorrecta_prueba_u5"
--   4. Leer el log actual en Windows (mensajes del servidor en WIN1252):
--      psql -U postgres -d bd2_tp5u5 -X -c "SELECT convert_from(pg_read_binary_file(pg_current_logfile()), 'WIN1252');"
-- ============================================================

\set ON_ERROR_STOP on

-- Protocolo de seguridad: confirmar contra qué base estamos conectados
SELECT current_database();

-- ============================================================
-- 1. ACTIVACIÓN DE PARÁMETROS DE AUDITORÍA (nivel servidor)
-- ============================================================
-- ALTER SYSTEM escribe en postgresql.auto.conf (nivel instancia) y
-- no puede ejecutarse dentro de un bloque BEGIN ... ROLLBACK.
-- pg_reload_conf() aplica los cambios sin reiniciar el servicio.
ALTER SYSTEM SET logging_collector = 'on';
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_statement = 'mod';
ALTER SYSTEM SET log_line_prefix = '%m [%p] %q%u@%d %r %a ';

SELECT pg_reload_conf();
SELECT pg_sleep(0.5);

-- Reconectamos (\c) para que esta nueva sesión ya abra con
-- log_connections = 'on', log_disconnections = 'on' y el nuevo
-- log_line_prefix activos desde el inicio de la conexión.
\c bd2_tp5u5

-- Verificación de los parámetros activos y ruta completa del log actual
SHOW logging_collector;
SHOW log_connections;
SHOW log_disconnections;
SHOW log_statement;
SHOW log_line_prefix;

SELECT
    pg_current_logfile() AS archivo_log_actual,
    setting || '/' || pg_current_logfile() AS ruta_log_completa
FROM pg_settings
WHERE name = 'data_directory';

-- ============================================================
-- 2. SECUENCIA DE OPERACIONES DE PRUEBA (BEGIN ... ROLLBACK)
-- ============================================================
-- Todas las escrituras se envuelven en BEGIN ... ROLLBACK para que
-- el motor ejecute y registre las sentencias en el archivo de log
-- sin modificar de forma permanente los datos de bd2_tp5u5.
BEGIN;

-- 2.a) Lectura (SELECT) bajo log_statement = 'mod':
-- Con 'mod' activo, esta lectura NO se escribe en el log del servidor
-- (evidencia práctica de que 'mod' solo registra DDL y escrituras DML).
SELECT id_categoria, nombre, activo
FROM categoria
WHERE nombre = 'Panificados';

-- Para dejar también constancia en el log de cómo se ve una lectura
-- auditada, habilitamos 'all' únicamente dentro de esta transacción
-- para una consulta puntual sobre usuario y volvemos a 'mod':
SET LOCAL log_statement = 'all';

SELECT id, mail, rol, eliminado
FROM usuario
WHERE id = 1;

SET LOCAL log_statement = 'mod';

-- 2.b) Inserción (INSERT):
-- Operación DML de modificación: queda registrada en el log por 'mod'.
INSERT INTO categoria (nombre, activo)
VALUES ('Auditoria Prueba U5', TRUE);

-- 2.c) Actualización (UPDATE con WHERE explícito):
-- Operación DML de modificación: queda registrada en el log por 'mod'.
UPDATE categoria
SET activo = FALSE
WHERE nombre = 'Auditoria Prueba U5';

-- Revertimos la transacción: la tabla categoria queda intacta, pero
-- las sentencias ejecutadas y el ROLLBACK quedan registrados en el log.
ROLLBACK;
