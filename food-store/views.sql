-- vista_cliente_completo
-- Propósito: exponer el perfil completo de contacto de cada cliente para
-- uso interno (soporte, verificación de datos, comunicaciones directas).
-- Incluye email y telefono, sensibles, ausentes en vista_pedidos_cliente.
-- Idempotente: CREATE OR REPLACE VIEW.

CREATE OR REPLACE VIEW vista_cliente_completo AS
SELECT id_cliente, nombre, apellido, email, telefono
FROM cliente;

-- Verificación (criterio de aceptación de la spec): no ejecutar en cada corrida.
-- Ambas direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT id_cliente, nombre, apellido, email, telefono
-- FROM vista_cliente_completo
-- EXCEPT
-- SELECT id_cliente, nombre, apellido, email, telefono
-- FROM cliente;
--
-- SELECT id_cliente, nombre, apellido, email, telefono
-- FROM cliente
-- EXCEPT
-- SELECT id_cliente, nombre, apellido, email, telefono
-- FROM vista_cliente_completo;