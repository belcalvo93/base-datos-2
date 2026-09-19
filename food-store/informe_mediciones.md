# Informe de mediciones — TP5

Mediciones de las tres partes: el plan de indexado (A), la verificacion de equivalencia de
las vistas (B) y la vista materializada (C).

---

# Parte A — Plan de indexado

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

---

# Parte B — Vistas

El entregable de la Parte B pide dejar documentada la verificacion de equivalencia de cada vista. Por
cada una se ejecuto el `EXCEPT` en las dos direcciones contra la consulta manual equivalente.

Las dos direcciones importan: `vista EXCEPT consulta` detecta filas que la vista devuelve de mas, y
`consulta EXCEPT vista` detecta las que le faltan. Con una sola se puede dar por buena una vista que
pierde filas.

| Vista | Filas | `vista EXCEPT consulta` | `consulta EXCEPT vista` | Equivalente |
|---|---:|---:|---:|---|
| `vista_cliente_completo` | 20.005 | 0 | 0 | Si |
| `vista_pedidos_cliente` | 200.005 | 0 | 0 | Si |
| `vista_productos_vigentes` | 39.963 | 0 | 0 | Si |
| `vista_detalle_pedido_producto` | 499.263 | 0 | 0 | Si |
| `vista_usuario_reportes` | 2 | 0 | 0 | Si |

Las consultas de verificacion de cada vista estan escritas en `specs/spec_vistas.md`, en la seccion
"Criterio de aceptacion" de cada una.

## Sobre los conteos

`vista_productos_vigentes` devuelve 39.963 de 50.010 productos. La diferencia es el filtro de vigencia:
descarta los productos inactivos y tambien los de categorias dadas de baja.

`vista_detalle_pedido_producto` devuelve las 499.263 lineas sin filtrar por vigencia, a proposito.
Reconstruye ventas pasadas: excluir lineas cuyo producto se dio de baja despues de la venta haria que
algunos pedidos aparecieran con menos lineas de las que realmente tuvieron.

## Vista con criterio de seguridad

La consigna pide exponer el usuario sin la columna `contrasena`. El esquema no tenia esa columna, y por
indicacion de la catedra se agrego la tabla `usuario` con `contrasena` y `rol`. Sobre ella,
`vista_usuario_reportes` excluye la contrasena y expone solo usuarios vigentes.

Se cargaron 3 usuarios de prueba (1 ADMIN, 1 USUARIO vigente y 1 con `eliminado = TRUE`, para probar el filtro), con hashes placeholder en `contrasena`, nunca texto plano. La vista devuelve 2 filas. Ademas del `EXCEPT` en las dos direcciones (0 filas), se consulto `information_schema.columns` y `contrasena` no aparece entre las columnas de la vista.

El detalle de la decision esta en `duia.md`, seccion B.2.

---

# Parte C — Vista materializada

Vista materializada sobre el reporte de facturación por categoría y mes (Consulta A de la Semana 4,
`docs/informe_tp4_semana4.md`). Spec: `specs/spec_vista_materializada_parteC.md`. Implementación:
`materializadas.sql`.

**Base de medición:** `practica_bd2`, 200.005 pedidos y 500.151 detalles, `ANALYZE` corrido.
Mediciones con `EXPLAIN (ANALYZE, BUFFERS)`.

| | Consulta sin materializar | Vista materializada |
|---|---|---|
| Tiempo de ejecucion | 870,172 ms | **0,070 ms** |
| Nodo principal del plan | `Parallel Hash Join` (2 workers) + `Sort` `external merge` (8.000 kB a disco) | `Seq Scan` sobre la vista |
| Filas devueltas | 100 (tras 399.184 filas intermedias) | 100 |

La mejora es de ~**12.430x**. El plan pasa de cruzar ~500.000 líneas de `detalle_pedido` y ~200.000
`pedido` con sort externo a disco para devolver 100 filas, a leer las 100 filas ya calculadas. El
`rows=100` de la vista coincide con el `rows=100` del `GroupAggregate` del plan original: se materializo
exactamente el resultado que antes exigía procesar ~400.000 filas.

**Tiempo del `REFRESH`:** `REFRESH MATERIALIZED VIEW CONCURRENTLY` corrió en **0,927 s** (0 filas
actualizadas: no hubo cambios entre el `CREATE` y el `REFRESH`). Es el costo que se paga a cambio: la
vista se lee en 0,070 ms pero refrescarla cuesta ~0,9 s. Conviene porque se lee muchísimas más veces de
las que se refresca.

**`REFRESH CONCURRENTLY`:** corrió sin error, lo que prueba que el índice único
`uq_mv_facturacion_cat_mes` sirve para refrescar sin bloquear las lecturas (el punto de la consigna
4.3.1).

**Frecuencia de refresco propuesta y su justificacion:** diaria (una corrida nocturna). El reporte es
mensual de negocios: ningún responsable toma una decisión al minuto con el monto del mes. Entre
refrescos el usuario ve un snapshot del último `REFRESH`: los pedidos cargados después no aparecen
(desfasaje máximo 24 h). Como ninguna decisión operativa (stock, despacho, atención al cliente)
depende de la facturación mensual exacta, el desfasaje es tolerable y refrescar más seguido sería gasto
puro. Si un día hiciera falta el dato casi en tiempo real, esa consulta se resuelve directo contra
`pedido`/`detalle_pedido`, no contra la vista.

**Equivalencia verificada:** `EXCEPT` en las dos direcciones contra la consulta original. `vista
EXCEPT consulta` → **0 filas**. `consulta EXCEPT vista` → **0 filas**.
