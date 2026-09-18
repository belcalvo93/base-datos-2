# Spec — índice de historial de pedidos por cliente y fecha

## Objetivo

Optimizar C2 de `food-store/queries.sql`, usada para consultar el historial de
pedidos de un cliente mostrando primero los más recientes.

## Consulta

```sql
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.id_cliente = 10
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
