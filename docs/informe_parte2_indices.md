# Parte 2 — Índices: laboratorio de consultas lentas, EXPLAIN ANALYZE y optimización medida

## 1. Objetivo y método

El objetivo es medir el impacto real de los índices del TP1 sobre tres consultas del modelo, y evaluar críticamente una alternativa propuesta por IA.

**Base de datos:** `bd2_tp3`, PostgreSQL 17.11, 50.011 productos, 20.005 clientes, 200.005 pedidos, 499.263 detalles. `ANALYZE` corrido. Medición desde psql en Git Bash.

**Problema del "antes":** el esquema del TP1 ya traía tres índices. Para tener un punto de partida real sin ellos, se borraron con `DROP INDEX`, se ejecutaron las consultas (medición "sin índice"), y después se recrearon idénticos y se volvieron a medir (medición "con índice"). Los planes completos de ambas corridas están en:

- `docs/planes_parte2_antes.txt` (sin índices)
- `docs/planes_parte2_despues.txt` (con los índices del TP1)

**Dos corridas y variación por caché:** hubo dos mediciones independientes. La primera fue en frío (datos no en caché del motor); la segunda, con datos ya cacheados. La variación entre corridas idénticas por efecto del caché ronda el 10-20 % en las consultas rápidas, siendo proporcionalmente menor en las consultas lentas. Para la tabla comparativa (sección 3) se usan los números de la segunda corrida, que son la fuente que el documento referencia.

**Rol de la IA:** se cumplió el paso 3 de la consigna 2.1: los planes reales de las tres consultas (antes y después) se pasaron a OpenCode, que analizó los nodos de cada plan y propuso tres índices compuestos con justificación en términos del plan (qué nodo eliminaba o reducía). Se cumplió también el paso 4: cada `CREATE INDEX` propuesto se leyó y se entendió antes de aplicarse, de ahí que la predicción sobre el Sort se pudiera contrastar contra el plan real en lugar de darla por buena. Las propuestas se evaluaron midiendo en la base real, no se aplicaron a ciegas.

## 2. Las tres consultas

| Consulta | Descripción | Filtro | Selectividad | Índice del TP1 |
|----------|-------------|--------|:------------:|----------------|
| C1 | Productos vigentes de la categoría 5 | `id_categoria = 5 AND activo = TRUE` | 10.047 / 50.011 (20 %) | `idx_producto_categoria_activo` |
| C2 | Historial de pedidos del cliente 20155 | `id_cliente = 20155` | 24 / 200.005 (0,012 %) | `idx_pedido_id_cliente` |
| C3 | Pedidos donde se vendió el producto 49112 | `id_producto = 49112` | 27 / 499.263 (0,005 %) | `idx_detalle_pedido_id_producto` |

Cada consulta fue diseñada para atacar uno de los tres índices. C1 opera sobre la tabla más pequeña pero con la selectividad más baja de las tres; C2 y C3 sobre tablas grandes con selectividad extrema.

### Consultas

**C1 — productos vigentes de la categoría 5:**

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.id_categoria = 5 AND p.activo = TRUE
ORDER BY p.precio DESC;
```

**C2 — historial de pedidos del cliente 20155:**

```sql
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.id_cliente = 20155
ORDER BY p.fecha DESC;
```

**C3 — pedidos donde se vendió el producto 49112:**

```sql
SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE dp.id_producto = 49112
ORDER BY ped.fecha DESC;
```

## 3. Tabla 2.2 — Comparativa antes/después

Los planes completos están en los archivos referenciados en la sección 1. A continuación se resume cada consulta con los nodos relevantes, el cost estimado y el Execution Time medido.

| | Consulta | Plan sin índice | Índice aplicado | Plan con índice | Mejora (tiempo) |
|---|----------|----------------|-----------------|-----------------|:---------------:|
| C1 | Productos categoría 5 | `Seq Scan on producto` cost 0.00..1141.14, **7,630 ms** | `idx_producto_categoria_activo` | `Bitmap Heap Scan` (118.19..759.84) + `Bitmap Index Scan` en el índice (0.00..115.68), Heap Blocks exact=516, **8,816 ms** | ≈ 0 % (dentro del ruido) |
| C2 | Pedidos del cliente 20155 | `Parallel Seq Scan` (1 worker) en pedido → `Gather Merge` → `Sort` → `Nested Loop` con `Materialize`, cost 3942.00..3951.29, **39,008 ms** | `idx_pedido_id_cliente` | `Index Scan` en `cliente_pkey` → `Bitmap Heap Scan` en pedido (4.37..42.02) con `Bitmap Index Scan` en el índice (0.00..4.37), Heap Blocks exact=23, **0,147 ms** | **−99,6 %** |
| C3 | Ventas del producto 49112 | `Parallel Seq Scan` (2 workers) en detalle_pedido → `Gather Merge` → `Sort` → `Nested Loop` con `Index Scan` en `pedido_pkey`, cost 7803.60..7804.76, **43,847 ms** | `idx_detalle_pedido_id_producto` | `Bitmap Heap Scan` en detalle_pedido (4.51..46.95) con `Bitmap Index Scan` en el índice (0.00..4.50), Heap Blocks exact=27 → `Index Scan` en `pedido_pkey`, **0,407 ms** | **−99,1 %** |

### Tiempos de creación de los índices del TP1

| Índice | Tiempo |
|--------|-------:|
| `idx_producto_categoria_activo` | 35,2 ms |
| `idx_pedido_id_cliente` | 179,7 ms |
| `idx_detalle_pedido_id_producto` | 294,3 ms |
| **Total** | **509 ms** |

## 4. Criterio de aceptación

Cada índice se diseñó para reemplazar un scan secuencial (o paralelo) por un acceso indexado, reduciendo la cantidad de filas leídas de la tabla. El criterio era que el plan mostrara el nodo de escaneo indexado en lugar del Seq Scan, y que el cost estimado bajara de forma proporcional a la selectividad.

**C1:** el Seq Scan rechaza 39.964 filas de 50.011. El índice debería filtrar el 80 % en el nodo del índice, evitando leer filas descartadas de la tabla. El plan confirma esto: el `Bitmap Index Scan` produce las 10.047 filas y el `Bitmap Heap Scan` accede solo a las 516 páginas que las contienen.

**C2:** el Parallel Seq Scan rechaza 99.990 filas por worker de 200.005. El índice debería reducir el scan a las 24 filas del cliente, eliminando el parallelismo, el `Gather Merge` y el `Materialize`. El plan confirma: el nodo raíz pasa de un `Nested Loop` con `Gather Merge` (3942..3951 cost) a un `Sort` trivial (50.60..50.62) sobre un `Nested Loop` de 4.66..50.43 cost.

**C3:** el Parallel Seq Scan rechaza 166.412 filas por worker de 499.263. El índice debería reducir el scan a las 27 líneas del producto, eliminando los workers y el `Gather Merge`. El plan confirma: el `Bitmap Heap Scan` (4.51..46.95) reemplaza al `Parallel Seq Scan` (6761.33), y los workers desaparecen.

## 5. El caso C1 — análisis del resultado

C1 es la consulta donde el índice produce un cambio claro en el plan pero no una mejora medible en el tiempo real (7,630 ms → 8,816 ms). Esta diferencia del 15 % cae dentro de la variación entre corridas idénticas por caché que ya se documentó en la sección 1, por lo que no se puede atribuir al índice ni a su ausencia. La causa de que el tiempo no mejore es verificable en los propios planes:

1. **Baja selectividad:** el filtro `id_categoria = 5 AND activo = TRUE` retiene el 20 % de la tabla. No es lo suficientemente selectivo como para que el acceso indexado tenga ventaja sobre el scan secuencial de la tabla completa (~1141 cost).

2. **El Sort domina el tiempo:** la consulta tiene `ORDER BY p.precio DESC` sobre 10.047 filas. El nodo `Sort` (quicksort, 932 kB) está presente antes y después del índice, y es el que consume la mayor parte del tiempo de ejecución. El índice reduce el cost del scan de la tabla, pero no toca el Sort.

La consigna pide documentar los resultados reales aunque el índice no mejore el tiempo, y explicar por qué. Se documenta en lugar de descartarlo en silencio porque la ausencia de mejora es informativa: demuestra que un índice bien construido puede cambiar el plan sin cambiar el tiempo cuando la selectividad no es lo suficientemente extrema.

## 6. Alternativa evaluada y rechazada

Se le pasaron los tres planes reales a OpenCode y propuso tres índices compuestos, con el argumento de que la segunda columna cubriría el `ORDER BY` (C1, C2) o el `JOIN` (C3), eliminando el nodo `Sort`:

```sql
CREATE INDEX idx_producto_cat_precio_alt ON producto (id_categoria, precio DESC) WHERE activo = TRUE;
CREATE INDEX idx_pedido_cliente_fecha_alt ON pedido (id_cliente, fecha DESC);
CREATE INDEX idx_detalle_producto_pedido_alt ON detalle_pedido (id_producto, id_pedido);
```

Se midieron con los índices del TP1 borrados, para que el optimizador no pudiera elegir entre ambos.

### Comparativa alternativo vs. TP1

> **Nota sobre corridas:** los alternativos se midieron en la misma sesión que la primera corrida del TP1 (en frío). Los tiempos del TP1 en la tabla 2.2 (sección 3) son de la segunda corrida (con caché). Para esta comparación A/B se usan los pares de la primera corrida, porque es la que se midió en las mismas condiciones.

| | Consulta | Índice TP1 (1.ª corrida) | Índice alternativo | Sort eliminado | Cost del nodo de índice |
|---|----------|:------------------------:|:------------------:|:--------------:|:-----------------------:|
| C1 | Productos categoría 5 | 8,450 ms | 8,413 ms | No | 231.68 (vs 115.68) |
| C2 | Pedidos del cliente 20155 | 0,198 ms | 0,159 ms | No | — |
| C3 | Ventas del producto 49112 | 0,285 ms | 0,311 ms | No | — |

### Tiempos de creación

| Índice | Tiempo | Ratio vs. TP1 |
|--------|-------:|:-------------:|
| `idx_producto_cat_precio_alt` | 92,0 ms | 2,6x |
| `idx_pedido_cliente_fecha_alt` | 241,7 ms | 1,3x |
| `idx_detalle_producto_pedido_alt` | 588,2 ms | 2,0x |
| **Total** | **922 ms** | **1,8x** |

### Causa de que la predicción fallara

La predicción de OpenCode era que el nodo `Sort` desaparecería porque la segunda columna del índice cubría el `ORDER BY`. Esto no ocurrió en ninguno de los tres casos. La causa, verificada en los tres planes, es que el optimizador elige `Bitmap Index Scan` en lugar de un `Index Scan` puro. El `Bitmap Index Scan` arma un mapa de páginas del heap y las visita en orden físico — no preserva el orden del índice. Por eso el `Sort` es obligatorio aunque el índice incluya la columna del `ORDER BY`. Para conservar el orden haría falta un `Index Scan` puro, que el optimizador descarta porque, con esa cantidad de filas (10.047 en C1, 24 en C2, 27 en C3), el ida y vuelta entre índice y tabla sale más caro que el bitmap + sort.

En C3 la causa es diferente: el `Bitmap Heap Scan` va igual a la tabla a buscar `cantidad` y `precio_unitario`, que no están en el índice. Tener `id_pedido` en el índice no ahorra ningún acceso adicional.

### Decisión

Se conservan los tres índices del TP1. Los alternativos empatan en tiempo de consulta (diferencias dentro del margen de ruido entre corridas) y cuestan 1,8x construirlos, con el costo de mantenimiento correspondiente en cada `INSERT` sobre las tablas involucradas.

## 7. Conclusiones

1. **Los tres índices del TP1 funcionan.** C2 y C3 reducen el tiempo de ejecución en dos órdenes de magnitud (~200x y ~100x respectivamente). C1 no mejora el tiempo real (baja selectividad + Sort dominante), pero cambia el plan de un `Seq Scan` a un `Bitmap Heap Scan` con cost reducido un 33 %.

2. **Los índices eliminan infraestructura pesada.** Los planes sin índices usan parallel seq scan, `Gather Merge`, `Materialize` y `Sort` sobre filas completas. Con los índices, los planes se reducen a un `Bitmap Heap Scan` + `Bitmap Index Scan`, y en C2 el nodo raíz pasa a ser un `Sort` trivial sobre 24 filas.

3. **Los índices compuestos no aportan mejora medible.** El optimizador elige `Bitmap Index Scan` que no preserva orden del índice, por lo que el `Sort` se mantiene. El costo de construcción es 1,8x mayor y el de mantenimiento es proporcionalmente mayor en cada `INSERT`.

4. **La selectividad es el factor determinante.** C2 (0,012 %) y C3 (0,005 %) muestran mejoras drásticas; C1 (20 %) no mejora en tiempo. Un índice es más efectivo cuanto más selectivo es el filtro que cubre.

5. **Medir es indispensable.** La propuesta de OpenCode era razonable en teoría (el índice "cubría" el `ORDER BY`), pero la implementación real del optimizador (bitmap scan) la invalida. Sin medición, se habrían creado tres índices más grandes y más costosos sin beneficio.
