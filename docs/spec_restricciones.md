# Spec de restricciones de integridad — Parte 1

Reglas de negocio del proyecto que hoy no están garantizadas por el motor y
dependen de que la aplicación las valide. Esta spec se escribe antes de pedirle
nada a la IA.

Base sobre la que se trabaja: `bd2_trabajo` (copia de desarrollo).

## Regla 1 — No se puede vender un producto dado de baja

Un producto con `producto.activo = FALSE` está retirado de la venta (baja
lógica, regla R7 del TP1). Actualmente nada impide insertar en
`detalle_pedido` una fila cuyo `id_producto` apunte a un producto inactivo.

**Qué debe garantizar el motor:** al insertar o actualizar una fila de
`detalle_pedido`, si el producto referenciado por `detalle_pedido.id_producto`
tiene `producto.activo = FALSE`, la operación debe rechazarse con un mensaje de
error explícito.

**Por qué no alcanza un CHECK:** un CHECK solo puede evaluar columnas de la
propia fila. Esta regla necesita consultar otra tabla (`producto`), así que
requiere un trigger.

## Regla 2 — No se puede vender más cantidad que el stock disponible

El esquema tiene `CHECK (stock >= 0)` en `producto` y `CHECK (cantidad > 0)` en
`detalle_pedido`, pero ninguna relación entre ambos. Hoy es posible registrar la
venta de 50 unidades de un producto que tiene 3 en stock.

**Qué debe garantizar el motor:** al insertar o actualizar una fila de
`detalle_pedido`, si `detalle_pedido.cantidad` es mayor que el
`producto.stock` del producto referenciado, la operación debe rechazarse con un
mensaje de error explícito que indique la cantidad pedida y el stock disponible.

**Alcance decidido:** el trigger solo valida; no modifica `producto.stock`. El
descuento de stock sigue siendo responsabilidad de la aplicación.

**Limitación conocida:** al validar cada línea por separado, la suma de varias
líneas en pedidos distintos puede superar el stock total. La restricción cubre
la validación por línea, no el control de stock acumulado.

**Por qué no alcanza un CHECK:** igual que la Regla 1, requiere leer una columna
de otra tabla.

## Casos de prueba a verificar

Sobre `bd2_trabajo`, dentro de una transacción con ROLLBACK:

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Insertar en `detalle_pedido` el producto 'Helado 1L' (`activo = FALSE`) | Rechazado por la Regla 1 |
| 2 | Insertar en `detalle_pedido` el producto 'Agua mineral 2L' con `cantidad = 2` (stock 40) | Aceptado |
| 3 | Insertar en `detalle_pedido` el producto 'Gaseosa cola 2.25L' con `cantidad = 50` (stock 1) | Rechazado por la Regla 2 |
| 4 | Insertar en `detalle_pedido` el producto 'Medialunas x6' con `cantidad = 3` (stock 3) | Aceptado (el límite es válido) |

## Archivo a generar

`sql/restricciones.sql`, con los triggers y sus funciones asociadas, escrito de
forma que se pueda reejecutar sin error (DROP TRIGGER IF EXISTS previo).