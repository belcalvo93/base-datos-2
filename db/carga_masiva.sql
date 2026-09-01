-- ============================================================
-- Carga masiva de datos — TP3 (Unidad 2)
-- ============================================================
-- Adaptación del Genera_registros.sql de la cátedra al esquema
-- del proyecto. Genera volumen para demostrar diferencias de
-- rendimiento entre estrategias de indexación.
--
-- Archivo de salida: db/carga_masiva.sql
-- Base de trabajo:   bd2_tp3 (copia de bd2_trabajo)
--
-- Orden de los INSERT (respeta dependencias FK):
--   1. producto      (depende de categoria — ya existente)
--   2. cliente
--   3. pedido        (depende de cliente)
--   4. detalle_pedido (depende de pedido y producto)
--
-- Sin BEGIN/COMMIT: la transacción es responsabilidad de quien
-- ejecuta (protocolo_seguridad.md). Envolver en BEGIN/ROLLBACK
-- para prueba, luego BEGIN/COMMIT para carga definitiva.
-- Sin CREATE INDEX ni ANALYZE: esas operaciones van en scripts
-- separados después de confirmar la carga.
-- ============================================================

-- ============================================================
-- CONFIG: ajustar los tres generate_series para cada escenario.
-- En la prueba se reducen LOS TRES contadores, no solo el de
-- pedidos. El cuello de botella de ORDER BY random() depende del
-- tamaño de la tabla barrida: mantener 50.000 productos y 20.000
-- clientes como dominio de selección daría una estimación de
-- tiempo no representativa.
--
-- Prueba reducida:
--   generate_series(1, 500)   → producto
--   generate_series(1, 200)   → cliente
--   generate_series(1, 500)   → pedido
--
-- Producción:
--   generate_series(1, 50000)  → producto
--   generate_series(1, 20000)  → cliente
--   generate_series(1, 200000) → pedido
-- ============================================================


-- ============================================================
-- 1. PRODUCTO
-- ============================================================
-- precio: rango $10–$1000, dos decimales (CHECK precio >= 0)
-- stock:  rango 50–200 (D2). Con cantidad máxima 4 en detalle,
--         ninguna inserción viola el trigger
--         trg_verificar_stock_suficiente.
-- activo: TRUE (D4). El trigger trg_verificar_producto_activo
--         rechaza productos inactivos; todos los generados aquí
--         están activos.
-- id_categoria: selección aleatoria de las categorías existentes.
-- ============================================================
INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria)
SELECT
    'Producto ' || i,
    NULL,
    ROUND((random() * 990 + 10)::NUMERIC, 2),
    (random() * 150 + 50)::INTEGER,
    TRUE,
    (SELECT id_categoria FROM categoria ORDER BY random() LIMIT 1)
FROM generate_series(1, 500) AS s(i);


-- ============================================================
-- 2. CLIENTE
-- ============================================================
-- email: 'cliente' + i + '@mail.com' es UNIQUE por construcción
--        (sufijo secuencial).
-- telefono: NULL (columna nullable; simplifica la generación).
-- ============================================================
INSERT INTO cliente (nombre, apellido, email, telefono)
SELECT
    'Nombre' || i,
    'Apellido' || i,
    'cliente' || i || '@mail.com',
    NULL
FROM generate_series(1, 200) AS s(i);


-- ============================================================
-- 3. PEDIDO
-- ============================================================
-- fecha: now() - (random() * INTERVAL '2 años'). Distribuye
--        pedidos en los últimos 2 años; rango estable para
--        consultas por fecha.
-- forma_pago: selección aleatoria entre las tres constantes del
--             ENUM forma_pago_enum. Array + floor(random()*3+1)
--             es idéntico al script de cátedra.
-- id_cliente: selección aleatoria de los recién insertados.
-- ============================================================
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT
    now() - (random() * INTERVAL '2 years'),
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA'])[floor(random() * 3 + 1)],
    (SELECT id_cliente FROM cliente ORDER BY random() LIMIT 1)
FROM generate_series(1, 500) AS s(i);


-- ============================================================
-- 4. DETALLE_PEDIDO
-- ============================================================
-- Cada pedido recibe entre 1 y 4 líneas. La mecánica es:
--
--   a) CTE lineas_por_pedido: asigna n_lineas = (random()*3+1)::INTEGER
--      a cada pedido. Se reutiliza tanto para el campo cantidad
--      como para el filtro WHERE, evitando recalcular random().
--
--   b) CROSS JOIN LATERAL con subquery anidada:
--      - Nivel interno: ORDER BY random() LIMIT 4 sobre producto.
--        Barre la tabla completa (Seq Scan; ORDER BY random() no
--        aprovecha índices porque genera un valor nuevo por fila
--        que no está indexado — decisión D1) y devuelve 4 filas
--        al azar. Al salir de una misma ordenación, los 4
--        id_producto son distintos entre sí por construcción.
--      - Nivel externo: ROW_NUMBER() OVER () sobre las 4 filas ya
--        seleccionadas. Numerar 4 filas es trivial; si el
--        ROW_NUMBER estuviera en el mismo nivel que el ORDER BY,
--        el motor numera las 50.000 filas antes del LIMIT, lo
--        cual es innecesario.
--
--   c) WHERE p.rn <= lpp.n_lineas: se queda con los primeros 1–4
--      productos según n_lineas. La restricción
--      UNIQUE (id_pedido, id_producto) nunca colisiona porque
--      cada pedido obtiene productos distintos de un único sort.
--
-- precio_unitario: se toma de producto.precio mediante el JOIN
--   del lateral (D3). El precio histórico se congela en el
--   momento de la venta (R4).
-- ============================================================
WITH
lineas_por_pedido AS (
    SELECT id_pedido, (random() * 3 + 1)::INTEGER AS n_lineas
    FROM pedido
)
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
SELECT
    lpp.n_lineas,
    p.precio,
    lpp.id_pedido,
    p.id_producto
FROM lineas_por_pedido lpp
CROSS JOIN LATERAL (
    SELECT id_producto, precio,
           ROW_NUMBER() OVER () AS rn
    FROM (
        SELECT id_producto, precio
        FROM producto
        ORDER BY random()
        LIMIT 4
    ) sub
) p
WHERE p.rn <= lpp.n_lineas;
