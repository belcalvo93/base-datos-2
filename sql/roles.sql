-- =====================================================================
-- roles.sql — Food Store, TP Unidad 5 (Parte A.2)
-- Orden: 3 (último). Concentra toda la política de permisos.
-- Ejecutar como postgres (superusuario): crea roles y cede ownership.
-- =====================================================================

-- 1) Roles de grupo: NOLOGIN y sin atributos peligrosos; son solo contenedores.
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_app_lectura',
                              'rol_app_escritura',
                              'rol_soporte',
                              'rol_reportes'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I', r);
        END IF;
        EXECUTE format('ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', r);
    END LOOP;
END $$;

-- 2) Roles de login: se crean si faltan y después se fuerzan sus atributos.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_web') THEN
        CREATE ROLE app_web;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_datos') THEN
        CREATE ROLE admin_datos;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_reportes_login') THEN
        CREATE ROLE rol_reportes_login;
    END IF;
END $$;

-- Solo admin_datos tiene CREATEDB/CREATEROLE; ningún rol de aplicación es SUPERUSER.
ALTER ROLE app_web WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    PASSWORD 'cambiar_en_produccion';
ALTER ROLE rol_reportes_login WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    PASSWORD 'cambiar_en_produccion';
ALTER ROLE admin_datos WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE
    PASSWORD 'cambiar_en_produccion';

-- 3) Membresías: app_web hereda lectura+escritura; reportes login hereda reportes.
GRANT rol_app_lectura, rol_app_escritura TO app_web;
GRANT rol_reportes TO rol_reportes_login;

-- 4) Ownership: admin_datos dueña del esquema y de los objetos existentes.
-- Sin esto ALTER DEFAULT PRIVILEGES no aplica y SECURITY DEFINER correría como postgres.
ALTER SCHEMA public OWNER TO admin_datos;

ALTER TABLE IF EXISTS categoria      OWNER TO admin_datos;
ALTER TABLE IF EXISTS cliente        OWNER TO admin_datos;
ALTER TABLE IF EXISTS producto       OWNER TO admin_datos;
ALTER TABLE IF EXISTS pedido         OWNER TO admin_datos;
ALTER TABLE IF EXISTS detalle_pedido OWNER TO admin_datos;
ALTER TABLE IF EXISTS usuario        OWNER TO admin_datos;

ALTER VIEW IF EXISTS vista_cliente_completo        OWNER TO admin_datos;
ALTER VIEW IF EXISTS vista_pedidos_cliente         OWNER TO admin_datos;
ALTER VIEW IF EXISTS vista_productos_vigentes      OWNER TO admin_datos;
ALTER VIEW IF EXISTS vista_detalle_pedido_producto OWNER TO admin_datos;
ALTER VIEW IF EXISTS vista_usuario_reportes        OWNER TO admin_datos;

ALTER MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_mes OWNER TO admin_datos;

ALTER FUNCTION fn_autenticar(TEXT, TEXT) OWNER TO admin_datos;
ALTER FUNCTION fn_resetear_password(BIGINT, TEXT) OWNER TO admin_datos;
ALTER FUNCTION fn_verificar_producto_activo() OWNER TO admin_datos;
ALTER FUNCTION fn_verificar_stock_suficiente() OWNER TO admin_datos;
ALTER PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB) OWNER TO admin_datos;

-- registrar_pedido lee/actualiza producto y sus triggers también leen producto;
-- SECURITY DEFINER lo ejecuta como admin_datos sin dar permisos de tabla a rol_app_escritura.
ALTER PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB)
    SECURITY DEFINER
    SET search_path = public, pg_temp;

-- 5) USAGE del esquema: sin esto ningún GRANT sobre objetos es utilizable.
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;

-- 6) Permisos de los roles de grupo, uno por uno según la matriz del design.md.
GRANT SELECT ON vista_productos_vigentes TO rol_app_lectura;

-- Escritura solo vía registrar_pedido (auditoría Parte A.4): el INSERT/UPDATE directo permitía
-- crear pedidos vacíos o cambiar fecha/cliente. El REVOKE limpia el GRANT ya aplicado en la base.
REVOKE INSERT, UPDATE ON pedido, detalle_pedido FROM rol_app_escritura;
GRANT SELECT ON pedido, detalle_pedido TO rol_app_escritura;

GRANT SELECT ON mv_ventas_categoria_mes TO rol_reportes;

-- Soporte: resumen de pedidos (Clase 1, sección 4.3) e identificación; nunca celular ni contrasena.
GRANT SELECT ON vista_pedidos_cliente TO rol_soporte;
REVOKE SELECT ON usuario FROM rol_soporte;  -- limpia un posible GRANT de tabla previo
GRANT SELECT (id, nombre, apellido, mail, rol) ON usuario TO rol_soporte;

-- 7) Quita accesos previos que la matriz no autoriza (exponían datos personales).
REVOKE SELECT ON vista_usuario_reportes FROM rol_soporte, rol_reportes;

-- 8) Funciones y procedimiento: PUBLIC pierde EXECUTE; solo el rol de la matriz lo recibe.
REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT) TO app_web;

-- fn_resetear_password: soporte la usa para reseteo (Clase 2, sección 2.3).
REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT) TO rol_soporte;

-- El procedimiento también trae EXECUTE a PUBLIC por defecto: se cierra.
REVOKE ALL ON PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB)
    TO rol_app_escritura;

-- 9) Default privileges para objetos que cree admin_datos en el futuro.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_reportes;
-- Sin IN SCHEMA: el EXECUTE a PUBLIC es un default global y no se puede revocar por esquema.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
