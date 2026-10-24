-- =====================================================================
-- funciones_auth.sql — Food Store, TP Unidad 5 (Parte A.2)
-- Orden: 1. Crea la extensión y las funciones. Sin GRANT/REVOKE:
-- toda la política de permisos vive en roles.sql (se ejecuta último).
-- =====================================================================

-- pgcrypto debe quedar en public porque las funciones usan search_path = public, pg_temp.
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA public;

-- Login: compara el hash sin concatenar texto; SECURITY DEFINER evita
-- darle SELECT sobre usuario a app_web y el search_path fijo evita hijacking.
CREATE OR REPLACE FUNCTION fn_autenticar(p_mail TEXT, p_pass TEXT)
RETURNS TABLE(id BIGINT, rol rol)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.rol
    FROM   usuario u
    WHERE  u.mail = p_mail
    AND    u.contrasena = crypt(p_pass, u.contrasena)
    AND    u.eliminado = FALSE;
END;
$$;

-- Reseteo de contraseña: corre como admin_datos (dueño) y con search_path fijo.
CREATE OR REPLACE FUNCTION fn_resetear_password(
    p_usuario_id BIGINT, p_nueva TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE usuario
    SET    contrasena = crypt(p_nueva, gen_salt('bf'))
    WHERE  id = p_usuario_id AND eliminado = FALSE;
END;
$$;
