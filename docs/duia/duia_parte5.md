# Declaración de Uso de IA (DUIA) — Parte 5

**Ejercicio:** TP5, Parte A — plan de indexado

## Estado

La Parte A fue validada en PostgreSQL sobre `practica_bd2`. La base tenía
50.010 productos, 200.005 pedidos y 500.151 detalles. No se aceptó ningún
índice nuevo: la decisión se tomó a partir de planes, tiempos, buffers y
costo de escritura reales.

## Specs preparadas

- `food-store/specs/spec_indice_productos_categoria_precio.md`
- `food-store/specs/spec_indice_pedidos_cliente_fecha.md`
- `food-store/specs/spec_indice_detalle_producto_pedido.md`

## Interacción y validación

Las specs se usaron para proponer tres índices candidatos. Cada sentencia se
leyó antes de ejecutarla y se probó dentro de una transacción con `ROLLBACK`.
La verificación se hizo con:

```text
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
```

Resultados:

- C1: `(id_categoria, precio DESC) WHERE activo = TRUE`; mantuvo el `Sort` y
  pasó de 8,742 ms a 10,415 ms. Descartado.
- C2: `(id_cliente, fecha DESC)`; mantuvo el plan con
  `idx_pedido_id_cliente` y `Sort`. Además, el lote de escritura pasó de
  28,729 ms a 46,699 ms. Descartado.
- C3: `(id_producto, id_pedido)`; mantuvo el `Sort`, pasó de 0,382 ms a
  0,455 ms y fue redundante frente a los índices existentes. Descartado.

La conclusión fue no modificar `food-store/indices.sql`. La propuesta de C3
se documenta como descarte explícito por redundancia y sobreindexación.
