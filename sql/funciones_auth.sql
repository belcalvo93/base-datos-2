-- =====================================================================
-- funciones_auth.sql — Food Store, TP Unidad 5
-- PARTE 0: reconstrucción de las funciones de la Clase 2
--   fn_autenticar        -> apunte Clase 2, sección 1.5
--   fn_resetear_password -> apunte Clase 2, sección 2.3
-- Requiere que roles.sql se haya ejecutado antes (usa rol_soporte).
-- =====================================================================

-- crypt() y gen_salt() vienen de esta extensión
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Login: compara el hash, nunca concatena texto (previene inyección SQL)
CREATE OR REPLACE FUNCTION fn_autenticar(p_mail TEXT, p_pass TEXT)
RETURNS TABLE(id BIGINT, rol rol) AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.rol
    FROM   usuario u
    WHERE  u.mail = p_mail
    AND    u.contrasena = crypt(p_pass, u.contrasena)
    AND    u.eliminado = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Reseteo de contraseña acotado: corre con privilegios del dueño,
-- con search_path fijo para evitar suplantación de esquema
CREATE OR REPLACE FUNCTION fn_resetear_password(
    p_usuario_id BIGINT, p_nueva TEXT
) RETURNS VOID
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE usuario
    SET    contrasena = crypt(p_nueva, gen_salt('bf'))
    WHERE  id = p_usuario_id AND eliminado = FALSE;
END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT) TO rol_soporte;