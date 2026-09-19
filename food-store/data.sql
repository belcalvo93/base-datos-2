-- ============================================================
-- Datos de carga inicial — Base de Datos 2
-- Proyecto integrador (esquema del TP N.º 1)
-- ============================================================
-- No se insertan los id: las PK son GENERATED ALWAYS AS IDENTITY,
-- por lo que el motor las asigna. Las claves foráneas se resuelven
-- con subconsultas sobre las claves naturales (nombre, email).
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- CATEGORIA
-- Se incluye una categoría inactiva a propósito: sirve para probar
-- la baja lógica (R7) y como caso inválido en la Parte 1.
-- ------------------------------------------------------------
INSERT INTO categoria (nombre, activo) VALUES
    ('Panificados',   TRUE),
    ('Bebidas',       TRUE),
    ('Lácteos',       TRUE),
    ('Almacén',       TRUE),
    ('Congelados',    FALSE);

-- ------------------------------------------------------------
-- CLIENTE
-- ------------------------------------------------------------
INSERT INTO cliente (nombre, apellido, email, telefono) VALUES
    ('Ana',      'Gutiérrez', 'ana.gutierrez@example.com',  '2614001001'),
    ('Bruno',    'Salinas',   'bruno.salinas@example.com',  '2614001002'),
    ('Carla',    'Medina',    'carla.medina@example.com',   NULL),
    ('Diego',    'Ferrari',   'diego.ferrari@example.com',  '2614001004'),
    ('Elena',    'Ríos',      'elena.rios@example.com',     '2614001005');

-- ------------------------------------------------------------
-- PRODUCTO
-- Stock deliberadamente bajo en algunos productos: son los que se
-- usan en la Parte 2 para forzar espera por bloqueo sobre la misma fila.
-- Se incluye un producto inactivo (R7).
-- ------------------------------------------------------------
INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria) VALUES
    ('Pan de campo 1kg',      'Pan de masa madre, horneado del día', 2500.00,  12, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Panificados')),
    ('Medialunas x6',         'Medialunas de manteca',               3200.00,   3, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Panificados')),
    ('Agua mineral 2L',       'Agua sin gas',                        1400.00,  40, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas')),
    ('Gaseosa cola 2.25L',    'Bebida gasificada',                   3900.00,   1, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas')),
    ('Leche entera 1L',       'Leche entera en sachet',              1800.00,  25, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Lácteos')),
    ('Queso cremoso 500g',    'Queso cremoso fraccionado',           7600.00,   8, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Lácteos')),
    ('Yerba mate 1kg',        'Yerba con palo',                      6800.00,  15, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Almacén')),
    ('Aceite girasol 900ml',  'Aceite de girasol',                   4100.00,  20, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Almacén')),
    ('Fideos secos 500g',     'Fideos tipo mostachol',               1950.00,  30, TRUE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Almacén')),
    ('Helado 1L',             'Producto dado de baja lógicamente',   9500.00,   0, FALSE,
        (SELECT id_categoria FROM categoria WHERE nombre = 'Congelados'));

-- ------------------------------------------------------------
-- PEDIDO
-- Fechas explícitas (no now()) para que las consultas por rango
-- den resultados estables al reejecutar la carga.
-- ------------------------------------------------------------
INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES
    ('2026-08-01 10:15:00-03', 'EFECTIVO',
        (SELECT id_cliente FROM cliente WHERE email = 'ana.gutierrez@example.com')),
    ('2026-08-03 18:40:00-03', 'TARJETA',
        (SELECT id_cliente FROM cliente WHERE email = 'bruno.salinas@example.com')),
    ('2026-08-07 09:05:00-03', 'TRANSFERENCIA',
        (SELECT id_cliente FROM cliente WHERE email = 'ana.gutierrez@example.com')),
    ('2026-08-12 20:30:00-03', 'TARJETA',
        (SELECT id_cliente FROM cliente WHERE email = 'carla.medina@example.com')),
    ('2026-08-18 12:00:00-03', 'EFECTIVO',
        (SELECT id_cliente FROM cliente WHERE email = 'diego.ferrari@example.com'));

-- ------------------------------------------------------------
-- DETALLE_PEDIDO
-- precio_unitario congela el precio histórico (R4): en el pedido más
-- antiguo se cargan valores menores al precio de lista vigente, para
-- que se note que son independientes.
-- Se respeta UNIQUE (id_pedido, id_producto).
-- ------------------------------------------------------------
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto) VALUES
    (2, 2200.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-01 10:15:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Pan de campo 1kg')),
    (1, 1650.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-01 10:15:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Leche entera 1L')),

    (3, 1400.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-03 18:40:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Agua mineral 2L')),
    (1, 6800.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-03 18:40:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Yerba mate 1kg')),

    (1, 7600.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-07 09:05:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Queso cremoso 500g')),
    (2, 3200.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-07 09:05:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Medialunas x6')),

    (4, 1950.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-12 20:30:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Fideos secos 500g')),
    (1, 4100.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-12 20:30:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Aceite girasol 900ml')),

    (1, 3900.00,
        (SELECT id_pedido FROM pedido WHERE fecha = '2026-08-18 12:00:00-03'),
        (SELECT id_producto FROM producto WHERE nombre = 'Gaseosa cola 2.25L'));

-- ------------------------------------------------------------
-- USUARIO (datos de prueba — TP5 Parte B)
-- Tabla agregada por indicación directa de la cátedra (profesor
-- Sergio Neira), documentada en food-store/duia.md: es una
-- tabla de login independiente de cliente (ver schema.sql).
-- Los valores de contrasena son hashes placeholder no legibles
-- (hex aleatorio), nunca texto plano: la columna almacena el hash.
-- Se incluye un usuario dado de baja (eliminado = TRUE) a propósito:
-- verifica que vista_usuario_reportes lo excluye (WHERE eliminado = FALSE).
-- ------------------------------------------------------------
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol, eliminado)
VALUES
    ('Nicole', 'González', 'n.gonzalez@foodstore.com', '+54 9 11 5555-0101',
     '3f7a9c1e5b2d4f6a8c0e1d2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b', 'ADMIN', FALSE),
    ('Matías', 'Ríos',     'm.rios@foodstore.com',     '+54 9 11 5555-0102',
     '9c3e2d1f4a6b8c5d7e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d', 'USUARIO', FALSE),
    ('Sofía',  'Luna',     's.luna@foodstore.com',     '+54 9 11 5555-0103',
     'b0a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c', 'USUARIO', TRUE);
