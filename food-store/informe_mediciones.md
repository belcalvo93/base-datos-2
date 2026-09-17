# Informe de mediciones — TP5, Parte A

## Estado

La Parte A está en preparación. Las tres specs de Kiro ya fueron redactadas
para C1, C2 y C3. Todavía no se declaran índices aceptados porque faltan las
mediciones ejecutadas sobre PostgreSQL con la base masiva.

## Consultas seleccionadas

| Consulta | Spec | Índice candidato | Estado |
|---|---|---|---|
| C1 — productos por categoría y precio | `spec_indice_productos_categoria_precio.md` | `(id_categoria, precio DESC) WHERE activo = TRUE` | Pendiente de medir |
| C2 — historial de pedidos por cliente | `spec_indice_pedidos_cliente_fecha.md` | `(id_cliente, fecha DESC)` | Pendiente de medir |
| C3 — pedidos donde apareció un producto | `spec_indice_detalle_producto_pedido.md` | evaluar `(id_producto, id_pedido)` frente al índice existente | Pendiente de medir |

## Evidencia que falta completar

Para cada consulta se debe registrar:

1. `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` antes del índice.
2. Creación reversible del índice, respetando backup y transacción.
3. El mismo `EXPLAIN` después del índice.
4. Tipo de scan, presencia de `Sort`, buffers y `Execution Time`.
5. Decisión final: aceptar o descartar.

También falta medir el mismo lote de varios cientos de `INSERT` en
`detalle_pedido` antes y después de los índices aceptados, y documentar una
propuesta descartada explícitamente por sobreindexación.

## Regla de decisión

No se agregará ninguna sentencia a `food-store/indices.sql` hasta contar con
evidencia real de que el cambio mejora el plan o el tiempo sin imponer un costo
de escritura injustificado.
