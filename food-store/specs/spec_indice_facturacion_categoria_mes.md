# Spec — índice para la facturación por categoría y mes (S4-A)

> **Estado:** revisada en Kiro el 21/09/2026. Cambios aplicados a partir del
> análisis de Kiro: se agregó la sección «Resultado de la medición» (pendiente),
> el antecedente pasó a «Estado actual medido», el SQL se alineó textualmente
> con `food-store/queries.sql` y se amplió la salida de descarte al caso
> general. Las frecuencias marcadas «a confirmar» siguen siendo supuestos del
> dominio que debe validar el autor.

## Objetivo

Reducir el costo de la consulta analítica de facturación por categoría y mes,
que hoy hace `Seq Scan` sobre `detalle_pedido` (499.263 filas) y `pedido`
(200.005 filas), o documentar con mediciones que ningún índice lo justifica.

## Consulta

Consulta A del TP4 Semana 4 (`docs/informe_tp4_semana4.md`), en
`food-store/queries.sql`, versión original (la reescritura se rechazó):

```sql
SELECT
    c.nombre AS categoria,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria AS c
JOIN producto AS p
    ON p.id_categoria = c.id_categoria
JOIN detalle_pedido AS dp
    ON dp.id_producto = p.id_producto
JOIN pedido AS pe
    ON pe.id_pedido = dp.id_pedido
WHERE c.activo = TRUE
  AND p.activo = TRUE
GROUP BY
    c.id_categoria,
    c.nombre,
    DATE_TRUNC('month', pe.fecha)
ORDER BY
    mes,
    facturacion_total DESC;
```

## Frecuencia y carga

Reporte de cierre mensual, del orden de una vez por mes, con consultas
ocasionales durante el mes (a confirmar). Agrega todo el histórico: no filtra
por fecha, por lo que no hay un subconjunto pequeño que un índice pueda aislar.

## Columnas relevantes

- Filtro: `categoria.activo`, `producto.activo`.
- Join: `producto.id_categoria`, `detalle_pedido.id_producto`,
  `detalle_pedido.id_pedido = pedido.id_pedido`.
- Agrupación: `categoria.id_categoria`, `categoria.nombre`,
  `DATE_TRUNC('month', pedido.fecha)`.
- Agregación: `detalle_pedido.cantidad`, `precio_unitario`, `pedido.id_pedido`
  (`COUNT DISTINCT`).
- Orden: sobre el resultado agregado.

## Estado actual medido

Base `bd2_tp3`, índices del TP1. Plan: `Seq Scan` en `detalle_pedido`,
`producto`, `pedido` y `categoria`; `Hash Join`; ordenamiento externo con
volcado a disco (23 MB). Mediana de 5 corridas: **2.219 ms**
(`food-store/informe_mediciones.md`, sección 3).

**Medición previa (exploratoria, sin spec).** Un índice cubriente sobre
`detalle_pedido (id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)`
no cambió el plan ni el tiempo (2.219 → 2.246 ms). Se pide evaluar esta
consulta de nuevo con el flujo completo.

## Hipótesis para OpenCode

Proponer el índice (tipo, columnas, orden, `INCLUDE`, condición parcial) que
podría reducir el costo de esta consulta, o justificar que ninguno lo logra y
proponer la alternativa correcta (por ejemplo, si el problema es de
agregación y no de acceso, indicar qué objeto lo resolvería). Cada propuesta
debe indicar qué nodo del plan elimina y cuánto pesa el índice.

## Criterio de aceptación

Se acepta un índice solo si, con `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` antes
y después:

1. el plan deja de usar `Seq Scan` en la tabla que el índice cubre, y
2. la mediana de 5 corridas baja al menos un 30 %, y
3. el costo de escritura (500 `INSERT` en `detalle_pedido`) queda justificado.

Si no se cumple alguna de las condiciones 1 a 3, se descarta y se documenta el
motivo. Si ningún índice cumple, se documenta que el `Seq Scan` es la elección
correcta para una consulta que agrega el 100 % de la tabla, y se deriva la
mejora a la vista materializada de la Parte C.

## Resultado de la medición

**Descartado (21/09/2026).** Decisión confirmada por el autor. OpenCode (sesión 4 del informe, sección 6.1) propuso ningún índice y derivar la mejora a una vista materializada; la medición lo confirma.

- El índice `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` contiene todas las columnas que esta consulta usa de `detalle_pedido`. Plan y tiempo no cambian: **2.219 ms → 2.246 ms**; el planificador sigue con `Seq Scan`.
- El costo está en el `Hash Join`, la agregación y el ordenamiento externo (23 MB volcados a disco), no en el acceso a la tabla.

No cumple las condiciones 1 y 2. La mejora corresponde a la vista materializada de la Parte C. Detalle en `food-store/informe_mediciones.md`, sección 6.4.
