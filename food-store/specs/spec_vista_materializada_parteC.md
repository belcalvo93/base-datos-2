# Spec de la vista materializada - TP5 Parte C

**Archivo de implementacion:** `food-store/materializadas.sql`
**Informe de mediciones:** `food-store/informe_mediciones.md`
**Estado:** completada por el integrante a cargo de la Parte C (Hernan).

---

## Vista materializada - `mv_facturacion_cat_mes`

### Proposito

Materializar el reporte agregado de facturacion por categoria y mes (Consulta A de la Semana 4,
documentada en `docs/informe_tp4_semana4.md`). Vale la pena porque cada ejecucion cruza las cinco
tablas, procesa ~500.000 lineas de `detalle_pedido` y ~200.000 `pedido`, arma un `Sort` externo a
disco (8.000 kB) y recien entonces agrupa en ~100 filas mensuales (399.184 filas intermedias para
devolver 100). Materializar convierte ese costo, que se paga en cada consulta, en un costo unico de
creacion + refresco; las lecturas posteriores son un `Seq Scan` de 100 filas.

### Consulta base

```sql
SELECT
    c.id_categoria,
    c.nombre AS categoria,
    DATE_TRUNC('month', pe.fecha) AS mes,
    COUNT(DISTINCT pe.id_pedido) AS cantidad_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS facturacion_total
FROM categoria c
JOIN producto p       ON p.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
JOIN pedido pe        ON pe.id_pedido = dp.id_pedido
WHERE c.activo = TRUE AND p.activo = TRUE
GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', pe.fecha);
```

Sobre `practica_bd2` (200.005 pedidos, 500.151 detalles, `ANALYZE` corrido) esta consulta atraviesa
399.184 filas antes de agregar, con `Parallel Hash Join` (2 workers) y sort externo a disco, y tarda
870,172 ms. Ahi esta el costo que justifica materializarla.

### Columnas de la vista

| Columna | Origen | Tipo | Notas |
|---|---|---|---|
| `id_categoria` | `categoria.id_categoria` | BIGINT | PK de origen; entra al `GROUP BY` y al indice unico |
| `categoria` | `categoria.nombre` | VARCHAR(80) | Nombre de la categoria, legible para el reporte |
| `mes` | `DATE_TRUNC('month', pedido.fecha)` | TIMESTAMPTZ | Primer dia del mes; define la particion temporal |
| `cantidad_pedidos` | `COUNT(DISTINCT pedido.id_pedido)` | BIGINT | Pedidos distintos; un pedido con varios productos de la misma categoria se cuenta una vez |
| `facturacion_total` | `SUM(detalle_pedido.cantidad * detalle_pedido.precio_unitario)` | NUMERIC | Suma de subtotales; `precio_unitario` es el precio historico congelado (R4) |

### Indice unico para `REFRESH CONCURRENTLY`

`REFRESH MATERIALIZED VIEW CONCURRENTLY` no funciona sin un indice unico sobre la vista. Es el que
permite refrescar sin bloquear a quien este leyendo: sin el, el `REFRESH` toma un `ACCESS EXCLUSIVE` y
el reporte queda inaccesible mientras dura.

El indice tiene que ser unico sobre la combinacion de columnas que identifica una fila del reporte, sin
nulos:

```sql
CREATE UNIQUE INDEX uq_mv_facturacion_cat_mes
    ON mv_facturacion_cat_mes (id_categoria, mes);
```

Columnas elegidas y por que identifican una fila univocamente: el `GROUP BY` produce exactamente una
fila por combinacion `(id_categoria, mes)`. `categoria.id_categoria` es PK (nunca nula) y `mes` surge
de `DATE_TRUNC` sobre una columna `NOT NULL`, asi que la combinacion no admite nulos y, al ser el grupo
univoco, tampoco duplicados.

### Restricciones de implementacion

- Se crea con `WITH DATA` (comportamiento por defecto), asi queda poblada desde el arranque.
- Las columnas se listan explicitamente; no se usa `SELECT *`.
- No se modifica el modelo de datos ni las restricciones de las tablas base.
- `materializadas.sql` es idempotente: `DROP MATERIALIZED VIEW IF EXISTS ... CASCADE` antes del `CREATE`.
- La script se leyo linea por linea antes de ejecutarse y se probo primero dentro de una transaccion
  con `ROLLBACK`, segun `protocolo_seguridad.md`.

### Criterio de aceptacion

1. El tiempo de consultar la vista materializada es al menos 10 veces menor que el de la consulta sin
   materializar, medido con `EXPLAIN (ANALYZE, BUFFERS)` en las dos. **Medido: 870,172 ms a 0,070 ms,
   una mejora de ~12.430x.**
2. Los resultados coinciden: `EXCEPT` en las dos direcciones devuelve 0 filas contra la consulta
   original, ejecutado inmediatamente despues del `REFRESH`.
3. `REFRESH MATERIALIZED VIEW CONCURRENTLY` corre sin error (0,927 s en la base de medicion), lo que
   prueba que el indice unico sirve.

### Frecuencia de refresco

El punto 3 de la Parte C pide justificar cada cuanto correr el `REFRESH` y que implica para el usuario
que el dato no se actualice entre uno y otro.

| Pregunta | Respuesta |
|---|---|
| Cada cuanto se consulta el reporte | Se usa para reportes de negocio mensuales y revisiones periodicas de la facturacion por categoria |
| Cada cuanto cambian los datos de origen | A diario: se cargan pedidos todos los dias |
| Frecuencia de refresco propuesta | Diaria (una vez por noche, cuando baje el trafico) |
| Desfasaje maximo que ve el usuario | Hasta 24 horas: lo ultimo que aparece es lo del refresh de la noche anterior |
| Que decision se tomaria mal con un dato desactualizado | Ninguna operativa. El reporte es mensual y sirve para analisis; las decisiones de atencion al cliente y stock no dependen del monto exacto por mes al minuto. Si una alerta dependiera del dato diario al instante, esta vista no seria la herramienta (ahi iria una consulta directa) |

La ultima fila es la que define de verdad la frecuencia: si con datos de ayer nadie toma una decision
equivocada, refrescar cada hora es gasto puro. El refresh, ademas, cuesta 0,927 s por corrida; hacerlo
una vez al dia es el costo minimo que mantiene el reporte util.