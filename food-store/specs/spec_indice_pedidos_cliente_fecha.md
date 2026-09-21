# Spec — índice de historial de pedidos por cliente y fecha

## Objetivo

Optimizar C2 de `food-store/queries.sql`, usada para consultar el historial de
pedidos de un cliente mostrando primero los más recientes.

## Consulta

```sql
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.id_cliente = 20155
ORDER BY p.fecha DESC;
```

## Frecuencia y carga

Es una consulta operativa frecuente del historial de compras. `pedido` es una
tabla grande y el resultado debe llegar ordenado por fecha descendente.

## Columnas relevantes

- Filtro y join: `pedido.id_cliente`.
- Orden: `pedido.fecha DESC`.

## Hipótesis para OpenCode

Evaluar un índice compuesto `(id_cliente, fecha DESC)`. El índice existente
`idx_pedido_id_cliente` cubre el filtro, pero no el orden; el índice compuesto
solo se acepta si elimina o reduce el `Sort` y mejora el tiempo total.

## Criterio de aceptación

Comparar planes y tiempos antes/después con
`EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`. Medir también el costo de escritura que
agrega el índice. Si la consulta devuelve pocas filas y el `Sort` resulta
insignificante, se documenta el descarte.

## Resultado de la medición (21/09/2026)

Base: `bd2_tp3` (200.005 pedidos). Evidencia en
`food-store/informe_mediciones.md` (sección 4.2) y
`food-store/planes_tp5_parteA.txt`.

**`(id_cliente, fecha DESC)`: descartado.** La consulta devuelve 24 filas, por
lo que el `Sort` (quicksort, 26 kB) cuesta microsegundos. El planificador no
usa el índice nuevo: mantiene `idx_pedido_id_cliente` + `Sort`, con el mismo
plan y el mismo tiempo (0,15 ms antes y después). Además cuesta +26 % de WAL
en cada `INSERT` de `pedido` (medido: 500 INSERT). Se cumple la salida
prevista por la spec: "si la consulta devuelve pocas filas y el `Sort` resulta
insignificante, se documenta el descarte".

**Decisión confirmada por el autor el 21/09/2026.**
