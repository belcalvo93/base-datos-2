-- ============================================================
-- Restricciones de integridad — Reglas de negocio
-- ============================================================
-- Regla 1: No se puede vender un producto dado de baja (activo = FALSE).
-- Regla 2: No se puede vender más cantidad que el stock disponible.
--
-- Ambas requieren triggers porque necesitan consultar la tabla
-- producto desde una operación sobre detalle_pedido, lo que un
-- CHECK no puede hacer.
-- ============================================================

-- ============================================================
-- REGLA 1 — Producto inactivo
-- ============================================================
-- Antes de cada INSERT o UPDATE en detalle_pedido, verifica que
-- el producto referenciado esté activo. Si no lo está, rechaza
-- la operación con un mensaje de error claro.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_verificar_producto_activo()
RETURNS TRIGGER AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo INTO v_activo
      FROM producto
     WHERE id_producto = NEW.id_producto;

    IF v_activo = FALSE THEN
        RAISE EXCEPTION 'No se puede vender el producto con id %: está dado de baja (activo = FALSE)',
                        NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Se elimina el trigger previo si existe, para permitir reejecución
-- sin errores. Luego se crea el trigger a nivel de fila BEFORE,
-- que se ejecuta en cada INSERT o UPDATE sobre detalle_pedido.
DROP TRIGGER IF EXISTS trg_verificar_producto_activo ON detalle_pedido;

CREATE TRIGGER trg_verificar_producto_activo
    BEFORE INSERT OR UPDATE
    ON detalle_pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_verificar_producto_activo();


-- ============================================================
-- REGLA 2 — Stock insuficiente
-- ============================================================
-- Antes de cada INSERT o UPDATE en detalle_pedido, verifica que
-- la cantidad solicitada no supere el stock disponible del
-- producto. Si lo supera, rechaza la operación indicando la
-- cantidad pedida y el stock actual.
--
-- Nota: este trigger solo valida. El descuento de stock sigue
-- siendo responsabilidad de la aplicación.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_verificar_stock_suficiente()
RETURNS TRIGGER AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    SELECT stock INTO v_stock
      FROM producto
     WHERE id_producto = NEW.id_producto;

    IF NEW.cantidad > v_stock THEN
        RAISE EXCEPTION 'Stock insuficiente para el producto con id %: se solicitan % unidades, pero hay % en stock',
                        NEW.id_producto, NEW.cantidad, v_stock;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_verificar_stock_suficiente ON detalle_pedido;

CREATE TRIGGER trg_verificar_stock_suficiente
    BEFORE INSERT OR UPDATE
    ON detalle_pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_verificar_stock_suficiente();
