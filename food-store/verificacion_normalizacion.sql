-- ============================================================
-- Verificación de normalización — Base de Datos 2
-- ============================================================
-- Contrasta contra los datos las dependencias funcionales (DF) que
-- se afirman en docs/normalizacion_er_relacional.md.
--
-- Script de SOLO LECTURA: corre dentro de una transacción READ ONLY
-- (el motor rechaza cualquier INSERT/UPDATE/DELETE) y termina con
-- ROLLBACK. No modifica nada.
--
-- Recordatorio para la lectura de resultados: los datos pueden
-- REFUTAR una DF (basta un contraejemplo), pero nunca DEMOSTRARLA.
-- Que una DF "se cumpla" en una extensión concreta de la tabla no
-- prueba que sea una regla del dominio; las DF se deducen de la
-- semántica (reglas R1–R7), no de los datos.
--
-- Uso (Git Bash), sobre la base poblada de la Unidad 2 (contiene las
-- semillas de data.sql más la carga masiva):
--   psql -U postgres -d bd2_tp3 -X -f food-store/verificacion_normalizacion.sql
-- ============================================================

BEGIN TRANSACTION READ ONLY;

SELECT current_database();

-- ------------------------------------------------------------
-- V1. Claves que el motor hace cumplir (PK, UNIQUE, FK)
-- Muestra que cada clave candidata del documento está declarada:
-- si está declarada, la DF clave -> resto de la fila la garantiza
-- el motor, no la buena voluntad de quien carga los datos.
-- ------------------------------------------------------------
SELECT conrelid::regclass            AS tabla,
       CASE contype WHEN 'p' THEN 'PK'
                    WHEN 'u' THEN 'UNIQUE'
                    WHEN 'f' THEN 'FK' END AS tipo,
       pg_get_constraintdef(oid)     AS definicion
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND contype IN ('p', 'u', 'f')
ORDER BY conrelid::regclass::text, contype DESC, conname;

-- ------------------------------------------------------------
-- V2. subtotal no se almacena en detalle_pedido
-- Si apareciera, habría una DF cantidad, precio_unitario -> subtotal
-- entre atributos no clave (dependencia transitiva, rompe 3FN).
-- Se espera: ninguna fila.
-- ------------------------------------------------------------
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'detalle_pedido'
  AND column_name  = 'subtotal';

-- ------------------------------------------------------------
-- V3. id_producto -/-> precio_unitario   (R4, precio histórico)
-- Si un mismo producto tiene más de un precio_unitario, la DF
-- id_producto -> precio_unitario queda refutada: precio_unitario
-- depende de la clave completa (id_pedido, id_producto), no de una
-- parte (no hay dependencia parcial, 2FN).
-- ------------------------------------------------------------
SELECT COUNT(*)                                        AS productos_vendidos,
       COUNT(*) FILTER (WHERE precios_distintos > 1)   AS productos_con_mas_de_un_precio
FROM (
    SELECT id_producto, COUNT(DISTINCT precio_unitario) AS precios_distintos
    FROM detalle_pedido
    GROUP BY id_producto
) t;

-- ------------------------------------------------------------
-- V4. precio_unitario no es una copia de producto.precio
-- Líneas cuyo precio congelado difiere del precio de lista vigente.
-- Si hay alguna, guardar precio_unitario no es redundancia: es un
-- dato distinto (el precio al momento de la venta).
-- ------------------------------------------------------------
SELECT COUNT(*)                                                AS lineas,
       COUNT(*) FILTER (WHERE d.precio_unitario <> p.precio)   AS lineas_con_precio_distinto_al_vigente
FROM detalle_pedido d
JOIN producto p ON p.id_producto = d.id_producto;

-- ------------------------------------------------------------
-- V5. (id_pedido, id_producto) es clave candidata de detalle_pedido
-- Se espera: 0 (además lo garantiza el UNIQUE listado en V1).
-- ------------------------------------------------------------
SELECT COUNT(*) AS pares_pedido_producto_repetidos
FROM (
    SELECT id_pedido, id_producto
    FROM detalle_pedido
    GROUP BY id_pedido, id_producto
    HAVING COUNT(*) > 1
) t;

-- ------------------------------------------------------------
-- V6. Atributos que NO son clave (no determinan al resto)
-- Cada contador > 0 es un contraejemplo de una DF que no existe:
--   - producto.nombre -/-> id_producto   (nombres repetidos)
--   - cliente(nombre, apellido) -/-> id_cliente (homónimos)
--   - pedido.id_cliente -/-> forma_pago   (el cliente elige en cada pedido)
--   - pedido.fecha -/-> id_cliente        (dos pedidos en el mismo instante)
-- Los que den 0 no prueban nada (ver el recordatorio del encabezado).
-- ------------------------------------------------------------
SELECT 'producto.nombre repetido'                 AS caso,
       COUNT(*) - COUNT(DISTINCT nombre)          AS contraejemplos
FROM producto
UNION ALL
SELECT 'cliente (nombre, apellido) repetido',
       COUNT(*) - COUNT(DISTINCT (nombre, apellido))
FROM cliente
UNION ALL
SELECT 'cliente con más de una forma_pago',
       COUNT(*)
FROM (
    SELECT id_cliente
    FROM pedido
    GROUP BY id_cliente
    HAVING COUNT(DISTINCT forma_pago) > 1
) t
UNION ALL
SELECT 'fecha de pedido compartida por clientes distintos',
       COUNT(*)
FROM (
    SELECT fecha
    FROM pedido
    GROUP BY fecha
    HAVING COUNT(DISTINCT id_cliente) > 1
) t;

-- ------------------------------------------------------------
-- V7. Claves candidatas alternativas sin duplicados
-- Se espera: 0 en todas (además las garantizan los UNIQUE de V1).
-- ------------------------------------------------------------
SELECT 'cliente.email'   AS clave_candidata,
       COUNT(*) - COUNT(DISTINCT email)  AS duplicados
FROM cliente
UNION ALL
SELECT 'categoria.nombre',
       COUNT(*) - COUNT(DISTINCT nombre)
FROM categoria;

-- ------------------------------------------------------------
-- V8. Detalle del contraejemplo de V3/V4
-- Todas las ventas de los productos que tienen más de un
-- precio_unitario: muestra el mismo producto cobrado a precios
-- distintos en pedidos distintos.
-- ------------------------------------------------------------
SELECT p.id_producto, p.nombre, p.precio AS precio_lista_vigente,
       pe.fecha, d.precio_unitario, d.cantidad
FROM detalle_pedido d
JOIN producto p ON p.id_producto = d.id_producto
JOIN pedido  pe ON pe.id_pedido  = d.id_pedido
WHERE d.id_producto IN (
    SELECT id_producto
    FROM detalle_pedido
    GROUP BY id_producto
    HAVING COUNT(DISTINCT precio_unitario) > 1
)
ORDER BY p.id_producto, pe.fecha;

ROLLBACK;
