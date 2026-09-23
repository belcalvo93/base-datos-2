# Spec — Procedimiento `registrar_pedido` (TPI Punto 5 / TP5 Parte B)

**Archivo de implementación:** `food-store/procedimientos.sql`
**Contexto:** el TPI Punto 5 pide cubrir funciones y procedimientos. El
esquema ya valida ventas vía triggers (TP2) pero el descuento de stock
quedó documentado como responsabilidad de la aplicación en
`food-store/restricciones.sql:58-59`. `registrar_pedido` materializa esa
responsabilidad en código PL/pgSQL: registra un pedido completo
(cabecera + líneas) y descuenta stock como una unidad atómica.

---

## 1. Qué es

Procedimiento almacenado que encapsula la operación de negocio de
registrar un pedido. Recibe un cliente, una forma de pago y los ítems
como JSONB, crea la cabecera en `pedido`, inserta cada línea en
`detalle_pedido` con el precio congelado (R4) y descuenta el stock de
`producto`. Todo dentro de una única transacción implícita: o se ejecuta
el flujo completo o no queda nada a medio guardar.

### Firma y parámetros

```sql
CREATE OR REPLACE PROCEDURE registrar_pedido(
    p_id_cliente BIGINT,
    p_forma_pago forma_pago_enum,
    p_items JSONB  -- [{"id_producto": 1, "cantidad": 2}, ...]
)
```

| Parámetro | Tipo | Descripción |
|---|---|---|
| `p_id_cliente` | `BIGINT` | FK al cliente que realiza el pedido |
| `p_forma_pago` | `forma_pago_enum` | `EFECTIVO`, `TARJETA` o `TRANSFERENCIA` |
| `p_items` | `JSONB` | Lista de ítems `[{"id_producto": N, "cantidad": M}]` |

### Algoritmo

1. Valida que la lista no esté vacía (`RAISE EXCEPTION` si lo está).
2. Inserta la cabecera en `pedido` (`fecha = now()`, `RETURNING id_pedido`).
3. Por cada ítem: lee el `precio` vigente de `producto`, valida que exista
   y lo congela en `detalle_pedido.precio_unitario`.
4. Descuenta `cantidad` del `stock` de `producto`.

---

## 2. Por qué es un PROCEDURE (se invoca con CALL) y no una función

- **Modifica tres tablas** (`pedido`, `detalle_pedido`, `producto`) y
  procesa N líneas por pedido; es una operación de efecto, no de cálculo.
- **No devuelve un valor** de retorno: informa el resultado con
  `RAISE NOTICE`. Una función PL/pgSQL exigiría un tipo de retorno (o
  `RETURNS void`) y naturalmente se ejecuta dentro de una expresión
  `SELECT ... FROM`; en cambio, quien invoca a `registrar_pedido` lo
  hace con `CALL`, que es la sintaxis prevista para acciones sobre datos.

---

## 3. Conexión con `restricciones.sql`

Los triggers `trg_verificar_producto_activo` y `trg_verificar_stock_suficiente`
validan cada `INSERT` en `detalle_pedido`:
- Regla 1: rechaza vender un producto con `activo = FALSE`.
- Regla 2: rechaza vender más cantidad que el stock disponible.

Su rol es **validar**: `restricciones.sql:58-59` deja escrito que "este
trigger solo valida. El descuento de stock sigue siendo responsabilidad
de la aplicación". Ese descuento es exactamente lo que ejecuta el
procedimiento (su `UPDATE producto SET stock = stock - v_cantidad`).
La validación y el descuento quedan así separados: el trigger decide si
la venta es legal y el procedimiento ejecuta el efecto material.

---

## 4. Evidencia de prueba (23/09/2026)

Ambos casos se ejecutaron con `BEGIN; ... ROLLBACK;` sobre `bd2_tp3`
para no alterar los datos reales, según `protocolo_seguridad.md`.

### Caso 1 — Éxito

```sql
BEGIN;
CALL registrar_pedido(20155, 'EFECTIVO',
                      '[{"id_producto": 1, "cantidad": 2}]'::jsonb);
SELECT stock FROM producto WHERE id_producto = 1;  -- 12 -> 10 dentro de la transacción
ROLLBACK;
```

Producto `id_producto = 1` con stock inicial 12.

**Resultado observado:** `RAISE NOTICE` "Pedido 245006 registrado con 1
linea(s)", y stock descontado a 10 dentro de la transacción. Tras el
`ROLLBACK`, el stock se verificó de nuevo en 12: la reversión fue
correcta.

### Caso 2 — Fallo (atomicidad)

```sql
BEGIN;
CALL registrar_pedido(20155, 'EFECTIVO',
                      '[{"id_producto": 1, "cantidad": 1000}]'::jsonb);
ROLLBACK;
```

Cantidad 1000, mayor al stock (12).

**Resultado observado:** el trigger `trg_verificar_stock_suficiente`
aborta la operación:

```
ERROR: Stock insuficiente para el producto con id 1: se solicitan 1000
unidades, pero hay 12 en stock
```

**Verificación posterior:** el stock del producto 1 sigue en 12 y no
quedó ningún pedido nuevo para el cliente 20155 en los últimos 5 minutos
(`COUNT = 0`). Confirma la atomicidad: ni el pedido ni el detalle
quedaron a medio guardar.

---

## 5. Criterio de aceptación

1. Un `CALL` válido crea 1 cabecera en `pedido`, N líneas en
   `detalle_pedido` (con `precio_unitario` congelado) y descuenta stock;
   dentro de una transacción se revierte por completo con `ROLLBACK`.
2. Un `CALL` con stock insuficiente es abortado por
   `trg_verificar_stock_suficiente` sin dejar ni pedido ni detalle a
   medio guardar (atomicidad).
3. `p_items` vacío dispara el `RAISE EXCEPTION` de validación.