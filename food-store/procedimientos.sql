-- ============================================================
-- Procedimiento almacenado — Registro de pedido
-- ============================================================
-- registrar_pedido encapsula la operación de negocio de registrar
-- un pedido: crea el pedido, inserta sus líneas con el precio
-- congelado en detalle_pedido y descuenta stock.
--
-- Es un PROCEDURE (se invoca con CALL), no una función:
--  1. Modifica tres tablas (pedido, detalle_pedido, producto) y
--     procesa N líneas por pedido; no produce un valor de retorno.
--  2. Por eso CALL es el mecanismo natural y no SELECT/FROM.
--  3. Ejecuta el UPDATE de stock que, como documenta
--     restricciones.sql ("el descuento de stock sigue siendo
--     responsabilidad de la aplicación"), queda delegado a la
--     aplicación (aquí materializado en el procedimiento).
--
-- Recibe los items como JSONB: [{"id_producto": 1, "cantidad": 2}, ...]
-- ============================================================

CREATE OR REPLACE PROCEDURE registrar_pedido(
    p_id_cliente BIGINT,
    p_forma_pago forma_pago_enum,
    p_items JSONB  -- [{"id_producto": 1, "cantidad": 2}, ...]
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_pedido     BIGINT;
    v_item          JSONB;
    v_id_producto   BIGINT;
    v_cantidad      INTEGER;
    v_precio        NUMERIC(10,2);
BEGIN
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El pedido debe tener al menos un producto';
    END IF;

    INSERT INTO pedido (fecha, forma_pago, id_cliente)
    VALUES (now(), p_forma_pago, p_id_cliente)
    RETURNING id_pedido INTO v_id_pedido;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_id_producto := (v_item->>'id_producto')::BIGINT;
        v_cantidad    := (v_item->>'cantidad')::INTEGER;

        SELECT precio INTO v_precio
          FROM producto
         WHERE id_producto = v_id_producto;

        IF v_precio IS NULL THEN
            RAISE EXCEPTION 'El producto con id % no existe', v_id_producto;
        END IF;

        INSERT INTO detalle_pedido (cantidad, precio_unitario, id_pedido, id_producto)
        VALUES (v_cantidad, v_precio, v_id_pedido, v_id_producto);

        UPDATE producto
           SET stock = stock - v_cantidad
         WHERE id_producto = v_id_producto;
    END LOOP;

    RAISE NOTICE 'Pedido % registrado con % linea(s)', v_id_pedido, jsonb_array_length(p_items);
END;
$$;