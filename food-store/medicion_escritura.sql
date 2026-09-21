-- ============================================================================
-- medicion_escritura.sql — TP5, Parte A, consigna 5: costo de los índices
-- sobre las escrituras.
--
-- Mide 500 INSERT por tabla (detalle_pedido, pedido, producto) y 500 UPDATE de
-- producto.stock bajo distintos estados de índices. Cada estado corre en su
-- propia transacción que termina en ROLLBACK: la base queda intacta y los
-- índices de prueba desaparecen con el rollback (protocolo_seguridad.md, paso 2).
--
-- Uso (una ronda; el informe usa 15 y toma la mediana):
--   psql -U postgres -d bd2_trabajo -X -A -t -f food-store/medicion_escritura.sql
-- Cada línea de salida:  tabla | estado | milisegundos | bytes_de_WAL
--
-- Detalles del método (ver informe_mediciones.md, sección 5):
--  * Cada INSERT es una sentencia independiente dentro de un bucle PL/pgSQL:
--    en cada fila corren los triggers de restricciones.sql (producto activo y
--    stock suficiente) y se mantienen todos los índices de la tabla.
--  * Los datos de cada carga se calculan antes de medir, fuera del tiempo.
--  * Cada carga arranca con una corrida de calentamiento sin medir (los
--    planes de los triggers se compilan en la primera ejecución de la sesión).
--  * Tras cada ROLLBACK se hace VACUUM de la tabla cargada: sin eso, las
--    tuplas muertas de la carga revertida sesgan los estados siguientes.
--  * El estado base se mide dos veces (base_a al inicio, base_b al final): su
--    diferencia es el piso de ruido del tiempo. Los bytes de WAL casi no
--    tienen ruido y son la métrica más confiable del trabajo de índices.
-- ============================================================================
\set ON_ERROR_STOP on
SELECT 'base: ' || current_database() AS "verificar_base";

-- Índices bajo prueba (no se crean acá de forma permanente).
\set i1_parcial   'CREATE INDEX idx_producto_categoria_precio_parcial ON producto (id_categoria, precio DESC) WHERE activo = TRUE'
\set i1_cubriente 'CREATE INDEX idx_producto_categoria_precio ON producto (id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo = TRUE'
\set i2           'CREATE INDEX idx_pedido_cliente_fecha ON pedido (id_cliente, fecha DESC)'
\set i3           'CREATE INDEX idx_detalle_producto_pedido ON detalle_pedido (id_producto, id_pedido)'
\set todas        :i1_parcial '; ' :i1_cubriente '; ' :i2 '; ' :i3
\set nada         'SELECT 1'

-- Datos de las cargas de detalle_pedido y pedido (temporales de sesión).
CREATE TEMP TABLE w_detalle AS
WITH ped AS (
    SELECT id_pedido, row_number() OVER (ORDER BY id_pedido) AS n
    FROM (SELECT id_pedido, row_number() OVER (ORDER BY id_pedido) AS r FROM pedido) x
    WHERE r % 397 = 0
), prod AS (
    SELECT id_producto, row_number() OVER (ORDER BY (id_producto * 7919) % 50021) AS n
    FROM producto WHERE activo AND stock >= 5
)
SELECT ped.n, 1 + (ped.n % 4) AS cantidad, 100 + (ped.n % 50) AS precio_unitario,
       ped.id_pedido, prod.id_producto
FROM ped JOIN prod USING (n)
WHERE NOT EXISTS (SELECT 1 FROM detalle_pedido d
                  WHERE d.id_pedido = ped.id_pedido AND d.id_producto = prod.id_producto)
ORDER BY ped.n LIMIT 500;

CREATE TEMP TABLE w_pedido AS
SELECT n, id_cliente,
       (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA'])[1 + n % 3]::forma_pago_enum AS forma_pago
FROM (SELECT id_cliente, row_number() OVER (ORDER BY (id_cliente * 7919) % 20011) AS n
      FROM cliente) c
ORDER BY n LIMIT 500;

-- Control: las dos cargas precalculadas deben tener exactamente 500 filas.
SELECT (SELECT count(*) FROM w_detalle) AS detalle,
       (SELECT count(*) FROM w_pedido)  AS pedido;

-- Cuerpos de las tres cargas.
\set body_detalle 'DO $$ DECLARE r record; BEGIN FOR r IN SELECT * FROM w_detalle ORDER BY n LOOP INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto) VALUES (r.cantidad, r.precio_unitario, r.id_pedido, r.id_producto); END LOOP; END $$'
\set body_pedido 'DO $$ DECLARE r record; BEGIN FOR r IN SELECT * FROM w_pedido ORDER BY n LOOP INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES (timestamptz ''2026-09-15 12:00:00-03'' + (r.n || '' minutes'')::interval, r.forma_pago, r.id_cliente); END LOOP; END $$'
\set body_producto 'DO $$ BEGIN FOR n IN 1..500 LOOP INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria) VALUES (''Producto de prueba de escritura '' || n, NULL, 100 + (n * 37) % 900, 50, TRUE, (SELECT id_categoria FROM categoria ORDER BY id_categoria OFFSET (n % 5) LIMIT 1)); END LOOP; END $$'

-- ---------------------------------------------------------------------------
-- Carga 1 — detalle_pedido (la que pide la consigna).
-- Solo los índices de detalle_pedido (i3) participan de estos INSERT.
-- ---------------------------------------------------------------------------
\set tabla detalle_pedido
BEGIN; :body_detalle; ROLLBACK; VACUUM :tabla;   -- calentamiento, sin medir

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_a|:ms|:wal

BEGIN; :i1_cubriente;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|aceptado (i1_cubriente)|:ms|:wal

BEGIN; :i3;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|descartado (i3)|:ms|:wal

BEGIN; :todas;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|todas las propuestas|:ms|:wal

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_b|:ms|:wal

-- ---------------------------------------------------------------------------
-- Carga 2 — pedido. Índice que la afecta: i2 (descartado).
-- ---------------------------------------------------------------------------
\set tabla pedido
BEGIN; :body_pedido; ROLLBACK; VACUUM :tabla;   -- calentamiento, sin medir

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_pedido;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_a|:ms|:wal

BEGIN; :i1_cubriente;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_pedido;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|aceptado (i1_cubriente)|:ms|:wal

BEGIN; :i2;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_pedido;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|descartado (i2)|:ms|:wal

BEGIN; :todas;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_pedido;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|todas las propuestas|:ms|:wal

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_pedido;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_b|:ms|:wal

-- ---------------------------------------------------------------------------
-- Carga 3 — producto. Índices que la afectan: i1_cubriente (aceptado) e
-- i1_parcial (descartado).
-- ---------------------------------------------------------------------------
\set tabla producto
BEGIN; :body_producto; ROLLBACK; VACUUM :tabla;   -- calentamiento, sin medir

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_producto;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_a|:ms|:wal

BEGIN; :i1_cubriente;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_producto;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|aceptado (i1_cubriente)|:ms|:wal

BEGIN; :i1_parcial;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_producto;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|descartado (i1_parcial)|:ms|:wal

BEGIN; :todas;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_producto;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|todas las propuestas|:ms|:wal

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_producto;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base_b|:ms|:wal

-- ---------------------------------------------------------------------------
-- Carga 4 — UPDATE de producto.stock (500 filas, un UPDATE por fila).
-- Es el riesgo del índice cubriente: incluye stock, así que cada UPDATE de
-- stock deja de ser HOT y obliga a mantener ese índice. El índice parcial sin
-- INCLUDE (i1_parcial) no contiene stock y sirve de contraste.
-- ---------------------------------------------------------------------------
\set tabla producto
CREATE TEMP TABLE w_stock AS
SELECT id_producto FROM producto WHERE activo AND stock >= 5
ORDER BY (id_producto * 7919) % 50021 LIMIT 500;
\set body_stock 'DO $$ DECLARE r record; BEGIN FOR r IN SELECT id_producto FROM w_stock LOOP UPDATE producto SET stock = stock - 1 WHERE id_producto = r.id_producto; END LOOP; END $$'
BEGIN; :body_stock; ROLLBACK; VACUUM :tabla;   -- calentamiento, sin medir

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_stock;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo producto (UPDATE stock)|base_a|:ms|:wal

BEGIN; :i1_cubriente;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_stock;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo producto (UPDATE stock)|aceptado (i1_cubriente)|:ms|:wal

BEGIN; :i1_parcial;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_stock;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo producto (UPDATE stock)|descartado (i1_parcial)|:ms|:wal

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_stock;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo producto (UPDATE stock)|base_b|:ms|:wal

-- ---------------------------------------------------------------------------
-- Carga 5 — detalle_pedido con el índice cubriente evaluado para P4-A (i5).
-- Se agregó después de las cargas 1-4, con su propio par base5_a/base5_b.
-- ---------------------------------------------------------------------------
\set i5 'CREATE INDEX idx_detalle_pedido_producto_cubriente ON detalle_pedido (id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)'
\set tabla detalle_pedido
BEGIN; :body_detalle; ROLLBACK; VACUUM :tabla;   -- calentamiento, sin medir

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base5_a|:ms|:wal

BEGIN; :i5;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|descartado (i5)|:ms|:wal

BEGIN; :nada;
SELECT pg_current_wal_insert_lsn() AS l0, clock_timestamp() AS t0 \gset
:body_detalle;
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 1) AS ms, pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'l0') AS wal \gset
ROLLBACK; VACUUM :tabla;
\echo :tabla|base5_b|:ms|:wal
