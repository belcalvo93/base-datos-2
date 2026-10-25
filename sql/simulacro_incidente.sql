-- =====================================================================
-- simulacro_incidente.sql — Food Store, TP Unidad 5 (Parte C, punto 1)
-- Simulacro de incidente de acceso indebido. SOLO contra el entorno de
-- desarrollo propio (bd2_tp5u5). Nunca contra bases o sistemas de terceros.
-- =====================================================================
-- Secuencia que reproduce (enunciado, Parte C.1):
--   1) varios intentos fallidos contra fn_autenticar
--   2) un inicio de sesión exitoso
--   3) una lectura masiva de la tabla usuario
--   4) un intento de otorgarle a un rol de bajo privilegio membresía en admin_datos
--
-- Requisitos previos:
--   * Parte A aplicada en bd2_tp5u5 (funciones_auth.sql, mv_ventas_categoria_mes.sql, roles.sql).
--   * Parte B: parámetros de log activos (auditoria_test.sql).
--   * Backup hecho: pg_dump -U postgres -F c -f "food-store/backups/bd2_tp5u5_antes_c.dump" bd2_tp5u5
--
-- Ejecución (Git Bash, desde la raíz del repo). La contraseña de postgres va en
-- una variable de entorno de ESA terminal y se le pasa a psql con -v: no se
-- escribe en ningún archivo del repositorio.
--   export PGPASSWORD='<contraseña de postgres>'
--   psql -U postgres -d bd2_tp5u5 -X -v pw_postgres="$PGPASSWORD" -f sql/simulacro_incidente.sql > "$TEMP/salida_simulacro.txt" 2>&1
-- Al terminar: sql/anonimizar_log.sh y después sql/simulacro_limpieza.sql.
--
-- Las contraseñas de los roles de login son las de roles.sql (marcador de desarrollo).
-- =====================================================================

\set ON_ERROR_STOP on

-- Protocolo de seguridad: confirmar contra qué base estamos conectados
SELECT current_database();

-- La clave de postgres tiene que llegar con -v pw_postgres=... (ver arriba)
\if :{?pw_postgres}
\else
    \echo 'Falta -v pw_postgres="$PGPASSWORD". Abortando antes de tocar nada.'
    \quit
\endif

-- Cadenas de conexión
\set conn_postgres 'host=localhost dbname=bd2_tp5u5 user=postgres password=' :pw_postgres
\set conn_app      'host=localhost dbname=bd2_tp5u5 user=app_web password=cambiar_en_produccion'

-- =====================================================================
-- 0. PREPARACIÓN (como postgres)
-- =====================================================================

-- 0.1 Subir el log a 'all': con 'mod' los SELECT (incluidas las llamadas a
--     fn_autenticar) no quedan registrados. Se restaura en simulacro_limpieza.sql.
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
SELECT pg_sleep(1);
\c :'conn_postgres'

-- 0.2 Usuario de prueba con hash bcrypt real. Los usuarios de data.sql tienen
--     hashes de relleno y no sirven para un login exitoso con crypt().
INSERT INTO usuario (nombre, apellido, mail, contrasena, rol)
VALUES ('Victima', 'Prueba', 'victima.prueba@example.test',
        crypt('Clave-Correcta-U5!', gen_salt('bf')), 'USUARIO')
ON CONFLICT (mail) DO NOTHING;

-- 0.3 Usuarios sintéticos para que la lectura masiva sea realmente masiva.
--     Dominio .test (reservado, no existe). Hash de costo mínimo: solo relleno.
INSERT INTO usuario (nombre, apellido, mail, contrasena, rol)
SELECT 'Sintetico' || n, 'Prueba' || n,
       'sintetico' || n || '@example.test',
       crypt('relleno', gen_salt('bf', 4)), 'USUARIO'
FROM generate_series(1, 300) AS n
ON CONFLICT (mail) DO NOTHING;

SELECT count(*) AS usuarios_antes_del_simulacro FROM usuario;

-- Marca para recortar el tramo del log
SELECT 'INICIO_SIMULACRO_U5' AS marca;

-- =====================================================================
-- SIMULACRO. A partir de acá se esperan errores (permiso denegado):
-- son parte de la evidencia, no deben cortar el script.
-- =====================================================================
\set ON_ERROR_STOP off

-- 1) Tres intentos fallidos contra fn_autenticar (R5 de docs/kiro_roles_spec/requirements.md),
--    cada uno en una conexión nueva (como lo haría un atacante probando claves
--    a través de la aplicación).
\c :'conn_app'
SELECT * FROM fn_autenticar('victima.prueba@example.test', 'clave_incorrecta_1');
\c :'conn_app'
SELECT * FROM fn_autenticar('victima.prueba@example.test', 'clave_incorrecta_2');
\c :'conn_app'
SELECT * FROM fn_autenticar('victima.prueba@example.test', 'clave_incorrecta_3');

-- 2) Inicio de sesión exitoso: devuelve una fila (id, rol)
\c :'conn_app'
SELECT * FROM fn_autenticar('victima.prueba@example.test', 'Clave-Correcta-U5!');

-- 3) Lectura masiva de usuario con la misma sesión de la aplicación.
--    Con el diseño de la Parte A se espera PERMISO DENEGADO (app_web no lee usuario).
SELECT * FROM usuario;
SELECT count(*) FROM usuario;

-- 4) Intento de escalamiento: membresía en admin_datos para un rol de bajo
--    privilegio. En PostgreSQL 16+ hace falta la opción ADMIN sobre el rol.
--    Se espera ERROR. Si NO falla, es un hallazgo y hay que corregir la Parte A.
GRANT admin_datos TO app_web;
SET ROLE admin_datos;

-- =====================================================================
-- CONSTANCIA (como postgres)
-- =====================================================================
\set ON_ERROR_STOP on
\c :'conn_postgres'

SELECT 'FIN_SIMULACRO_U5' AS marca;

-- ¿Quedó alguna membresía en admin_datos? Se espera 0 filas.
SELECT r.rolname AS miembro, g.rolname AS grupo
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles g ON g.oid = am.roleid
WHERE g.rolname = 'admin_datos';

\echo 'Revisar arriba: lectura masiva y escalamiento deben mostrar ERROR; la consulta de membresías, 0 filas.'
