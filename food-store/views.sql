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

-- vista_productos_vigentes
-- Propósito: mostrar cada producto activo junto con el nombre de su
-- categoría, aplicando el filtro de vigencia en ambas tablas. Un producto
-- cuya categoría esté dada de baja no aparece, aunque el producto esté activo.
-- INNER JOIN: producto.id_categoria es NOT NULL (FK con participación total).
-- Idempotente: CREATE OR REPLACE VIEW.

CREATE OR REPLACE VIEW vista_productos_vigentes AS
SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre AS nombre_categoria
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.activo = TRUE AND c.activo = TRUE;

-- Verificación (criterio de aceptación de la spec): no ejecutar en cada corrida.
-- Ambas direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT id_producto, nombre, precio, stock, nombre_categoria
-- FROM vista_productos_vigentes
-- EXCEPT
-- SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre
-- FROM producto p
-- JOIN categoria c ON c.id_categoria = p.id_categoria
-- WHERE p.activo = TRUE AND c.activo = TRUE;
--
-- SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre
-- FROM producto p
-- JOIN categoria c ON c.id_categoria = p.id_categoria
-- WHERE p.activo = TRUE AND c.activo = TRUE
-- EXCEPT
-- SELECT id_producto, nombre, precio, stock, nombre_categoria
-- FROM vista_productos_vigentes;