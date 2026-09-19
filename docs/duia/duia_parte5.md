# Declaración de Uso de IA (DUIA) — Parte 5

> La bitácora consolidada del TP5 está en `food-store/duia.md`, que es donde la ubica el
> punto 7 de la consigna. Lo de acá queda como registro; lo nuevo va allá.

**Ejercicio:** TP5 — Partes A y B

## Parte A — plan de indexado

La Parte A fue validada en PostgreSQL sobre `practica_bd2`. La base tenía
50.010 productos, 200.005 pedidos y 500.151 detalles. No se aceptó ningún
índice nuevo: la decisión se tomó a partir de planes, tiempos, buffers y
costo de escritura reales.

Specs utilizadas:

- `food-store/specs/spec_indice_productos_categoria_precio.md`
- `food-store/specs/spec_indice_pedidos_cliente_fecha.md`
- `food-store/specs/spec_indice_detalle_producto_pedido.md`

Cada candidato se leyó y se probó dentro de una transacción con `ROLLBACK`,
usando `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.

Resultados:

- C1: `(id_categoria, precio DESC) WHERE activo = TRUE`; mantuvo el `Sort` y
  pasó de 8,742 ms a 10,415 ms. Descartado.
- C2: `(id_cliente, fecha DESC)`; mantuvo el plan con
  `idx_pedido_id_cliente` y `Sort`. Además, el lote de escritura pasó de
  28,729 ms a 46,699 ms. Descartado.
- C3: `(id_producto, id_pedido)`; mantuvo el `Sort`, pasó de 0,382 ms a
  0,455 ms y fue redundante frente a los índices existentes. Descartado.

La conclusión fue no agregar índices nuevos a `food-store/indices.sql`.

## Parte B — tabla `usuario` y vista de reportes

La consigna del TP5 pide una vista que oculte la columna `contrasena` de una
tabla de login. El esquema original no tenía ese caso de uso; `cliente` no
maneja autenticación. Según la indicación documentada de la cátedra, se agregó
una tabla `usuario` separada de `cliente`, con `contrasena` hasheada y `rol`
como tipo ENUM.

Se agregó `vista_usuario_reportes`, que excluye explícitamente `contrasena` y
expone solamente usuarios vigentes. Las cuatro vistas existentes sobre las
tablas de negocio se mantienen sin cambios. La spec específica está en
`food-store/specs/spec_usuario.md`.

La decisión se aparta del punto general de no modificar el modelo únicamente
por la indicación explícita de la cátedra para este criterio de seguridad.
