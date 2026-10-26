-- =====================================================================
-- usuario_anon.sql — Food Store, TP Unidad 5 (Parte D, punto 1)
-- Construye la tabla usuario_anon con datos sintéticos deterministas
-- siguiendo el patrón de la Clase 2 (preserva id, cardinalidad y unicidad,
-- e inhabilita la autenticación con un hash no válido).
--
-- Primera corrida: ejecutar tal cual (termina en ROLLBACK) e inspeccionar
-- las consultas de control. Segunda corrida: cambiar ROLLBACK por COMMIT.
-- =====================================================================

\set ON_ERROR_STOP on

-- Protocolo de seguridad: confirmar que la sesión apunta a bd2_tp5u5
SELECT current_database();

BEGIN;

-- Sin CASCADE: evita arrastrar objetos dependientes por accidente
DROP TABLE IF EXISTS usuario_anon;

-- Replica los tipos y restricciones de usuario (sin IDENTITY en id para
-- copiar exactamente el id de origen de forma determinista)
CREATE TABLE usuario_anon (
    id          BIGINT       PRIMARY KEY,
    nombre      VARCHAR(80)  NOT NULL,
    apellido    VARCHAR(80)  NOT NULL,
    mail        VARCHAR(120) NOT NULL UNIQUE,
    celular     VARCHAR(30),
    contrasena  VARCHAR(255) NOT NULL,
    rol         rol          NOT NULL DEFAULT 'USUARIO',
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Propiedad alineada con el esquema de la Parte A (roles.sql).
-- No se otorgan permisos adicionales (mínimo privilegio).
ALTER TABLE usuario_anon OWNER TO admin_datos;

-- Carga determinista derivada del id; conserva rol, eliminado y created_at
INSERT INTO usuario_anon (
    id, nombre, apellido, mail, celular, contrasena, rol, eliminado, created_at
)
SELECT
    id,
    'Usuario ' || id,
    'Apellido ' || id,
    'usuario' || id || '@ejemplo.test',
    NULL,
    'hash_no_valido',
    rol,
    eliminado,
    created_at
FROM usuario;

-- =====================================================================
-- Consultas de control
-- =====================================================================

-- 1) Misma cardinalidad entre usuario y usuario_anon
SELECT
    (SELECT COUNT(*) FROM usuario)      AS filas_usuario,
    (SELECT COUNT(*) FROM usuario_anon) AS filas_usuario_anon;

-- 2) Ningún dato personal real ni hash real expuesto en usuario_anon (debe dar 0)
SELECT COUNT(*) AS filas_con_datos_reales_o_hash_invalido
FROM usuario u
INNER JOIN usuario_anon ua ON ua.id = u.id
WHERE ua.mail = u.mail
   OR ua.nombre = u.nombre
   OR ua.apellido = u.apellido
   OR ua.celular IS NOT NULL
   OR ua.contrasena <> 'hash_no_valido';

-- 3) Unicidad de mail en usuario_anon (debe dar 0 duplicados)
SELECT COUNT(*) - COUNT(DISTINCT mail) AS mails_duplicados
FROM usuario_anon;

-- Primera corrida: ROLLBACK para verificar. Cambiar a COMMIT para persistir.
ROLLBACK;
