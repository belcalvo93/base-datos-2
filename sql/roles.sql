-- =====================================================================
-- roles.sql — Food Store, TP Unidad 5
-- PARTE 0: reconstrucción del esquema de roles de la Clase 1 (apunte, sección 4.4)
-- Adaptado a los nombres reales de nuestra base:
--   v_productos_vigentes / v_categorias_vigentes -> vista_productos_vigentes
--   v_usuarios_publico                           -> vista_usuario_reportes
--   v_pedidos_resumen                            -> vista_pedidos_cliente
--   sp_crear_pedido                              -> registrar_pedido
--   mv_ventas_categoria_mes                      -> no existe (pendiente Parte A)
-- Los roles son del servidor entero: el script verifica si ya existen
-- para poder correrlo más de una vez sin error.
-- =====================================================================

-- 1. Roles de grupo (NOLOGIN): definen QUÉ se puede hacer
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        ELSE
            -- Si ya existía (por ejemplo rol_reportes, creado con LOGIN en el TP de vistas),
            -- se fuerza NOLOGIN: un rol de grupo nunca abre conexiones.
            EXECUTE format('ALTER ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- 2. Uso del esquema: sin esto ningún otro privilegio sirve
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;

-- 3. Privilegios de cada rol de grupo
GRANT SELECT ON vista_productos_vigentes
    TO rol_app_lectura;

GRANT SELECT, INSERT, UPDATE ON pedido, detalle_pedido
    TO rol_app_escritura;
GRANT EXECUTE ON PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB)
    TO rol_app_escritura;

GRANT SELECT ON vista_usuario_reportes, vista_pedidos_cliente
    TO rol_soporte;

-- rol_reportes: en clase recibe SELECT sobre mv_ventas_categoria_mes,
-- que no existe en nuestra base. Se resuelve en la Parte A.

-- 4. Roles de login (LOGIN): definen QUIÉN se conecta
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_web') THEN
        CREATE ROLE app_web WITH LOGIN PASSWORD 'cambiar_en_produccion';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_datos') THEN
        CREATE ROLE admin_datos WITH LOGIN PASSWORD 'cambiar_en_produccion'
            CREATEDB CREATEROLE;
    END IF;
END $$;

GRANT rol_app_lectura, rol_app_escritura TO app_web;