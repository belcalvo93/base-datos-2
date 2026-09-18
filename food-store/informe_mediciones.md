# Informe de mediciones — TP5, Parte A

## Estado y entorno

La evaluación se ejecutó en PostgreSQL sobre `practica_bd2`, después de la
carga masiva y `ANALYZE`.

Conteos verificados:

| Tabla | Filas |
|---|---:|
| `categoria` | 5 |
| `cliente` | 20.005 |
| `producto` | 50.010 |
| `pedido` | 200.005 |
| `detalle_pedido` | 500.151 |

Parámetros reproducibles: C1 `id_categoria = 10` (10.093 filas), C2
`id_cliente = 10` (9 filas en la ejecución final) y C3 `id_producto = 64074`
(26 filas). Cada candidato se probó dentro de una transacción y se verificó
que no quedara instalado después del `ROLLBACK`.

## Consultas seleccionadas

| Consulta | Spec | Índice candidato | Estado |
|---|---|---|---|
| C1 — productos por categoría y precio | `spec_indice_productos_categoria_precio.md` | `(id_categoria, precio DESC) WHERE activo = TRUE` | Descartado |
| C2 — historial de pedidos por cliente | `spec_indice_pedidos_cliente_fecha.md` | `(id_cliente, fecha DESC)` | Descartado |
| C3 — pedidos donde apareció un producto | `spec_indice_detalle_producto_pedido.md` | `(id_producto, id_pedido)` | Descartado |

## Resultados antes/después

| Consulta | Baseline | Con candidato | Plan observado | Decisión |
|---|---:|---:|---|---|
| C1 | 8,742 ms | 10,415 ms | Siguió `Bitmap Index Scan` sobre `idx_producto_categoria_activo` y `Sort` | Descartar |
| C2 | 0,274 ms | 0,176 ms | Siguió `Bitmap Index Scan` sobre `idx_pedido_id_cliente` y `Sort`; mismos buffers | Descartar |
| C3 | 0,382 ms | 0,455 ms | Usó el candidato, pero mantuvo `Sort`; era redundante | Descartar |

La diferencia de C2 no se considera una mejora concluyente: el plan, el tipo
de scan y los buffers fueron equivalentes, y el índice existente ya resolvía
el filtro.

## Costo de escritura

Se midió el mismo lote de 300 pedidos y 300 detalles con `ROLLBACK` al final.

| Estado | Filas | Buffers | Execution Time |
|---|---:|---|---:|
| Índices originales | 300 | hit=3658, read=1, dirtied=10, written=2 | 28,729 ms |
| Con `idx_pedido_cliente_fecha` | 300 | hit=4558, read=6, dirtied=16, written=4 | 46,699 ms |

El candidato de C2 incrementó el tiempo de escritura aproximadamente 62,5 %.
Los lotes no dejaron filas persistentes.

## Decisión final

No se agrega ninguna sentencia a `food-store/indices.sql`. Los índices
existentes cubren suficientemente las consultas evaluadas; los candidatos no
eliminaron el `Sort`, no fueron elegidos por el planificador o agregaron costo
de escritura. C3 se descarta además por redundancia frente a
`idx_detalle_pedido_id_producto` y la restricción única
`(id_pedido, id_producto)`.
