-- ============================================================
-- TP U4 — Parte 2: costo de escritura del trigger de sincronización
-- Spec: food-store/specs/spec_top_categorias_desnormalizacion.md (6.1, punto 7)
-- Base de ejecución: bd2_tp4u4, con tp_desnormalizacion_top_categorias.sql
-- ya confirmado. Cada ronda corre en BEGIN…ROLLBACK: no deja nada.
-- ============================================================
-- Ejecución:
--   psql -U postgres -d bd2_tp4u4 -f food-store/medicion_escritura_top_categorias.sql
-- Una ronda = un pedido nuevo con 500 líneas, insertadas de a una (500
-- INSERT individuales, como en medicion_escritura.sql del TP5). Se mide
-- tiempo y bytes de WAL. "Sin trigger" apaga solo el de sincronización.
-- Se alternan los dos casos 5 veces y se toma la mediana de cada uno.
-- ============================================================

\set ON_ERROR_STOP on

SELECT current_database();

SET timezone = 'America/Argentina/Mendoza';

-- Función temporal: existe solo en esta sesión, no queda en la base
CREATE FUNCTION pg_temp.medir_500_inserts()
RETURNS TABLE (ms NUMERIC, wal_bytes NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_pedido BIGINT;
    v_producto  RECORD;
    v_inicio    TIMESTAMPTZ;
    v_lsn       pg_lsn;
BEGIN
    INSERT INTO pedido (fecha, forma_pago, id_cliente)
    VALUES (now(), 'EFECTIVO', (SELECT min(id_cliente) FROM cliente))
    RETURNING id_pedido INTO v_id_pedido;

    v_inicio := clock_timestamp();
    v_lsn    := pg_current_wal_insert_lsn();

    -- Productos activos y con stock, por los triggers del TP2
    FOR v_producto IN
        SELECT id_producto, precio
          FROM producto
         WHERE activo AND stock >= 1
         ORDER BY id_producto
         LIMIT 500
    LOOP
        INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
        VALUES (1, v_producto.precio, v_id_pedido, v_producto.id_producto);
    END LOOP;

    ms        := round(EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)::numeric * 1000, 3);
    wal_bytes := pg_wal_lsn_diff(pg_current_wal_insert_lsn(), v_lsn);
    RETURN NEXT;
END;
$$;

-- Calentamiento (se descarta)
BEGIN;
SELECT 'calentamiento' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;

-- Ronda 1
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;
SELECT 'sin trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
BEGIN;
SELECT 'con trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;

-- Ronda 2
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;
SELECT 'sin trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
BEGIN;
SELECT 'con trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;

-- Ronda 3
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;
SELECT 'sin trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
BEGIN;
SELECT 'con trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;

-- Ronda 4
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;
SELECT 'sin trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
BEGIN;
SELECT 'con trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;

-- Ronda 5
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_resumen_ventas_detalle;
SELECT 'sin trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
BEGIN;
SELECT 'con trigger' AS caso, * FROM pg_temp.medir_500_inserts();
ROLLBACK;
