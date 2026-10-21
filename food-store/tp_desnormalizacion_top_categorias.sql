-- ============================================================
-- TP U4 — Parte 2 (c, d, e): desnormalización controlada
-- Specs: food-store/specs/spec_top_categorias_desnormalizacion.md (spec 5)
--        food-store/specs/spec_top_categorias_auditoria.md (spec 6)
-- Base de ejecución: bd2_tp4u4. NUNCA bd2_tp3 ni bd2_proyecto.
-- ============================================================
-- Patrón 1: tabla resumen por día y categoría, mantenida por trigger.
--
-- Protocolo (protocolo_seguridad.md):
--   1. Primera corrida con ROLLBACK (como está): se crea todo, se prueba
--      y se deshace. Revisar que la auditoría dé 0 filas y que cada
--      prueba de detección devuelva filas.
--   2. Segunda corrida: cambiar el ROLLBACK de la última línea por COMMIT.
--   3. Después del COMMIT: VACUUM ANALYZE resumen_ventas_categoria_dia;
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/tp_desnormalizacion_top_categorias.sql
-- La reversión real está aparte, en tp_desnormalizacion_reversion.sql.
-- ============================================================

\set ON_ERROR_STOP on

-- Tiene que decir bd2_tp4u4
SELECT current_database();

-- El día de negocio es el de Mendoza, no el del servidor
SET timezone = 'America/Argentina/Mendoza';

BEGIN;

-- ------------------------------------------------------------
-- 0. Idempotencia: si el script ya se confirmó antes, se borra todo y
--    se vuelve a crear. Ninguna tabla fuente se toca.
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_resumen_ventas_detalle ON detalle_pedido;
DROP TRIGGER IF EXISTS trg_resumen_ventas_pedido_borrado ON pedido;
DROP FUNCTION IF EXISTS fn_trg_resumen_ventas_detalle();
DROP FUNCTION IF EXISTS fn_trg_resumen_ventas_pedido_borrado();
DROP FUNCTION IF EXISTS fn_resumen_ventas_aplicar_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
DROP TABLE IF EXISTS resumen_ventas_categoria_dia;

-- ------------------------------------------------------------
-- 1. Estructura desnormalizada (5.2c)
--    PK con fecha primero: la consulta del panel filtra por un día.
--    Sin índice sobre total_vendido: cambia en cada venta y solo
--    ahorraría ordenar 5 filas (spec 5, 2.1).
-- ------------------------------------------------------------
CREATE TABLE resumen_ventas_categoria_dia (
    fecha           DATE          NOT NULL,
    id_categoria    BIGINT        NOT NULL REFERENCES categoria (id_categoria) ON DELETE RESTRICT,
    total_vendido   NUMERIC(12,2) NOT NULL,
    cantidad_lineas INTEGER       NOT NULL CHECK (cantidad_lineas > 0),
    PRIMARY KEY (fecha, id_categoria)
);

-- ------------------------------------------------------------
-- 2. Mecanismo de sincronización (5.2c)
--    fn_resumen_ventas_aplicar_linea es la ÚNICA que escribe en el
--    resumen. Los dos triggers solo la llaman.
-- ------------------------------------------------------------
CREATE FUNCTION fn_resumen_ventas_aplicar_linea(
    p_id_pedido   BIGINT,
    p_id_producto BIGINT,
    p_monto       NUMERIC,
    p_signo       INTEGER   -- +1 suma una línea, -1 la resta
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_fecha        DATE;
    v_id_categoria BIGINT;
BEGIN
    SELECT (fecha AT TIME ZONE 'America/Argentina/Mendoza')::date
      INTO v_fecha
      FROM pedido
     WHERE id_pedido = p_id_pedido;

    -- Si el pedido ya no existe es un borrado en cascada: esas líneas
    -- ya las restó trg_resumen_ventas_pedido_borrado. No se resta dos veces.
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT id_categoria
      INTO v_id_categoria
      FROM producto
     WHERE id_producto = p_id_producto;

    IF p_signo = 1 THEN
        INSERT INTO resumen_ventas_categoria_dia (fecha, id_categoria, total_vendido, cantidad_lineas)
        VALUES (v_fecha, v_id_categoria, p_monto, 1)
        ON CONFLICT (fecha, id_categoria) DO UPDATE
           SET total_vendido   = resumen_ventas_categoria_dia.total_vendido + EXCLUDED.total_vendido,
               cantidad_lineas = resumen_ventas_categoria_dia.cantidad_lineas + 1;
    ELSE
        -- Si es la última línea de ese día y categoría, la fila se borra
        -- (no por total = 0: precio_unitario admite 0)
        DELETE FROM resumen_ventas_categoria_dia
         WHERE fecha = v_fecha
           AND id_categoria = v_id_categoria
           AND cantidad_lineas = 1;

        IF NOT FOUND THEN
            UPDATE resumen_ventas_categoria_dia
               SET total_vendido   = total_vendido - p_monto,
                   cantidad_lineas = cantidad_lineas - 1
             WHERE fecha = v_fecha
               AND id_categoria = v_id_categoria;
        END IF;
    END IF;
END;
$$;

-- En un UPDATE se resta la línea vieja y se suma la nueva: la línea pudo
-- cambiar de producto (otra categoría) o de pedido (otro día).
CREATE FUNCTION fn_trg_resumen_ventas_detalle() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        PERFORM fn_resumen_ventas_aplicar_linea(OLD.id_pedido, OLD.id_producto,
                                                OLD.cantidad * OLD.precio_unitario, -1);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM fn_resumen_ventas_aplicar_linea(NEW.id_pedido, NEW.id_producto,
                                                NEW.cantidad * NEW.precio_unitario, 1);
    END IF;
    RETURN NULL;
END;
$$;

-- Borrado de un pedido: por el ON DELETE CASCADE, el trigger de
-- detalle_pedido ya no encuentra el pedido y no sabe de qué día restar.
-- Por eso las líneas se restan acá, antes de que el pedido desaparezca.
CREATE FUNCTION fn_trg_resumen_ventas_pedido_borrado() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_linea RECORD;
BEGIN
    FOR v_linea IN
        SELECT id_producto, cantidad * precio_unitario AS monto
          FROM detalle_pedido
         WHERE id_pedido = OLD.id_pedido
    LOOP
        PERFORM fn_resumen_ventas_aplicar_linea(OLD.id_pedido, v_linea.id_producto, v_linea.monto, -1);
    END LOOP;
    RETURN OLD;
END;
$$;

-- Los triggers se crean ANTES de la carga inicial: CREATE TRIGGER bloquea
-- las escrituras en la tabla hasta el fin de la transacción, así ninguna
-- venta queda entre la carga y el momento en que el trigger empieza a andar.
CREATE TRIGGER trg_resumen_ventas_detalle
    AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_trg_resumen_ventas_detalle();

CREATE TRIGGER trg_resumen_ventas_pedido_borrado
    BEFORE DELETE ON pedido
    FOR EACH ROW EXECUTE FUNCTION fn_trg_resumen_ventas_pedido_borrado();

-- ------------------------------------------------------------
-- 3. Carga inicial: TODOS los días, no solo hoy, para que coincida con
--    lo que recalcula la auditoría.
-- ------------------------------------------------------------
INSERT INTO resumen_ventas_categoria_dia (fecha, id_categoria, total_vendido, cantidad_lineas)
SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date,
       pr.id_categoria,
       SUM(dp.cantidad * dp.precio_unitario),
       COUNT(*)
  FROM detalle_pedido dp
  JOIN producto pr ON pr.id_producto = dp.id_producto
  JOIN pedido ped  ON ped.id_pedido  = dp.id_pedido
 GROUP BY 1, 2;

SELECT count(*) AS filas_resumen,
       count(DISTINCT fecha) AS dias
  FROM resumen_ventas_categoria_dia;

-- ------------------------------------------------------------
-- 4. Consulta del punto 5.2(d): el mismo reporte, leyendo del resumen
-- ------------------------------------------------------------
SELECT c.nombre AS categoria,
       r.total_vendido
  FROM resumen_ventas_categoria_dia r
  JOIN categoria c ON c.id_categoria = r.id_categoria
 WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
 ORDER BY r.total_vendido DESC
 LIMIT 5;

-- 4.1 Mismo resultado que la consulta original (5.1 adaptada).
--     EXCEPT en los dos sentidos: tiene que dar 0 filas.
WITH original AS (
    SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
      FROM detalle_pedido dp
      JOIN producto pr  ON pr.id_producto = dp.id_producto
      JOIN categoria c  ON c.id_categoria = pr.id_categoria
      JOIN pedido ped   ON ped.id_pedido  = dp.id_pedido
     WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
     GROUP BY c.nombre
     ORDER BY total_vendido DESC
     LIMIT 5
),
nueva AS (
    SELECT c.nombre AS categoria, r.total_vendido
      FROM resumen_ventas_categoria_dia r
      JOIN categoria c ON c.id_categoria = r.id_categoria
     WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
     ORDER BY r.total_vendido DESC
     LIMIT 5
)
(SELECT 'solo en la original' AS lado, * FROM (SELECT * FROM original EXCEPT SELECT * FROM nueva) a)
UNION ALL
(SELECT 'solo en la nueva' AS lado, * FROM (SELECT * FROM nueva EXCEPT SELECT * FROM original) b);

-- ------------------------------------------------------------
-- 5. Auditoría (5.2e): recalcula desde la fuente, para TODOS los días,
--    y compara en los dos sentidos. Tiene que dar 0 filas.
--    Si da filas, no se corrige el valor a mano: se revisa el mecanismo.
-- ------------------------------------------------------------
CREATE TEMP VIEW v_auditoria_resumen AS
WITH fuente AS (
    SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha,
           c.id_categoria,
           SUM(dp.cantidad * dp.precio_unitario) AS total_vendido,
           COUNT(*)::int AS cantidad_lineas
      FROM categoria c
     INNER JOIN producto pr       ON pr.id_categoria = c.id_categoria
     INNER JOIN detalle_pedido dp ON dp.id_producto  = pr.id_producto
     INNER JOIN pedido ped        ON ped.id_pedido   = dp.id_pedido
     GROUP BY 1, 2
),
guardado AS (
    SELECT fecha, id_categoria, total_vendido, cantidad_lineas
      FROM resumen_ventas_categoria_dia
)
(SELECT 'solo en el resumen' AS lado, * FROM (SELECT * FROM guardado EXCEPT SELECT * FROM fuente) a)
UNION ALL
(SELECT 'solo en la fuente' AS lado, * FROM (SELECT * FROM fuente EXCEPT SELECT * FROM guardado) b);

-- 5.1 Sobre la base recién cargada: 0 filas
SELECT * FROM v_auditoria_resumen ORDER BY fecha, id_categoria, lado;

-- ------------------------------------------------------------
-- 6. Pruebas. Cada una se deshace con ROLLBACK TO SAVEPOINT, así no
--    deja rastros aunque el script termine en COMMIT.
-- ------------------------------------------------------------

-- 6.0 El mecanismo funciona: después de insertar, modificar, mover de
--     categoría y borrar líneas, y de borrar un pedido entero, la
--     auditoría sigue en 0 filas.
SAVEPOINT prueba_mecanismo;

-- El último pedido cargado. No se filtra por hoy, para que las pruebas
-- anden cualquier día.
SELECT max(id_pedido) AS id_pedido_prueba
  FROM pedido
\gset

-- Inserción: una línea nueva en ese pedido, con un producto activo y
-- con stock (triggers del TP2) que no esté ya en ese pedido
INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
SELECT 1, pr.precio, :id_pedido_prueba, pr.id_producto
  FROM producto pr
 WHERE pr.activo AND pr.stock >= 1
   AND NOT EXISTS (SELECT 1 FROM detalle_pedido d
                    WHERE d.id_pedido = :id_pedido_prueba AND d.id_producto = pr.id_producto)
 ORDER BY pr.id_producto
 LIMIT 1;

-- Modificación de cantidad
UPDATE detalle_pedido
   SET cantidad = cantidad + 1
 WHERE id_detalle = (SELECT min(d.id_detalle) FROM detalle_pedido d
                       JOIN producto pr ON pr.id_producto = d.id_producto
                      WHERE d.id_pedido = :id_pedido_prueba AND pr.stock >= d.cantidad + 1);

-- Mover una línea a un producto de otra categoría
UPDATE detalle_pedido d
   SET id_producto = (SELECT pr2.id_producto FROM producto pr2
                       WHERE pr2.activo AND pr2.stock >= d.cantidad
                         AND pr2.id_categoria <> (SELECT id_categoria FROM producto WHERE id_producto = d.id_producto)
                         AND NOT EXISTS (SELECT 1 FROM detalle_pedido x
                                          WHERE x.id_pedido = d.id_pedido AND x.id_producto = pr2.id_producto)
                       ORDER BY pr2.id_producto
                       LIMIT 1)
 WHERE d.id_detalle = (SELECT max(id_detalle) FROM detalle_pedido WHERE id_pedido = :id_pedido_prueba);

-- Borrado de una línea
DELETE FROM detalle_pedido
 WHERE id_detalle = (SELECT min(id_detalle) FROM detalle_pedido WHERE id_pedido = :id_pedido_prueba);

-- Borrado de un pedido entero (sus líneas caen por cascada)
DELETE FROM pedido WHERE id_pedido = :id_pedido_prueba;

-- Tiene que dar 0 filas
SELECT * FROM v_auditoria_resumen ORDER BY fecha, id_categoria, lado;

ROLLBACK TO SAVEPOINT prueba_mecanismo;

-- 6.1 Detección: mecanismo apagado. Se apaga solo el trigger de
--     sincronización (no ALL: apagaría también los triggers internos
--     de las FK) y se inserta una venta. Tiene que dar filas.
SAVEPOINT prueba_trigger_apagado;

ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;

SELECT min(id_pedido) AS id_pedido_prueba
  FROM pedido
\gset

INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
SELECT 1, pr.precio, :id_pedido_prueba, pr.id_producto
  FROM producto pr
 WHERE pr.activo AND pr.stock >= 1
   AND NOT EXISTS (SELECT 1 FROM detalle_pedido d
                    WHERE d.id_pedido = :id_pedido_prueba AND d.id_producto = pr.id_producto)
 ORDER BY pr.id_producto
 LIMIT 1;

SELECT * FROM v_auditoria_resumen ORDER BY fecha, id_categoria, lado;

ROLLBACK TO SAVEPOINT prueba_trigger_apagado;

-- 6.2 Detección: alguien escribe el resumen a mano (rompe la regla del
--     único dueño). Tiene que dar 2 filas, una de cada lado.
SAVEPOINT prueba_escritura_a_mano;

-- Sobre la fila del día más reciente del resumen
UPDATE resumen_ventas_categoria_dia
   SET total_vendido = total_vendido + 1
 WHERE (fecha, id_categoria) = (SELECT fecha, id_categoria
                                  FROM resumen_ventas_categoria_dia
                                 ORDER BY fecha DESC, id_categoria
                                 LIMIT 1);

SELECT * FROM v_auditoria_resumen ORDER BY fecha, id_categoria, lado;

ROLLBACK TO SAVEPOINT prueba_escritura_a_mano;

-- 6.3 Detección: caso fuera de alcance. Cambiar la categoría de un
--     producto con ventas no lo cubre el trigger (spec 5), pero la
--     auditoría lo detecta. Tiene que dar filas.
SAVEPOINT prueba_cambio_categoria;

UPDATE producto pr
   SET id_categoria = (SELECT min(c.id_categoria) FROM categoria c
                        WHERE c.id_categoria <> pr.id_categoria)
 WHERE pr.id_producto = (SELECT id_producto FROM detalle_pedido
                          ORDER BY id_detalle DESC
                          LIMIT 1);

SELECT * FROM v_auditoria_resumen ORDER BY fecha, id_categoria, lado;

ROLLBACK TO SAVEPOINT prueba_cambio_categoria;

-- 6.4 Reversión: se borra todo lo que creó este script y se comprueba que
--     las tablas fuente quedan iguales. La reversión real está en
--     tp_desnormalizacion_reversion.sql.
SAVEPOINT prueba_reversion;

SELECT (SELECT count(*) FROM pedido)         AS pedidos_antes,
       (SELECT count(*) FROM detalle_pedido) AS detalles_antes
\gset

DROP TRIGGER trg_resumen_ventas_detalle ON detalle_pedido;
DROP TRIGGER trg_resumen_ventas_pedido_borrado ON pedido;
DROP FUNCTION fn_trg_resumen_ventas_detalle();
DROP FUNCTION fn_trg_resumen_ventas_pedido_borrado();
DROP FUNCTION fn_resumen_ventas_aplicar_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
DROP VIEW v_auditoria_resumen;
DROP TABLE resumen_ventas_categoria_dia;

-- Tiene que dar: resumen_existe = f, y los dos conteos iguales a los de antes
SELECT to_regclass('resumen_ventas_categoria_dia') IS NOT NULL AS resumen_existe,
       (SELECT count(*) FROM pedido)         = :pedidos_antes  AS pedidos_iguales,
       (SELECT count(*) FROM detalle_pedido) = :detalles_antes AS detalles_iguales;

ROLLBACK TO SAVEPOINT prueba_reversion;

-- Primera corrida: ROLLBACK. Para aplicar de verdad, cambiar por COMMIT.
ROLLBACK;
