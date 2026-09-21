# Spec — índice de productos vigentes por categoría y precio

## Objetivo

Optimizar C1 de `food-store/queries.sql`, usada para mostrar el catálogo
vigente de una categoría ordenado por precio descendente.

## Consulta

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.id_categoria = 5
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

## Resultado de la medición (21/09/2026)

Base: `bd2_tp3` restaurada desde `bd2_tp3_actualizada_20260919.dump`
(50.011 productos). Evidencia completa en `food-store/informe_mediciones.md`
(sección 4.1) y `food-store/planes_tp5_parteA.txt`.

**Hipótesis original — `(id_categoria, precio DESC) WHERE activo = TRUE`:
rechazada.** El planificador no usa el índice nuevo: sigue con
`idx_producto_categoria_activo` (Bitmap Heap Scan + Sort) y el tiempo queda
idéntico (10,5 ms). Como el índice no contiene `nombre` ni `stock`, cada fila
exigiría una visita al heap y el costo estimado supera al del bitmap. Es el
caso "solo duplica el índice parcial existente" que el criterio de aceptación
manda descartar.

**Iteración 2 — agregar `INCLUDE (id_producto, nombre, stock)`: aceptada.**
La consulta devuelve solo columnas que el índice ahora contiene, así que el
plan pasa a `Index Only Scan` sin `Sort` y con `Heap Fetches: 0`:
10,5 ms → 3,1 ms (mediana de 5), 527 → 86 buffers. El resultado es idéntico
fila por fila (`EXCEPT` en ambas direcciones: 0 filas).

Costo aceptado: 3,3 MB de índice y +45 % de WAL por `INSERT` en `producto`
(+32 % de WAL por `UPDATE` de `stock`, que ahora deja de ser barato porque
`stock` forma parte del índice).

**Decisión confirmada por el autor el 21/09/2026.**
