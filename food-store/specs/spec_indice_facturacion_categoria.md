# Spec — índice para la facturación por categoría (P4-A)

> **Estado:** revisada en Kiro el 21/09/2026. Cambios aplicados a partir del
> análisis de Kiro: se agregó la sección «Resultado de la medición» (pendiente),
> el antecedente pasó a «Estado actual medido» y se corrigió el origen de la
> consulta. Las frecuencias marcadas «a confirmar» siguen siendo supuestos del
> dominio que debe validar el autor.

## Objetivo

Evitar el `Seq Scan` sobre `detalle_pedido` (499.263 filas) en la consulta de
facturación por categoría, o documentar con mediciones que no se puede.

## Consulta

Consulta A de `docs/informe_parte4_consultas.md`; en `food-store/queries.sql`
figura en la sección «TP4 — Parte 4» (versión aceptada, LEFT JOIN + GROUP BY):

```sql
SELECT
    c.nombre AS nombre_categoria,
    COUNT(dp.id_detalle) AS cantidad_lineas_venta,
    COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS monto_total_facturado
FROM categoria c
LEFT JOIN producto p ON p.id_categoria = c.id_categoria AND p.activo = TRUE
LEFT JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE c.activo = TRUE
GROUP BY c.id_categoria, c.nombre
ORDER BY monto_total_facturado DESC;
```

## Frecuencia y carga

Reporte gerencial de facturación por categoría. Se consulta a demanda, del
orden de varias veces por día (a confirmar). Devuelve 4 filas pero agrega el
100 % de las líneas de venta de productos activos.

## Columnas relevantes

- Filtro: `categoria.activo`, `producto.activo` (condición del `LEFT JOIN`).
- Join: `producto.id_categoria = categoria.id_categoria` y
  `detalle_pedido.id_producto = producto.id_producto`.
- Agregación: `detalle_pedido.id_detalle`, `cantidad`, `precio_unitario`.
- Orden: sobre el resultado agregado (4 filas), no sobre la tabla grande.

## Estado actual medido

Base `bd2_tp3` (499.263 detalles), índices del TP1. Plan: `Seq Scan` en
`detalle_pedido` y en `producto`, `Hash Right Join`, `HashAggregate`.
Mediana de 5 corridas: **727 ms** (`food-store/informe_mediciones.md`, sección 3).

**Medición previa (exploratoria, sin spec).** Un índice cubriente sobre
`detalle_pedido (id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)`
(24 MB) no cambió el plan ni el tiempo. Se pide evaluar esta consulta de nuevo
con el flujo completo; no se da por descartada.

## Hipótesis para OpenCode

Proponer el índice (tipo, columnas, orden, `INCLUDE`, condición parcial) que
permita reemplazar el `Seq Scan` de `detalle_pedido`, o indicar que ningún
índice lo justifica y por qué. **No crear nada sin justificar** qué nodo del
plan elimina y cuánto pesa el índice frente a los 33 MB de la tabla. Una
propuesta redundante con `idx_detalle_pedido_id_producto` o con
`UNIQUE (id_pedido, id_producto)` se debe marcar como tal.

## Criterio de aceptación

Se acepta solo si, con `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` antes y después:

1. `detalle_pedido` deja de leerse con `Seq Scan`, y
2. la mediana de 5 corridas baja al menos un 30 %, y
3. el costo de escritura (500 `INSERT` en `detalle_pedido`, tiempo y WAL,
   `food-store/medicion_escritura.sql`) queda justificado por la mejora.

Si no se cumple alguna de las condiciones 1 a 3, se descarta y se documenta el
motivo.

## Resultado de la medición

**Descartado (21/09/2026).** Decisión confirmada por el autor a partir de la medición y de las propuestas de OpenCode (sesiones 1 y 2 del informe, sección 6.1: ningún índice se justifica).

Se midió el índice cubriente que esta consulta necesita, `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)` (incluye `id_detalle` por el `COUNT(dp.id_detalle)`):

- El planificador lo ignora: sigue con `Seq Scan` en `detalle_pedido`. Mediana de 5, misma corrida: **743 ms sin índice, 735 ms con él** (−1 %).
- Pesa **24 MB** frente a los 33 MB de la tabla (73 %).
- Costo de escritura, 500 `INSERT` en `detalle_pedido`: **+21,4 % de WAL** (251.432 contra 207.088 bytes).

No cumple la condición 1 (el `Seq Scan` no desaparece) ni la 2 (la mejora es del 1 %, no del 30 %); el costo de escritura no tiene contrapartida.

**Corrección a la «Medición previa».** El índice de esa prueba, con `INCLUDE (id_pedido, cantidad, precio_unitario)`, no contenía `id_detalle`, así que no podía dar un `Index Only Scan` para esta consulta. Se rehízo con el índice correcto y la conclusión se mantiene. Detalle en `food-store/informe_mediciones.md`, sección 6.2.
