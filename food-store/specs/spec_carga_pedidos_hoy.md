# Spec: Carga de pedidos de hoy

**Responsable**: Elías  
**Fecha de creación**: 2026-10-18  
**Última revisión**: —

---

## 1. Objetivo

Poblar la base `bd2_tp4u4` con pedidos y detalles del día actual (fecha = `CURRENT_DATE`) para contar con datos medibles en la consulta adaptada del punto 5.1.

---

## 2. Consulta

### 2.1. Volumen propuesto

- **Pedidos**: entre 5.000 y 10.000 pedidos de hoy.
- **Detalles**: 1-3 productos por pedido (promedio ~2).
- **Distribución de forma_pago**: ~33% cada forma (EFECTIVO, TARJETA, TRANSFERENCIA).
- **Clientes**: usar clientes existentes de la base.

### 2.2. Consulta adaptada del punto 5.1 (para verificación)

```sql
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;
```

---

## 3. Frecuencia y carga

- **Frecuencia**: una sola vez (carga inicial del TP U4).
- **Carga estimada**: ~10.000 pedidos × ~2 detalles = ~20.000 detalles nuevos.
- **Supuestos del dominio**:
  - La carga masiva existente del TP3 distribuye pedidos en 2 años, dejando hoy prácticamente vacío.
  - Los triggers de TP2 (`trg_verificar_producto_activo`, `trg_verificar_stock_suficiente`) YA están activos y deben respetarse.

---

## 4. Columnas relevantes

| Tabla | Columnas |
|-------|----------|
| `pedido` | fecha (entre CURRENT_DATE y now()), forma_pago, id_cliente |
| `detalle_pedido` | cantidad, precio_unitario (congelado, debe ser ≤ precio actual del producto), id_pedido, id_producto |
| `producto` | id_producto, precio, stock, activo |
| `categoria` | id_categoria, nombre |

---

## 5. Estado actual medido

No aplica (es carga nueva).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Verificar la existencia de los triggers** de TP2 en `restricciones.sql`:
   - `trg_verificar_producto_activo` → rejects inactive products
   - `trg_verificar_stock_suficiente` → rejects if cantidad > stock

2. **Generar脚本 de carga** (`food-store/carga_pedidos_hoy.sql`) que:
   - Use productos con `activo = TRUE`.
   - Use cantidades ≤ `producto.stock` (los triggers validan esto).
   - Asigne `precio_unitario` ≤ `producto.precio` (congelado histórico, regla R4).
   - Genere fechas entre `CURRENT_DATE` y `CURRENT_DATE + INTERVAL '1 day'`.
   - Respete la restricción `UNIQUE (id_pedido, id_producto)` en detalle_pedido.
   - Sea idempotente (eliminar pedidos de hoy antes de cargar nuevos).

3. **Verificación post-carga**:
   - Conteo de pedidos de hoy.
   - Conteo de detalles de hoy.
   - Ejecutar la consulta adaptada del punto 5.1 y verificar que devuelve 5 filas.

4. **Ejecutar VACUUM ANALYZE** al terminar (obligatorio para que los planes sean representativos).

### 6.2. Lo que NO se puede hacer sin justificar

- Insertar productos con `activo = FALSE`.
- Insertar cantidades mayores al stock disponible (los triggers lo rechazan).
- Usar el procedimiento `registrar_pedido` (descuenta stock y es más lento).
- Modificar la estructura de las tablas existentes.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- El script corre sin errores.
- Conteo de pedidos de hoy > 0.
- Conteo de detalles de hoy > 0.
- La consulta adaptada del punto 5.1 devuelve exactamente 5 filas (top 5 categorías por ventas).
- `VACUUM ANALYZE` se ejecuta al final.

### 7.2. Salida de descarte

Si la consulta adaptada no devuelve 5 filas, se descarta y se documenta el motivo (probablemente falta de volumen).

---

## 8. Resultado de la medición

*Fecha: 19/10/2026*  
*Estado: Aceptado. Script `food-store/carga_pedidos_hoy.sql` ejecutado en `bd2_tp4u4`, primero con ROLLBACK y después con COMMIT, seguido de `VACUUM ANALYZE`.*  
*Pedidos de hoy: 10.000.*  
*Detalles de hoy: 20.012 (la corrida de prueba con ROLLBACK dio 20.054; el sorteo es aleatorio).*  
*Productos distintos vendidos: 16.484.*  
*Reparto de forma_pago: 3.290 / 3.329 / 3.381.*  
*Consulta del 5.1 adaptada: 5 filas.*