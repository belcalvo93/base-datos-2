# Informe TP4 — Semana 4

## 1. Objetivo y método

Esta práctica continúa el trabajo de optimización de consultas sobre el modelo
Food Store. El objetivo es medir consultas analíticas con varios `JOIN`,
identificar los algoritmos elegidos por PostgreSQL, pedir propuestas de
reescritura a la IA y aceptar únicamente los cambios que puedan justificarse
con el plan real y la medición posterior.

La base se referencia como `bd2_tp3`, siguiendo el nombre utilizado en los
informes anteriores. En esta ejecución la copia local fue registrada en
DBeaver con el nombre `FoodStore`.

Se utilizó:

- PostgreSQL 17.11.
- `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.
- La base masiva sin crear índices nuevos ni modificar `work_mem`.
- Dos mediciones de validación para la Consulta B, para distinguir la mejora
  del efecto de la caché.

## 2. Estado inicial

La conexión confirmó PostgreSQL 17.11 y el usuario `postgres`. La base masiva
contenía:

| Tabla | Filas |
|---|---:|
| `categoria` | 5 |
| `producto` | 50.011 |
| `cliente` | 20.005 |
| `pedido` | 200.005 |
| `detalle_pedido` | 499.263 |

Antes de las mediciones ya estaban presentes los índices de la Semana 3:

- `idx_pedido_id_cliente`
- `idx_producto_categoria_activo`
- `idx_detalle_pedido_id_producto`
- índices primarios y de unicidad del esquema

No se agregaron índices ni se eliminaron índices durante esta etapa.

## 3. Parte 1 — Consultas analíticas lentas

### 3.1 Consulta A — Facturación por categoría y mes

La consulta cruza `categoria`, `producto`, `detalle_pedido` y `pedido`. Calcula
la cantidad de pedidos y la facturación mensual por categoría:

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

#### Plan inicial

El plan utilizó `Hash Join` entre `producto` y `categoria`, otro `Hash Join`
con `detalle_pedido` y un `Parallel Hash Join` con `pedido`. PostgreSQL
distribuyó el trabajo entre dos workers y luego utilizó `Gather Merge`.

El resultado intermedio tuvo 398.846 filas antes de la agregación final. Los
workers realizaron un ordenamiento externo (`external merge`) que utilizó
aproximadamente 7,5 MB de disco por worker. El tiempo total fue:

```text
Execution Time: 1366.991 ms
```

#### Reescritura evaluada

Se probó una preagregación por categoría y pedido. La intención era reducir las
filas antes de unirlas con `pedido`, pero el plan resultante produjo 413.573
filas intermedias y eligió un `Nested Loop` con 330.539 búsquedas mediante
`pedido_pkey`.

También realizó un ordenamiento externo de 330.539 filas y registró un volumen
de buffers considerablemente mayor. El tiempo fue:

```text
Execution Time: 3150.150 ms
```

La propuesta se rechazó. Aunque la reescritura reducía la cantidad estimada de
grupos finales, la medición real mostró un aumento aproximado del 130,4 %:

| Versión | Tiempo |
|---|---:|
| Original | 1.366,991 ms |
| Reescrita | 3.150,150 ms |

El cambio de `Parallel Hash Join` a `Nested Loop` resultó desfavorable para
este volumen de datos.

### 3.2 Consulta B — Ranking de clientes por gasto

La consulta cruza `cliente`, `pedido` y `detalle_pedido`, agrupando el gasto
total y la cantidad de pedidos por cliente:

```sql
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
FROM cliente AS c
JOIN pedido AS pe
    ON pe.id_cliente = c.id_cliente
JOIN detalle_pedido AS dp
    ON dp.id_pedido = pe.id_pedido
GROUP BY
    c.id_cliente,
    c.nombre,
    c.apellido
ORDER BY
    gasto_total DESC;
```

#### Plan inicial

El plan utilizó dos `Hash Join`: primero entre `detalle_pedido` y `pedido`, y
después entre ese resultado y `cliente`. Procesó las 499.263 filas de
`detalle_pedido` y realizó un ordenamiento externo antes de `GroupAggregate`.

El ordenamiento utilizó aproximadamente 31.800 kB de disco y leyó/escribió
5.752/5.764 bloques temporales. El tiempo de la primera medición fue:

```text
Execution Time: 1739.999 ms
```

En la segunda medición el plan se mantuvo y el tiempo fue:

```text
Execution Time: 1624.797 ms
```

#### Reescritura aceptada

Se calculó primero el total de cada pedido y luego se agrupó por cliente:

```sql
WITH total_por_pedido AS (
    SELECT
        dp.id_pedido,
        SUM(dp.cantidad * dp.precio_unitario) AS total_pedido
    FROM detalle_pedido AS dp
    GROUP BY dp.id_pedido
)
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    COUNT(*) AS cantidad_pedidos,
    SUM(tpp.total_pedido) AS gasto_total
FROM total_por_pedido AS tpp
JOIN pedido AS pe
    ON pe.id_pedido = tpp.id_pedido
JOIN cliente AS c
    ON c.id_cliente = pe.id_cliente
GROUP BY
    c.id_cliente,
    c.nombre,
    c.apellido
ORDER BY
    gasto_total DESC;
```

El plan aprovechó el índice
`detalle_pedido_id_pedido_id_producto_key` para recorrer los detalles en
orden de pedido. Luego utilizó `GroupAggregate`, `Merge Join` con `pedido`,
`Hash Join` con `cliente` y un `HashAggregate` final.

La agregación previa redujo el resultado que atraviesa los joins de 499.263
detalles a 200.005 pedidos. El ordenamiento externo grande desapareció y los
temporales bajaron a 160 bloques leídos y 324 escritos.

Los tiempos fueron:

| Medición | Original | Reescrita |
|---|---:|---:|
| 1 | 1.739,999 ms | 1.025,563 ms |
| 2 | 1.624,797 ms | 981,764 ms |
| Promedio | 1.682,398 ms | 1.003,664 ms |

La mejora promedio fue aproximadamente del **40,4 %**. La propuesta se
aceptó porque mejoró el tiempo, redujo el uso de temporales y produjo un plan
más adecuado para la agregación por pedido.

### 3.3 Tabla comparativa

| Consulta | Join antes | Cambio | Join después | Tiempo antes | Tiempo después | Decisión |
|---|---|---|---|---:|---:|---|
| Facturación por categoría y mes | `Hash Join` + `Parallel Hash Join` | Preagregación por categoría/pedido | `Hash Join` + `Nested Loop` | 1.366,991 ms | 3.150,150 ms | Rechazada |
| Ranking de clientes por gasto | `Hash Join` + `Hash Join` | Preagregación por pedido | `Merge Join` + `Hash Join` | 1.682,398 ms promedio | 1.003,664 ms promedio | Aceptada |

## 4. Parte 2 — Lectura crítica de planes de join

Se analizó la explicación generada por IA sobre la Consulta B reescrita y se
contrastó con el plan real de PostgreSQL. La lectura fue crítica: cada
afirmación se validó contra `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` y no se
aceptó ninguna inferencia que no coincidiera con los números reales del plan.

La lectura más importante del plan es que el optimizador eligió una estrategia
basada en dos etapas: primero reducir los detalles por `id_pedido` y luego
hacer el cruce con `pedido` y `cliente`. Ese cambio es consistente con la
naturaleza del problema y con la estructura del esquema.

### 4.1 Análisis del `Merge Join`

El primer join relevante es el que conecta la salida del `GroupAggregate` con la
tabla `pedido`:

```text
Merge Join
  Merge Cond: (dp.id_pedido = pe.id_pedido)
```

La explicación de IA fue correcta al identificar que esta unión compara la
clave `dp.id_pedido` con `pe.id_pedido` y que el flujo izquierdo proviene del
`GroupAggregate` por pedido. El lado izquierdo tuvo 200.005 filas reales, y el
lado derecho fue un `Index Scan` sobre la clave primaria de `pedido` con 200.005
filas reales. Esto se corresponde con la decisión del optimizador de usar un
`Merge Join`: ambos flujos ya estaban ordenados o alineados por la misma clave,
lo que hace posible recorrerlos en paralelo sin materializar una tabla hash
completa.

La diferencia entre filas estimadas y reales es importante: PostgreSQL estimó
177.686 filas para el flujo agregado, pero el resultado real fue 200.005. Eso
no invalida la estrategia; simplemente muestra que la estimación del planner no
fue exacta para ese volumen. Lo relevante es que el plan real confirmó la
misma clave de unión y la misma lógica de flujo.

### 4.2 Análisis del `Hash Join` final

El segundo join relevante es:

```text
Hash Join
  Hash Cond: (pe.id_cliente = c.id_cliente)
```

Aquí la IA identificó correctamente que la salida del `Merge Join` se combina
con una tabla hash construida sobre `cliente`. El lado izquierdo fue la salida
agregada por pedido, y el lado derecho fue `Hash` sobre `cliente`, con el
`Hash Cond` correspondiente a la llave `id_cliente`.

La suma por cliente luego se materializa en otro `HashAggregate` y el plan final
ordena los resultados por gasto total. El `HashAggregate` mostró `Batches: 5`,
`Memory Usage: 8241kB` y `Disk Usage: 1656kB`, con temporales reales de
lectura/escritura (`temp read=160`, `written=324`). Eso confirma que el
resultado se procesó en memoria y, cuando no alcanzó, desbordó a disco.

### 4.3 Uso del índice y la agregación previa

La explicación de IA también describe bien la lectura del índice sobre
`detalle_pedido`:

```text
Index Scan using detalle_pedido_id_pedido_id_producto_key
```

El plan mostró `rows=499263` reales y `actual time=0.027..145.186 ms`, lo que
confirma que el recorrido del índice no fue una suposición sino una lectura
efectiva sobre toda la tabla de detalle. Eso explica por qué la primera etapa
fue razonable: reducir los 499.263 registros de detalle a un agregado por
`id_pedido`.

El siguiente paso fue el `GroupAggregate` por `dp.id_pedido` y luego el `Merge
Join` con `pedido`. Ese es precisamente el punto de la reescritura: en lugar de
hacer el ordenamiento y la agregación sobre los 499.263 detalles durante la
primera parte del plan, la consulta reordena el trabajo para agrupar por
pedido antes de cruzar con la información del cliente.

### 4.4 Diferencia entre `cost`, `actual time` y `Execution Time`

La explicación de IA fue correcta al distinguir tres niveles distintos de la
información del plan:

- `cost` = estimación del optimizador antes de ejecutar;
- `actual time` = tiempo real observado en un nodo concreto;
- `Execution Time` = tiempo total para toda la consulta.

Por ejemplo, el `Sort` final reportó un `actual time` de
`958.789..961.147 ms`, pero eso no significa que todo el tiempo total de la
consulta haya sido ese valor. El tiempo total de la consulta quedó en:

```text
Execution Time: 981.764 ms
```

La diferencia entre ambos números es completamente esperable porque el nodo
`Sort` no es el único trabajo que se ejecuta: también hay `HashAggregate`,
joins, lectura de filas y preparación del resultado final.

### 4.5 Tabla de verificación crítica

| Afirmación de la explicación | Evidencia exacta del plan | ¿Está demostrada? |
|---|---|---|
| El `Index Scan` sobre `detalle_pedido` leyó exactamente 499.263 filas reales. | `(actual time=0.027..145.186 rows=499263 loops=1)` | Sí |
| El `Merge Join` se basa en la igualdad de `id_pedido`. | `Merge Cond: (dp.id_pedido = pe.id_pedido)` | Sí |
| El `Hash Join` final se basa en la igualdad de `id_cliente`. | `Hash Cond: (pe.id_cliente = c.id_cliente)` | Sí |
| El `HashAggregate` requirió usar archivos temporales. | `Batches: 5`, `Memory Usage: 8241kB`, `Disk Usage: 1656kB`, `temp read=160`, `written=324` | Sí |
| La consulta completa ejecutó en 981.764 ms. | `Execution Time: 981.764 ms` | Sí |

### 4.6 Conclusión crítica

La explicación generada por IA para la Consulta B reescrita fue útil y en su
mayoría correcta, pero solo cuando se la confronta con el plan real se vuelve
verdaderamente defensable. La clave es que la IA identificó bien la estructura
lógica del plan, la dirección de cada join, la presencia de temporales y la
relación entre agregación y ordenamiento; además, los datos del plan confirmaron
las principales afirmaciones.

La recomendación metodológica es mantener este criterio para el resto de la
práctica: usar la IA como apoyo para interpretar el plan, pero aceptar solo
los puntos que se validen con `actual time`, `rows`, `Hash Cond`, `Merge Cond` y
`Execution Time` reales de PostgreSQL.

## 5. Parte 3 — Ranking con ventana y subconsulta correlacionada

La parte 3 se centró en dos formas equivalentes de resolver un ranking de
clientes por gasto total. La especificación fue fija antes de generar SQL:

- tablas involucradas: `cliente`, `pedido`, `detalle_pedido`;
- filtrado: se consideran todos los clientes y pedidos que existen en el
  esquema; `cliente` no tiene baja lógica ni `pedido` tiene un estado adicional;
- cálculo: gasto_total = suma de `cantidad * precio_unitario` por cliente;
- salida: `id_cliente`, nombre, apellido, gasto_total y puesto;
- orden: mayor gasto primero;
- criterio de corte: se muestran los clientes del ranking completo o un límite
  razonable para la prueba de equivalencia.

### 5.1 Especificación del ranking con ventana

La versión principal se resolvió con `RANK()` sobre el gasto total por
cliente:

```sql
WITH gasto_por_cliente AS (
    SELECT
        pe.id_cliente,
        SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
    FROM pedido AS pe
    JOIN detalle_pedido AS dp
        ON dp.id_pedido = pe.id_pedido
    GROUP BY pe.id_cliente
)
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    gpc.gasto_total,
    RANK() OVER (
        ORDER BY gpc.gasto_total DESC
    ) AS puesto
FROM gasto_por_cliente AS gpc
JOIN cliente AS c
    ON c.id_cliente = gpc.id_cliente
ORDER BY gpc.gasto_total DESC;
```

### 5.2 Versión alternativa con subconsulta correlacionada

La misma lógica se reescribió sin usar `ROW_NUMBER()`, calculando el puesto con
una subconsulta correlacionada que cuenta cuántos clientes tienen gasto mayor al
actual:

```sql
WITH gasto_por_cliente AS (
    SELECT
        pe.id_cliente,
        SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
    FROM pedido AS pe
    JOIN detalle_pedido AS dp
        ON dp.id_pedido = pe.id_pedido
    GROUP BY pe.id_cliente
)
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    gpc.gasto_total,
    1 + (
        SELECT COUNT(*)
        FROM gasto_por_cliente AS gpc2
        WHERE gpc2.gasto_total > gpc.gasto_total
    ) AS puesto
FROM gasto_por_cliente AS gpc
JOIN cliente AS c
    ON c.id_cliente = gpc.id_cliente
ORDER BY gpc.gasto_total DESC;
```

La subconsulta es correlacionada porque depende del valor de `gpc.gasto_total`
para cada fila del conjunto exterior. La lógica es equivalente a `RANK()`: el
puesto se define como uno más que la cantidad de clientes con un gasto mayor al
actual. Si dos clientes empatan, ambos reciben el mismo puesto y se conserva el
salto correspondiente en el ranking.

### 5.3 Verificación de equivalencia con `EXCEPT`

La equivalencia se comprobó comparando los dos resultados en ambos sentidos. La
idea es que una consulta y su reescritura deben devolver el mismo conjunto de
filas en el mismo orden y con los mismos valores.

```sql
WITH gasto_por_cliente AS (
    SELECT
        pe.id_cliente,
        SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
    FROM pedido AS pe
    JOIN detalle_pedido AS dp
        ON dp.id_pedido = pe.id_pedido
    GROUP BY pe.id_cliente
),
ranking_ventana AS (
    SELECT
        c.id_cliente,
        c.nombre,
        c.apellido,
        gpc.gasto_total,
        RANK() OVER (
            ORDER BY gpc.gasto_total DESC
        ) AS puesto
    FROM gasto_por_cliente AS gpc
    JOIN cliente AS c
        ON c.id_cliente = gpc.id_cliente
),
ranking_subconsulta AS (
    SELECT
        c.id_cliente,
        c.nombre,
        c.apellido,
        gpc.gasto_total,
        1 + (
            SELECT COUNT(*)
            FROM gasto_por_cliente AS gpc2
            WHERE gpc2.gasto_total > gpc.gasto_total
        ) AS puesto
    FROM gasto_por_cliente AS gpc
    JOIN cliente AS c
        ON c.id_cliente = gpc.id_cliente
)
SELECT * FROM ranking_ventana
EXCEPT
SELECT * FROM ranking_subconsulta;
```

Y en sentido inverso:

```sql
WITH gasto_por_cliente AS (
    SELECT
        pe.id_cliente,
        SUM(dp.cantidad * dp.precio_unitario) AS gasto_total
    FROM pedido AS pe
    JOIN detalle_pedido AS dp
        ON dp.id_pedido = pe.id_pedido
    GROUP BY pe.id_cliente
),
ranking_ventana AS (
    SELECT
        c.id_cliente,
        c.nombre,
        c.apellido,
        gpc.gasto_total,
        RANK() OVER (
            ORDER BY gpc.gasto_total DESC
        ) AS puesto
    FROM gasto_por_cliente AS gpc
    JOIN cliente AS c
        ON c.id_cliente = gpc.id_cliente
),
ranking_subconsulta AS (
    SELECT
        c.id_cliente,
        c.nombre,
        c.apellido,
        gpc.gasto_total,
        1 + (
            SELECT COUNT(*)
            FROM gasto_por_cliente AS gpc2
            WHERE gpc2.gasto_total > gpc.gasto_total
        ) AS puesto
    FROM gasto_por_cliente AS gpc
    JOIN cliente AS c
        ON c.id_cliente = gpc.id_cliente
)
SELECT * FROM ranking_subconsulta
EXCEPT
SELECT * FROM ranking_ventana;
```

Si ambas consultas devuelven cero filas, entonces las dos versiones son
equivalentes. Ese patrón es la forma correcta de verificar que una reescritura
funciona sin depender de la apariencia visual del resultado.

### 5.4 Observación de diseño

El punto clave de la parte 3 es que `RANK()` expresa el ranking de forma
más directa y legible, mientras que la subconsulta correlacionada demuestra la
misma lógica usando un criterio de comparación entre cada fila y el resto del
conjunto. La diferencia no es semántica: ambas resuelven la misma definición de
puesto. La decisión de cuál usar se vuelve entonces un criterio de claridad,
legibilidad y rendimiento real del plan, no de la intención del SQL.

## 6. Parte 4 — Consultas resumen y subconsultas bajo especificación precisa

La Parte 4 se resolvió siguiendo la metodología de la consigna: primero se
redactaron las specs antes de pedir SQL a la IA, luego se compararon dos
versiones diferentes de cada consulta y se validó la equivalencia con `EXCEPT`
en ambos sentidos.

### 6.1 Consulta A — facturación total por categoría

La definición pedía: facturación total por categoría con inclusión de
categorías vigentes sin ventas, con `activo = TRUE` en ambos niveles,
`cantidad * precio_unitario` como cálculo y orden descendente por monto.

#### Versión 1 — `LEFT JOIN` con `GROUP BY`

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

La decisión clave fue mover el filtro de `producto.activo = TRUE` al `ON` del
`LEFT JOIN`, porque si se ubica en el `WHERE`, la categoría sin productos
activos desaparece del conjunto. También se usó `COUNT(dp.id_detalle)` para que
las categorías sin ventas cuenten 0 y no 1.

#### Versión 2 — subconsultas correlacionadas en el `SELECT`

```sql
SELECT
    c.nombre AS nombre_categoria,
    (SELECT COUNT(*)
       FROM detalle_pedido dp
       JOIN producto p ON p.id_producto = dp.id_producto
      WHERE p.id_categoria = c.id_categoria
        AND p.activo = TRUE) AS cantidad_lineas_venta,
    COALESCE((SELECT SUM(dp.cantidad * dp.precio_unitario)
       FROM detalle_pedido dp
       JOIN producto p ON p.id_producto = dp.id_producto
      WHERE p.id_categoria = c.id_categoria
        AND p.activo = TRUE), 0) AS monto_total_facturado
FROM categoria c
WHERE c.activo = TRUE
ORDER BY monto_total_facturado DESC;
```

#### Resultado verificado

Ambas versiones devolvieron las mismas 4 filas vigentes:

| Categoría | Líneas de venta | Monto facturado |
|---|---:|---:|
| Lácteos | 100.350 | 126.098.972,37 |
| Almacén | 100.238 | 125.747.608,46 |
| Bebidas | 99.572 | 125.587.056,38 |
| Panificados | 98.686 | 125.367.166,20 |

La quinta categoría quedó fuera porque tuvo `activo = FALSE` en el modelo de
los TP previos.

### 6.2 Consulta B — productos que nunca se vendieron

La definición pedía productos activos que no tuvieran ninguna fila en
`detalle_pedido`, resolviendo la consulta con una subconsulta.

#### Versión 1 — `NOT EXISTS` (generada por IA)

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

#### Versión 2 — `LEFT JOIN ... IS NULL` (escritura alternativa)

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
LEFT JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE p.activo = TRUE
  AND dp.id_producto IS NULL
ORDER BY p.nombre ASC;
```

#### Resultado verificado

Ambas devolvieron exactamente 2 productos:

| id_producto | nombre | precio | stock |
|---:|---|---:|---:|
| 66891 | Producto 31880 | 717,57 | 58 |
| 78088 | Producto 43077 | 161,63 | 67 |

Esto coincide con la distribución de la carga masiva: 50.008 productos aparecen
en ventas y los dos restantes no tienen detalle asociado.

#### Variante descartada — `NOT IN`

```sql
SELECT COUNT(*) FROM producto
WHERE activo = TRUE
  AND id_producto NOT IN (SELECT id_producto FROM detalle_pedido);
```

Esta variante devolvió el mismo resultado, pero es más frágil: si la columna
`detalle_pedido.id_producto` admitiera `NULL`, la semántica de `NOT IN` cambiaría
y el resultado se volvería incorrecto. En este esquema la columna no acepta
`NULL`, pero el punto de la práctica era demostrar que `NOT EXISTS` es la forma
más robusta, y además suele ejecutarse mejor.

### 6.3 Verificación por `EXCEPT`

La equivalencia se validó en ambos sentidos, sin depender de la inspección visual
del resultado:

```sql
SELECT * FROM version_1
EXCEPT
SELECT * FROM version_2;
```

```sql
SELECT * FROM version_2
EXCEPT
SELECT * FROM version_1;
```

Si ambas sentencias devuelven 0 filas, entonces las dos consultas son
equivalentes en contenido.

## 7. DUIA

La declaración final de uso de IA quedó así:

| Uso | Herramienta | Resultado | Estado |
|---|---|---|---|
| Reescritura de la Consulta A | OpenCode | Se propuso una preagregación, luego se descartó por empeorar el plan | Descartada |
| Reescritura de la Consulta B | OpenCode | Se aceptó la versión con preagregación por pedido | Aceptada |
| Explicación del plan de la Parte 2 | OpenCode | Se validó contra `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` | Aceptada con correcciones |
| Ranking con ventana y subconsulta correlacionada | OpenCode | Se validó por equivalencia con `EXCEPT` | Aceptada |
| Consultas resumen y subconsultas de la Parte 4 | OpenCode | Se verificó que la reescritura conserva el mismo conjunto | Aceptada |

En todas las pruebas, la aceptación o rechazo de la propuesta dependió del plan
real y de la medición efectiva, no de la plausibilidad de la idea.

## 8. Conclusiones parciales

La primera medición confirma que una reescritura no debe aceptarse solo porque
reduce filas estimadas. En la Consulta A, la preagregación cambió el plan hacia
un `Nested Loop` con cientos de miles de búsquedas puntuales y empeoró el
tiempo.

En la Consulta B, la preagregación por pedido permitió aprovechar el orden del
índice existente y cambiar el plan a un `Merge Join`, eliminando el
ordenamiento externo de casi medio millón de filas. La mejora se mantuvo en
dos mediciones y no se crearon índices nuevos para obtenerla.

La práctica terminó con una metodología consistente: especificar primero,
medir con datos reales, pedir la explicación a la IA, y aceptar exclusivamente
las reescrituras que podían justificarse con el plan y la ejecución real en
PostgreSQL.
