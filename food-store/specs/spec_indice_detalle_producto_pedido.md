# Spec — índice de detalle por producto y pedido

## Objetivo

Optimizar C3 de `food-store/queries.sql`, usada para consultar los pedidos en
los que apareció un producto y ordenar esos pedidos por fecha.

## Consulta

```sql
SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE dp.id_producto = 49112
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

## Resultado de la medición (21/09/2026)

Base: `bd2_tp3` (499.263 detalles). Evidencia en
`food-store/informe_mediciones.md` (sección 4.3) y
`food-store/planes_tp5_parteA.txt`.

**`(id_producto, id_pedido)`: descartado por sobreindexación.** El
planificador sí usa el índice nuevo, pero el plan es el mismo que con
`idx_detalle_pedido_id_producto` (Bitmap Heap Scan, 27 bloques, `Index Scan`
en `pedido_pkey`) y no mejora el tiempo: `pgbench` da 0,68-0,86 ms sin el
índice y 0,73-0,78 ms con él, rangos que se superponen. La segunda columna no
ahorra ningún acceso porque `cantidad` y `precio_unitario` igual se leen del
heap, y `id_pedido` ya está cubierto por `UNIQUE (id_pedido, id_producto)`.
Es un superconjunto del índice existente y cuesta +17 % de WAL en cada
`INSERT` de `detalle_pedido` (medido: 500 INSERT).

**Decisión confirmada por el autor el 21/09/2026.**
