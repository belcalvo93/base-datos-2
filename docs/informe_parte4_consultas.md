# Informe — Parte 4: Consultas resumen y subconsultas bajo especificación precisa

## 1. Objetivo y método

El trabajo consistió en generar dos consultas del modelo Food Store a partir de specs escritas antes de pedirle el SQL a la IA, y verificar que las dos formas de escribir cada una devuelvan el mismo resultado.

**Base de datos:** `bd2_tp3`, PostgreSQL 17.11. 50.011 productos (50.008 activos), 20.005 clientes, 200.005 pedidos, 499.263 detalles.

Los cuatro pasos de la consigna se cumplieron en orden:

1. Se redactaron las dos specs (resumen y subconsulta) antes de pedir nada.
2. Se le pasó cada spec a OpenCode en una sesión limpia, sin mostrarle ninguna solución previa. Solo se agregaron las convenciones de nombres del esquema (`id_<tabla>` para PK, `id_<tabla_referenciada>` para FK, y las columnas de cada tabla), porque sin eso la IA inventaría nombres de columna.
3. Se escribió una segunda versión de cada consulta con estructura distinta.
4. Se verificó la equivalencia con `EXCEPT` en ambas direcciones.

Las specs están en `docs/spec_consultas_parte4.md`.

## 2. Consulta A — facturación por categoría

La spec (sección "Consulta de resumen" en el archivo referenciado) pide: facturación total por categoría, con inclusión de categorías sin ventas (monto 0), orden descendente por monto.

### Versión 1 — LEFT JOIN con GROUP BY

Generada por la IA a partir de la spec:

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

**Tres decisiones de diseño:**

- **El filtro `p.activo = TRUE` va en el `ON` del `LEFT JOIN`, no en el `WHERE`.** Si estuviera en el `WHERE`, las categorías sin productos activos desaparecerían del resultado, porque el `WHERE` se aplica después del join y descarta las filas con `NULL`. En el `ON`, la categoría sobrevive con sus columnas en `NULL`, que es lo que pide la cláusula de inclusión de la spec.
- **`COUNT(dp.id_detalle)` en lugar de `COUNT(*)`.** `COUNT(*)` contaría la fila fantasma que el `LEFT JOIN` genera para una categoría sin ventas, devolviendo 1 en lugar de 0. `COUNT` de una columna ignora los `NULL`.
- **`GROUP BY c.id_categoria, c.nombre` agrupa por la PK además del nombre.** En este esquema `categoria.nombre` es `UNIQUE`, así que da igual, pero evita que dos categorías homónimas se fusionen.

### Versión 2 — subconsultas correlacionadas en el SELECT, sin GROUP BY

Escrita de forma independiente:

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

### Resultado

Ambas versiones devuelven las mismas 4 filas:

| Categoría   | Líneas de venta | Monto facturado    |
|-------------|:---------------:|-------------------:|
| Lácteos     | 100.350         | 126.098.972,37    |
| Almacén     | 100.238         | 125.747.608,46    |
| Bebidas     | 99.572          | 125.587.056,38    |
| Panificados | 98.686          | 125.367.166,20    |

Son 4 y no 5 porque la quinta categoría (Congelados) tiene `activo = FALSE` desde el TP2, y el filtro de borrado lógico la excluye.

### Verificación

`EXCEPT` en ambas direcciones: 0 filas en las dos. Las versiones son equivalentes.

## 3. Consulta B — productos nunca vendidos

La spec (sección "Consulta con subconsulta" en el archivo referenciado) pide: productos activos que no tengan ninguna fila en `detalle_pedido`. Exige resolverse con subconsulta, no con `LEFT JOIN`.

### Versión 1 — NOT EXISTS (generada por la IA)

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

**Observación sobre el alias:** la subconsulta compara `id_producto = producto.id_producto` sin alias. Funciona porque el `id_producto` de la izquierda se resuelve contra `detalle_pedido` y el de la derecha contra `producto`, pero es frágil: si `detalle_pedido` no tuviera esa columna, PostgreSQL la buscaría en la consulta externa y compararía la columna consigo misma, dando siempre verdadero y devolviendo cero filas sin ningún error. Con alias explícitos no puede ocurrir.

### Versión 2 — LEFT JOIN ... IS NULL (sin subconsulta)

Escrita de forma independiente:

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
LEFT JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE p.activo = TRUE
  AND dp.id_producto IS NULL
ORDER BY p.nombre ASC;
```

### Resultado

Ambas versiones devuelven las mismas 2 filas:

| id_producto | nombre         | precio | stock |
|:-----------:|----------------|-------:|------:|
| 66891       | Producto 31880 | 717,57 |    58 |
| 78088       | Producto 43077 | 161,63 |    67 |

Este número cierra con la verificación de distribución de la Parte 1: 50.008 productos distintos aparecen en `detalle_pedido` sobre 50.011 existentes. Los que faltan son estos 2, que el sorteo de la carga masiva nunca eligió, más 1 producto preexistente con `activo = FALSE` que esta consulta ni siquiera considera.

### Verificación

`EXCEPT` en ambas direcciones: 0 filas en las dos. Las versiones son equivalentes.

## 4. Tercera variante — NOT IN

Se probó además una tercera forma de escribir la consulta B:

```sql
SELECT COUNT(*) FROM producto
WHERE activo = TRUE
  AND id_producto NOT IN (SELECT id_producto FROM detalle_pedido);
```

Devuelve 2, el mismo resultado. Dos observaciones:

- **Devuelve el resultado correcto porque `detalle_pedido.id_producto` está declarada `NOT NULL`.** Si esa columna admitiera nulos y hubiera aunque sea uno, `NOT IN` devolvería 0 filas, sin error ni aviso, por la semántica de tres valores de SQL: comparar contra `NULL` da "desconocido", no "falso". La garantía no viene del SQL sino del esquema. `NOT EXISTS` no tiene ese problema.
- **Fue notoriamente más lenta que las otras dos**, que respondieron de inmediato: `NOT IN` tiene que materializar las 499.263 filas de la subconsulta antes de poder descartar nada, mientras que `NOT EXISTS` puede cortar apenas encuentra la primera coincidencia.

## 5. Conclusiones

1. **La verificación con `EXCEPT` es un hecho, no una opinión.** Comparar a ojo dos tablas de 4 filas puede pasar por alto una diferencia sutil en un monto o un nombre. `EXCEPT` en ambas direcciones es un mecanismo mecánico: si devuelve 0 filas, las consultas son idénticas en resultado.

2. **Una spec precisa reduce la ambigüedad de la implementación.** El caso más claro es la cláusula de inclusión de la Consulta A: sin ella, cada implementación podría elegir `INNER JOIN` o `LEFT JOIN` y devolver conjuntos distintos de filas. Fijarla en la spec obliga al `LEFT JOIN` y hace que las dos versiones sean comparables.
