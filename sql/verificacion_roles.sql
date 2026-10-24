\echo '=== Verificación de roles y permisos — TP U5, Parte A.3 ==='
\echo 'Base: bd2_tp5u5, después de aplicar funciones_auth.sql, mv_ventas_categoria_mes.sql y roles.sql.'
\echo 'Nota: information_schema.role_table_grants no lista vistas materializadas (mv_ventas_categoria_mes)'
\echo 'ni permisos por columna (usuario para rol_soporte). Por eso se complementa con role_column_grants,'
\echo '\\dp, routine_privileges y \\ddp. Se compara contra la matriz de docs/kiro_roles_spec/design.md.'
\echo ''

\echo '--- 1. Roles y atributos (\\du) ---'
\du

\echo '--- 2. Membresías ---'
SELECT r.rolname AS rol, g.rolname AS miembro_de
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles g ON g.oid = am.roleid
WHERE r.rolname IN ('app_web', 'admin_datos', 'rol_reportes_login')
ORDER BY 1, 2;

\echo '--- 3. Privilegios sobre tablas y vistas (role_table_grants) ---'
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes', 'app_web', 'rol_reportes_login')
ORDER BY 1, 2, 3;

\echo '--- 4. Privilegios por columna sobre usuario (role_column_grants) ---'
SELECT grantee, table_name, column_name, privilege_type
FROM information_schema.role_column_grants
WHERE table_schema = 'public' AND table_name = 'usuario'
  AND grantee <> 'admin_datos'
ORDER BY 1, 3;

\echo '--- 5. Vista materializada (\\dp) ---'
\dp mv_ventas_categoria_mes

\echo '--- 6. EXECUTE sobre funciones y procedimiento ---'
\echo '(Las funciones de trigger conservan EXECUTE para PUBLIC: solo se pueden invocar como trigger.)'
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND grantee <> 'admin_datos'
  AND routine_name IN ('fn_autenticar', 'fn_resetear_password', 'registrar_pedido',
                       'fn_verificar_producto_activo', 'fn_verificar_stock_suficiente')
ORDER BY 1, 2;

\echo '--- 7. Privilegios por defecto (\\ddp) ---'
\ddp

\echo '--- 8. Dueño de los objetos ---'
SELECT c.relname AS objeto, c.relkind AS tipo, pg_get_userbyid(c.relowner) AS dueno
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm')
ORDER BY 2, 1;

\echo '--- 9. Pruebas funcionales con SET ROLE (los ERROR son esperados) ---'
\echo '(Todo dentro de BEGIN … ROLLBACK: si una prueba que debe fallar no falla, no deja cambios.'
\echo ' ON_ERROR_ROLLBACK hace que cada ERROR vuelva a un savepoint y la transacción siga.)'
\set ON_ERROR_ROLLBACK on
BEGIN;
\echo 'app_web: fn_autenticar debe funcionar (0 filas con credenciales inválidas)'
SET ROLE app_web;
SELECT * FROM fn_autenticar('nadie@test.com', 'x');
\echo 'app_web: leer usuario debe fallar'
SELECT count(*) FROM usuario;
\echo 'app_web: otorgar admin_datos a un rol de bajo privilegio debe fallar'
GRANT admin_datos TO rol_soporte;
\echo 'app_web: INSERT directo en pedido debe fallar (solo vía registrar_pedido, Parte A.4)'
INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES (now(), 'EFECTIVO', 1);
RESET ROLE;
\echo 'rol_soporte: columnas permitidas deben funcionar'
SET ROLE rol_soporte;
SELECT count(id), count(mail) FROM usuario;
\echo 'rol_soporte: contrasena debe fallar'
SELECT count(contrasena) FROM usuario;
\echo 'rol_soporte: resetear la contraseña de un ADMIN debe fallar (Parte A.4)'
\echo '(Si el mensaje dice "Usuario <NULL>", no hay ningún ADMIN cargado y la prueba no es concluyente.)'
SELECT fn_resetear_password((SELECT id FROM usuario WHERE rol = 'ADMIN' ORDER BY id LIMIT 1),
                            'clave_nueva_123');
RESET ROLE;
\echo 'rol_reportes_login: la vista materializada debe funcionar'
SET ROLE rol_reportes_login;
SELECT count(*) FROM mv_ventas_categoria_mes;
RESET ROLE;
ROLLBACK;
\set ON_ERROR_ROLLBACK off
