# Spec — índice para productos nunca vendidos (P4-B)

> **Estado:** revisada en Kiro el 21/09/2026. Cambios aplicados a partir del
> análisis de Kiro: se agregó la sección «Resultado de la medición» (pendiente),
> el antecedente pasó a «Estado actual medido», se corrigió el origen de la
> consulta y se amplió la salida de descarte al caso general. Las frecuencias
> marcadas «a confirmar» siguen siendo supuestos del dominio que debe validar
> el autor.

## Objetivo

Evitar el `Seq Scan` sobre `detalle_pedido` (499.263 filas) en la consulta de
productos activos que nunca se vendieron, o documentar con mediciones que no
se puede.

## Consulta

Consulta B de `docs/informe_parte4_consultas.md`; en `food-store/queries.sql`
figura en la sección «TP4 — Parte 4» (versión aceptada, NOT EXISTS):

```sql
SELECT id_producto, nombre, precio, stock
FROM producto
WHERE activo = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM detalle_pedido
      WHERE id_producto = producto.id_producto
  )
ORDER BY nombre ASC;
```

## Frecuencia y carga

Control periódico del catálogo (productos sin rotación), del orden de una vez
por semana o por mes (a confirmar). Devuelve pocas filas (2 en la base
actual) pero necesita saber, para cada producto activo, si existe alguna venta.

## Columnas relevantes

- Filtro: `producto.activo = TRUE`.
- Anti-join: `detalle_pedido.id_producto = producto.id_producto`
  (`NOT EXISTS`).
- Orden: `producto.nombre` sobre el resultado (pocas filas).

## Estado actual medido

Base `bd2_tp3`, índices del TP1. Plan: `Hash Right Anti Join` con `Seq Scan`
en `detalle_pedido` (499.263) y en `producto`. Mediana de 5 corridas:
**259 ms** (`food-store/informe_mediciones.md`, sección 3).

Ya existe `idx_detalle_pedido_id_producto` sobre `detalle_pedido (id_producto)`,
que en principio permitiría un `Index Only Scan` para este anti-join.

**Medición previa (exploratoria, sin spec).** Forzando `enable_seqscan = off`
en una transacción de prueba, el planificador usa ese índice existente
(`Merge Anti Join` con `Index Only Scan`) y baja de 259 a 133 ms; elige el
`Seq Scan` porque estima costos casi iguales. Se pide evaluar si algún índice
**nuevo** aporta algo más allá de ese índice, o si la respuesta correcta es no
crear ninguno.

## Hipótesis para OpenCode

Proponer, si corresponde, un índice (tipo, columnas, orden, condición parcial)
o justificar que el existente alcanza. Se debe marcar explícitamente si la
propuesta es redundante con `idx_detalle_pedido_id_producto` o con
`UNIQUE (id_pedido, id_producto)`: un índice sobre `id_producto` ya existe y
no se acepta una segunda copia.

## Criterio de aceptación

Se acepta un índice nuevo solo si, con `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`
antes y después:

1. el plan cambia de forma verificable respecto del índice existente, y
2. la mediana de 5 corridas baja al menos un 30 %, y
3. el costo de escritura (500 `INSERT` en `detalle_pedido`) queda justificado.

Si no se cumple alguna de las condiciones 1 a 3, se descarta y se documenta el
motivo. En particular, una propuesta que duplique el índice existente se
descarta como sobreindexación.

## Resultado de la medición

**Descartado (21/09/2026), sin índice nuevo.** Decisión confirmada por el autor. OpenCode (sesión 3 del informe, sección 6.1) propuso no crear ninguno; la medición lo confirma.

- El índice existente `idx_detalle_pedido_id_producto` (4,5 MB frente a 33 MB de tabla) ya permite un `Index Only Scan`; el planificador no lo elige por sus estimaciones de costo (17.586 contra 18.338).
- Mediana de 5: **258 ms** por defecto (`random_page_cost = 4`, `Seq Scan`); **112 ms** forzando `enable_seqscan = off`; **110 ms** con `random_page_cost = 1.1`, donde el planificador elige solo el `Merge Anti Join` con `Index Only Scan`.
- No falta un índice: cualquier índice sobre `id_producto` duplicaría al existente (condición 1: el plan no puede cambiar respecto de él).

`random_page_cost` es un parámetro del servidor y queda fuera de esta parte; se deja como observación en el informe (sección 8).

**Aclaración.** `UNIQUE (id_pedido, id_producto)` empieza por `id_pedido`, así que no sirve para buscar por producto; solo `idx_detalle_pedido_id_producto` cubre `id_producto`. Detalle en `food-store/informe_mediciones.md`, sección 6.3.
