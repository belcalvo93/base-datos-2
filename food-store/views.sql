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

-- vista_pedidos_cliente
-- Propósito: mostrar cada pedido junto con el nombre y apellido del cliente
-- que lo realizó, sin exponer datos sensibles (email, telefono). Caso de uso
-- operativo; para acceso completo al perfil existe vista_cliente_completo.
-- INNER JOIN: pedido.id_cliente es NOT NULL (FK con participación total).
-- Idempotente: CREATE OR REPLACE VIEW.

CREATE OR REPLACE VIEW vista_pedidos_cliente AS
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente;

-- Verificación (criterio de aceptación de la spec): no ejecutar en cada corrida.
-- Ambas direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT id_pedido, fecha, forma_pago, nombre, apellido
-- FROM vista_pedidos_cliente
-- EXCEPT
-- SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
-- FROM pedido p
-- JOIN cliente c ON c.id_cliente = p.id_cliente;
--
-- SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
-- FROM pedido p
-- JOIN cliente c ON c.id_cliente = p.id_cliente
-- EXCEPT
-- SELECT id_pedido, fecha, forma_pago, nombre, apellido
-- FROM vista_pedidos_cliente;