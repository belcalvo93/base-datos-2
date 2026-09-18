# Spec — índice de productos vigentes por categoría y precio

## Objetivo

Optimizar C1 de `food-store/queries.sql`, usada para mostrar el catálogo
vigente de una categoría ordenado por precio descendente.

## Consulta

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.id_categoria = 10
  AND p.activo = TRUE
ORDER BY p.precio DESC;
```

## Frecuencia y carga

Es una consulta de catálogo frecuente. Se ejecuta sobre la tabla masiva de
productos y debe conservar el filtro de baja lógica.

## Columnas relevantes

- Filtro: `producto.id_categoria`, `producto.activo`.
- Orden: `producto.precio DESC`.

## Hipótesis para OpenCode

Evaluar un índice parcial compuesto sobre `(id_categoria, precio DESC)` con
condición `activo = TRUE`. El índice solo se acepta si el plan y el tiempo
mejoran respecto del índice parcial existente y el costo adicional de escritura
es justificable.

## Criterio de aceptación

Registrar `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` antes y después. Comparar tipo de
scan, presencia del `Sort`, buffers y tiempo total. Si el nuevo índice solo
duplica el índice parcial existente sin una mejora medible, se descarta.
