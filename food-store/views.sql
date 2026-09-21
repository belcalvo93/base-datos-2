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

-- vista_detalle_pedido_producto
-- Propósito: mostrar cada línea de detalle_pedido junto con el nombre del
-- producto vendido, para reconstruir el contenido de un pedido sin hacer
-- el JOIN contra producto por separado. Sin filtro de vigencia: reconstruye
-- hechos pasados; precio_unitario es histórico congelado (R4), independiente
-- del precio de lista. La baja lógica protege contra ventas futuras, no
-- contra la consulta de ventas pasadas.
-- INNER JOIN: detalle_pedido.id_producto es NOT NULL (FK con ON DELETE RESTRICT).
-- Idempotente: CREATE OR REPLACE VIEW.

CREATE OR REPLACE VIEW vista_detalle_pedido_producto AS
SELECT dp.id_detalle, dp.id_pedido, pr.nombre AS nombre_producto,
       dp.cantidad, dp.precio_unitario
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto;

-- Verificación (criterio de aceptación de la spec): no ejecutar en cada corrida.
-- Ambas direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT id_detalle, id_pedido, nombre_producto, cantidad, precio_unitario
-- FROM vista_detalle_pedido_producto
-- EXCEPT
-- SELECT dp.id_detalle, dp.id_pedido, pr.nombre,
--        dp.cantidad, dp.precio_unitario
-- FROM detalle_pedido dp
-- JOIN producto pr ON pr.id_producto = dp.id_producto;
--
-- SELECT dp.id_detalle, dp.id_pedido, pr.nombre,
--        dp.cantidad, dp.precio_unitario
-- FROM detalle_pedido dp
-- JOIN producto pr ON pr.id_producto = dp.id_producto
-- EXCEPT
-- SELECT id_detalle, id_pedido, nombre_producto, cantidad, precio_unitario
-- FROM vista_detalle_pedido_producto;

-- vista_usuario_reportes
-- Propósito: exponer los datos de usuario para reportes y administración
-- ocultando la columna contrasena (criterio de seguridad, punto 4 Parte B;
-- tabla usuario agregada por indicación de la cátedra — ver schema.sql y
-- food-store/duia.md). Incluye rol y eliminado; solo usuarios vigentes
-- (eliminado = FALSE), por eso eliminado vale siempre FALSE aquí. Las columnas
-- se listan explícitamente (no SELECT *) para excluir contrasena a propósito.
-- Solo lectura: sin WITH CHECK OPTION ni trigger INSTEAD OF.
-- Idempotente: CREATE OR REPLACE VIEW.

CREATE OR REPLACE VIEW vista_usuario_reportes AS
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM usuario
WHERE eliminado = FALSE;

-- Verificación (criterio de aceptación de la spec): no ejecutar en cada corrida.
-- Ambas direcciones del EXCEPT deben devolver exactamente 0 filas:
--
-- SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
-- FROM vista_usuario_reportes
-- EXCEPT
-- SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
-- FROM usuario
-- WHERE eliminado = FALSE;
--
-- SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
-- FROM usuario
-- WHERE eliminado = FALSE
-- EXCEPT
-- SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
-- FROM vista_usuario_reportes;
--
-- Verificación adicional: contrasena no debe estar expuesta en la vista:
--
-- SELECT column_name
-- FROM information_schema.columns
-- WHERE table_name = 'vista_usuario_reportes'
--   AND column_name = 'contrasena';