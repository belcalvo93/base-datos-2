# Spec — índice de detalle por producto y pedido

## Objetivo

Optimizar C3 de `food-store/queries.sql`, usada para consultar los pedidos en
los que apareció un producto y ordenar esos pedidos por fecha.

## Consulta

```sql
SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE dp.id_producto = 64074
ORDER BY ped.fecha DESC;
```

## Frecuencia y carga

Es una consulta de trazabilidad de producto. `detalle_pedido` es la tabla más
voluminosa del modelo y el filtro por producto debe reducir el conjunto antes
del join.

## Columnas relevantes

- Filtro: `detalle_pedido.id_producto`.
- Join: `detalle_pedido.id_pedido = pedido.id_pedido`.
- Orden final: `pedido.fecha DESC`.

## Hipótesis para OpenCode

Evaluar si el índice existente sobre `detalle_pedido(id_producto)` alcanza y si
un índice compuesto `(id_producto, id_pedido)` aporta algo medible al join.
No se acepta automáticamente una segunda variante: puede ser redundante con el
índice existente y con la restricción única `(id_pedido, id_producto)`.

## Criterio de aceptación

Comparar planes, buffers y tiempos antes/después. El índice solo se conserva
si cambia favorablemente el acceso a `detalle_pedido` o reduce el trabajo del
join sin introducir un costo de escritura desproporcionado.
