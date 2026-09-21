# Informe de mediciones — TP5, Parte A: plan de indexado

## 1. Resumen

De los cuatro índices evaluados se **acepta uno** y se descartan tres, más una prueba adicional sobre las consultas analíticas del TP4 que también se descarta.

| Índice | Consulta | Decisión | Motivo en una línea |
|---|---|---|---|
| `(id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo` | C1 | **Aceptado** | `Bitmap Heap Scan + Sort` → `Index Only Scan` sin `Sort`: 10,5 → 3,1 ms, 527 → 86 buffers |
| `(id_categoria, precio DESC) WHERE activo` (hipótesis original de la spec) | C1 | Descartado | El planificador no lo usa; tiempo idéntico al base |
| `(id_cliente, fecha DESC)` | C2 | Descartado | Devuelve 24 filas, el `Sort` es insignificante; sin cambio de plan ni de tiempo |
| `(id_producto, id_pedido)` | C3 | Descartado (**sobreindexación**) | Superconjunto del índice existente; mismo plan, mismo tiempo, +17 % de WAL por INSERT |
| `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` | TP4 analíticas | Descartado | Las consultas leen el 100 % de la tabla; siguen con `Seq Scan` (727 ms → 727 ms) |

Sentencia final aceptada: [`food-store/indices.sql`](indices.sql). Planes completos: [`food-store/planes_tp5_parteA.txt`](planes_tp5_parteA.txt).

## 2. Entorno y método

**Base.** `bd2_tp3`, restaurada con `pg_restore` desde `bd2_tp3_actualizada_20260919.dump` (generado con `pg_dump` 17.11 el 19/09/2026). Conteos verificados tras restaurar: 5 categorías, 20.005 clientes, 50.011 productos, 200.005 pedidos, 499.263 detalles. Los índices de partida son los tres del TP1 (`idx_producto_categoria_activo`, `idx_pedido_id_cliente`, `idx_detalle_pedido_id_producto`) más los de PK/UNIQUE. El dump incluye además las vistas de la Parte B y la tabla `usuario`; no participan de esta parte.

**Motor.** PostgreSQL 17.11 sobre Windows 11. La medición se hizo en una **instancia temporal** en el puerto 5433 con configuración por defecto (`shared_buffers` 128 MB, `work_mem` 4 MB, `random_page_cost` 4), separada de `bd2_proyecto` y `bd2_trabajo`, que no se tocaron. Toda la base cabe en caché: las mediciones son *en caliente*.

**Estadísticas.** `pg_restore` no carga estadísticas del planificador, por eso se corrió `VACUUM ANALYZE` después de restaurar (esto además deja armado el mapa de visibilidad, necesario para el `Index Only Scan`).

**Protocolo.** Todo índice de prueba se creó dentro de `BEGIN; … ROLLBACK;` (`protocolo_seguridad.md`, paso 2). Antes de cada `EXPLAIN` la consulta se ejecutó una vez para calentar la caché.

**Lectura (consigna 4).** `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`, una corrida de calentamiento + 5 corridas medidas; se informa la **mediana**. Como C2 y C3 duran décimas de milisegundo, cada estado se midió además con `pgbench` (`-n -M simple -c 1 -T 5`, 3 repeticiones, miles de ejecuciones por repetición). La latencia de `pgbench` incluye transferir las filas al cliente, por eso es mayor que el `Execution Time` en C1.

**Escritura (consigna 5).** [`food-store/medicion_escritura.sql`](medicion_escritura.sql): 500 `INSERT` individuales por tabla (con los triggers de `restricciones.sql` activos) y 500 `UPDATE` de `stock`, cada estado en su propia transacción con `ROLLBACK`, 15 rondas, mediana. Se mide **tiempo** y **bytes de WAL** generados (ver sección 5 sobre por qué las dos métricas).

**Limitación.** Los milisegundos absolutos son de esta máquina e instancia; al reproducir en `bd2_trabajo` van a variar. Lo reproducible son los planes y las proporciones.

## 3. Punto de partida: qué consultas hacen Seq Scan hoy

La consigna pide partir de consultas que hoy resuelven con `Seq Scan` sobre una tabla grande. Se ejecutaron las siete consultas de [`queries.sql`](queries.sql) sobre la base restaurada (mediana de 5 corridas):

| Consulta | Origen | Acceso principal | Mediana |
|---|---|---|---:|
| C1 productos vigentes categoría 5 | TP3 P2 | `Bitmap Heap Scan` (idx TP1) + `Sort` | 10,5 ms |
| C2 pedidos del cliente 20155 | TP3 P2 | `Bitmap Heap Scan` (idx TP1) + `Sort` | 0,15 ms |
| C3 ventas del producto 49112 | TP3 P2 | `Bitmap Heap Scan` (idx TP1) + `Sort` | 0,17 ms |
| P4-A facturación por categoría | TP3 P4 | **`Seq Scan` en `detalle_pedido`** (499.263) y `producto` | 727 ms |
| P4-B productos nunca vendidos | TP3 P4 | **`Seq Scan` en `detalle_pedido`** y `producto` (Hash Anti Join) | 259 ms |
| S4-A facturación por categoría y mes | TP4 S4 | **`Seq Scan` en `detalle_pedido`, `pedido`, `producto`** | 2.219 ms |
| S4-B ranking de clientes por gasto | TP4 S4 | `Index Scan` en el UNIQUE de `detalle_pedido` y `pedido_pkey`; `Seq Scan` solo en `cliente` (20.005) | 1.007 ms |

**Hallazgo.** C1, C2 y C3 ya **no** hacen `Seq Scan`: los índices del TP1 se lo sacaron. Su `Seq Scan` original está medido en el TP3 (`docs/informe_parte2_indices.md`: 7,6 / 39,0 / 43,8 ms sin índices). Los `Seq Scan` sobre tablas grandes que subsisten hoy están en las consultas analíticas P4-A, P4-B y S4-A.

Las tres specs de Kiro ya existentes (C1, C2, C3) apuntan a consultas operativas frecuentes cuyo plan todavía admite mejoras (el `Sort`, el acceso al heap). Se evaluaron esas tres tal como estaban especificadas (sección 4) y se probó por separado qué podía hacer un índice por las analíticas (sección 6).

## 4. Consultas candidatas

### 4.1 C1 — productos vigentes de la categoría 5

```sql
SELECT p.id_producto, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.id_categoria = 5 AND p.activo = TRUE
ORDER BY p.precio DESC;
```

Selectividad: 10.047 de 50.011 filas (20 %). Spec: [`spec_indice_productos_categoria_precio.md`](specs/spec_indice_productos_categoria_precio.md).

**Antes** (índice del TP1 `idx_producto_categoria_activo`):

```text
Sort  (cost=1434.41..1459.60 rows=10077) (actual time=9.170..10.098 rows=10047)
  Sort Key: p.precio DESC
  Sort Method: quicksort  Memory: 932kB
  Buffers: shared hit=527
  ->  Bitmap Heap Scan on producto p  (cost=122.39..764.35) (actual time=0.403..3.881 rows=10047)
        Heap Blocks: exact=516
        ->  Bitmap Index Scan on idx_producto_categoria_activo  (cost=0.00..119.87)
Execution Time: 10.781 ms
```

**Iteración 1 — hipótesis de la spec:** `CREATE INDEX … ON producto (id_categoria, precio DESC) WHERE activo = TRUE`.
El plan **no cambia**: el planificador sigue con `idx_producto_categoria_activo` y `Sort`, y el índice nuevo queda sin usar. Aun desactivando el bitmap scan, prefiere `Seq Scan + Sort` (cost 1825) antes que usarlo. Razón: el índice guarda `(id_categoria, precio)` pero la consulta también devuelve `id_producto`, `nombre` y `stock`; recorrer 10.047 entradas ordenadas implica 10.047 visitas al heap, más caro que un bitmap más un `Sort` en memoria. Es exactamente el caso que el criterio de aceptación de la spec manda descartar.

**Iteración 2 — variante con `INCLUDE`** (propuesta tras ver el resultado anterior):

```sql
CREATE INDEX idx_producto_categoria_precio
    ON producto (id_categoria, precio DESC)
    INCLUDE (id_producto, nombre, stock)
    WHERE activo = TRUE;
```

**Después:**

```text
Index Only Scan using idx_producto_categoria_precio on producto p
    (cost=0.41..512.76 rows=10077) (actual time=0.016..1.784 rows=10047)
  Index Cond: (p.id_categoria = 5)
  Heap Fetches: 0
  Buffers: shared hit=86
Execution Time: 2.125 ms
```

| | Plan | `Sort` | Buffers | Mediana (5) | `pgbench` |
|---|---|:-:|---:|---:|---:|
| Base (TP1) | Bitmap Heap Scan | sí (932 kB) | 527 | 10,5 ms | 18,2 ms |
| + hipótesis de la spec | Bitmap Heap Scan (índice nuevo sin uso) | sí | 527 | 10,5 ms | 18,5 ms |
| **+ con `INCLUDE`** | **Index Only Scan** | **no** | **86** | **3,1 ms** | **11,0 ms** |

Mejora: 3,4× en `Execution Time`, 6,1× menos buffers, y 1,65× en latencia de punta a punta (`pgbench`, donde el costo de transferir 10.047 filas al cliente es fijo y diluye el efecto).

**Equivalencia de resultados.** Dentro de una transacción con `ROLLBACK`, el resultado con el índice (`Index Only Scan`) se comparó contra el resultado sin él (`enable_indexonlyscan = off`, `enable_indexscan = off`): 10.047 filas en ambos, `EXCEPT` en las dos direcciones = 0 filas, orden descendente por `precio` verificado.

**Decisión: aceptado** (`indices.sql`). Costo y riesgos en las secciones 5 y 8.

### 4.2 C2 — historial de pedidos del cliente 20155

```sql
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.id_cliente = 20155 ORDER BY p.fecha DESC;
```

Selectividad: 24 de 200.005 pedidos (0,012 %). Spec: [`spec_indice_pedidos_cliente_fecha.md`](specs/spec_indice_pedidos_cliente_fecha.md).

Candidato: `(id_cliente, fecha DESC)`. Después de crearlo el plan es **idéntico** al base: `Index Scan` en `cliente_pkey`, `Bitmap Heap Scan` sobre `pedido` con `idx_pedido_id_cliente`, y `Sort` de 24 filas (quicksort, 26 kB). El planificador ni siquiera elige el índice nuevo: con 24 filas no le conviene evitar un `Sort` que cuesta microsegundos.

| | Plan | Mediana (5) | `pgbench` |
|---|---|---:|---:|
| Base (TP1) | Bitmap Heap Scan + Sort | 0,152 ms | 0,43 ms |
| + `(id_cliente, fecha DESC)` | idéntico; índice sin uso | 0,151 ms | 0,46 ms |

**Decisión: descartado.** Sin mejora, y su primera columna repite `idx_pedido_id_cliente`. Cuesta +26 % de WAL en cada `INSERT` de `pedido` (sección 5).

### 4.3 C3 — pedidos donde se vendió el producto 49112

```sql
SELECT dp.id_detalle, dp.cantidad, dp.precio_unitario, ped.fecha
FROM detalle_pedido dp JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE dp.id_producto = 49112 ORDER BY ped.fecha DESC;
```

Selectividad: 27 de 499.263 detalles (0,005 %). Spec: [`spec_indice_detalle_producto_pedido.md`](specs/spec_indice_detalle_producto_pedido.md).

Candidato: `(id_producto, id_pedido)`. Acá el planificador **sí** usa el índice nuevo (`Bitmap Index Scan on idx_detalle_producto_pedido`, en lugar de `idx_detalle_pedido_id_producto`), pero el plan tiene la misma forma y el mismo costo estimado (4,50), 27 bloques de heap en ambos casos, y el mismo `Index Scan` en `pedido_pkey`.

| | Plan | Mediana (5) | `pgbench` (3 rep.) |
|---|---|---:|---:|
| Base (TP1) | Bitmap Heap Scan + Sort | 0,165 ms | 0,68 – 0,86 ms |
| + `(id_producto, id_pedido)` | mismo plan | 0,301 ms | 0,73 – 0,78 ms |

Las dos medidas se contradicen en el signo (la transacción de prueba da peor, `pgbench` da parecido) y los rangos se superponen: la diferencia es ruido sub-milisegundo, no una mejora ni un perjuicio. Con 27 filas y buffers iguales no hay nada que el índice nuevo pueda ahorrar: `cantidad` y `precio_unitario` se siguen leyendo del heap, y `id_pedido` no evita ningún acceso porque el join va por `pedido_pkey`.

**Decisión: descartado por sobreindexación** (detalle en la sección 7).

## 5. Costo de las escrituras

### Por qué dos métricas

La primera versión de esta medición tenía un defecto que conviene dejar registrado: el estado base medido al inicio y al final de la ronda (mismo estado, sin diferencias) daba tiempos distintos en ~60 %. Dos causas: la primera transacción de la sesión compila los planes de los triggers, y las transacciones revertidas dejan tuplas muertas que sesgan a las siguientes. Se corrigió con una corrida de calentamiento por carga y un `VACUUM` tras cada `ROLLBACK`; y se sumó una segunda métrica, los **bytes de WAL** generados (`pg_current_wal_insert_lsn`), que es determinista: mide cuánto trabajo de mantenimiento de índices hizo el motor, sin depender del reloj.

Con el método corregido, `base_a` y `base_b` difieren entre 1 % y 10 % en tiempo y menos del 1 % en WAL. **Esa es la resolución de la medición: diferencias de tiempo menores a ~10 %–20 % no son distinguibles del ruido; las de WAL sí.**

### Resultados (500 filas por carga, mediana de 15 rondas)

Referencia "base" = promedio de `base_a` y `base_b`.

**`INSERT` en `detalle_pedido`** (la carga que pide la consigna) — base 65,4 ms / 207.468 bytes de WAL.

| Estado | Tiempo | Δ tiempo | WAL (bytes) | Δ WAL |
|---|---:|---:|---:|---:|
| Aceptado (`idx_producto_categoria_precio`, sobre `producto`) | 79,5 ms | +22 %* | 207.736 | **+0,1 %** |
| Descartado `(id_producto, id_pedido)` | 108,6 ms | +66 % | 243.128 | **+17,2 %** |
| Las cuatro propuestas juntas | 101,9 ms | +56 % | 243.776 | +17,5 % |

\* El índice aceptado vive en `producto`: no participa de estos `INSERT`, y el WAL lo confirma (+0,1 %). El +22 % de tiempo es ruido de esta carga (`base_a` vs `base_b` ya difieren 10 %).

**`INSERT` en `pedido`** — base 24,1 ms / 139.216 bytes.

| Estado | Tiempo | Δ tiempo | WAL (bytes) | Δ WAL |
|---|---:|---:|---:|---:|
| Aceptado (sobre `producto`) | 24,9 ms | +3 % | 138.808 | −0,3 % |
| Descartado `(id_cliente, fecha DESC)` | 53,8 ms | +123 % | 175.720 | **+26,2 %** |
| Las cuatro juntas | 49,4 ms | +105 % | 174.904 | +25,6 % |

**`INSERT` en `producto`** — base 56,6 ms / 134.540 bytes.

| Estado | Tiempo | Δ tiempo | WAL (bytes) | Δ WAL |
|---|---:|---:|---:|---:|
| **Aceptado** `idx_producto_categoria_precio` | 74,8 ms | **+32 %** | 194.824 | **+44,8 %** |
| Descartado (parcial sin `INCLUDE`) | 65,2 ms | +15 % | 170.720 | +26,9 % |
| Las cuatro juntas | 85,6 ms | +51 % | 230.920 | +71,6 % |

**`UPDATE` de `producto.stock`** — base 27,6 ms / 164.056 bytes.

| Estado | Tiempo | Δ tiempo | WAL (bytes) | Δ WAL |
|---|---:|---:|---:|---:|
| **Aceptado** `idx_producto_categoria_precio` | 41,5 ms | **+50 %** | 216.392 | **+31,9 %** |
| Descartado (parcial sin `INCLUDE`) | 39,0 ms | +41 % | 200.144 | +22,0 % |

### Lectura

* **El índice aceptado no toca la escritura crítica.** `detalle_pedido` es la tabla que más crece (una fila por línea de venta) y el índice aceptado no la afecta: +0,1 % de WAL.
* **Sí cuesta sobre `producto`**: +45 % de WAL por `INSERT` y +32 % por `UPDATE` de `stock`. Es un costo real y se acepta a conciencia: el catálogo se lee muchas más veces de las que se modifica, y el alta de productos es infrecuente frente a las consultas de catálogo. Ver el riesgo del `UPDATE` de `stock` en la sección 8.
* **El descartado en `detalle_pedido` habría sido caro y sin beneficio**: +17 % de WAL en la tabla más escrita a cambio de cero mejora medible.
* **Los costos suben con cada índice y se suman**: con las cuatro propuestas, `producto` llega a +72 % de WAL.
* El parcial sin `INCLUDE` cuesta +27 % de WAL en `producto` **sin que ninguna consulta lo use**: es el costo puro de un índice muerto.

## 6. Los Seq Scan que sí persisten: consultas analíticas del TP4

> Esta prueba fue **exploratoria**: se hizo después de las tres specs y no tiene spec propia de Kiro. Se documenta igual porque cierra la pregunta de la sección 3.

Las consultas P4-A, P4-B y S4-A hacen `Seq Scan` sobre `detalle_pedido`. Se probó si un índice puede evitarlo:

* **P4-A y S4-A** leen todas las filas de `detalle_pedido` (agregan por categoría / mes sobre todo el histórico). Se probó un índice cubriente `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)`, que permitiría un `Index Only Scan`. El planificador **lo ignora** y sigue con `Seq Scan`; tiempo 727 ms → 727 ms (P4-A) y 2.219 → 2.246 ms (S4-A). El índice pesaría 24 MB frente a los 33 MB de la tabla: leerlo entero no ahorra casi nada, y el trabajo pesado no está en el acceso sino en el `Hash Join`, la agregación y el ordenamiento externo (S4-A vuelca 23 MB a disco).
* **P4-B (nunca vendidos)** es distinta: no necesita un índice nuevo, porque `idx_detalle_pedido_id_producto` ya permite un `Index Only Scan`. Forzándolo (`enable_seqscan = off`, en transacción) el plan pasa a `Merge Anti Join` con `Index Only Scan` y baja de 259 a 133 ms (1,9×). El planificador elige el `Seq Scan` porque estima costos casi iguales (17.496 contra 18.170); no es un problema de índices faltantes y no se resolvió tocando parámetros del motor.

**Conclusión.** Un `Seq Scan` que lee la mayoría de la tabla es la elección correcta, no un síntoma. Ningún índice nuevo mejora estas consultas; el camino para S4-A es la vista materializada de la Parte C.

## 7. Propuesta descartada por sobreindexación (consigna 6)

**Descartado: `CREATE INDEX idx_detalle_producto_pedido ON detalle_pedido (id_producto, id_pedido)`** (C3).

1. **Redundante.** Su primera columna es exactamente la del índice existente `idx_detalle_pedido_id_producto`; todo lo que sirve el nuevo, lo sirve el viejo. Un índice compuesto solo justifica su existencia si aporta algo que el prefijo no da.
2. **No aporta lo que promete.** La hipótesis era que `id_pedido` ayudaría al join. No ayuda: el join con `pedido` va por `pedido_pkey`, y `cantidad` y `precio_unitario` igual se leen del heap. Mismo plan, mismo costo estimado, mismos 27 bloques, tiempos indistinguibles.
3. **`id_pedido` ya está cubierto** por la restricción `UNIQUE (id_pedido, id_producto)`.
4. **Tiene costo en la tabla que más se escribe:** +17 % de WAL por cada `INSERT` en `detalle_pedido`, más el espacio y el mantenimiento en cada `UPDATE`/`DELETE`.

También se descartaron por el mismo criterio (índice que no cambia el plan pero se mantiene en cada escritura):

* `(id_cliente, fecha DESC)` en `pedido`: prefijo del existente, 24 filas, +26 % de WAL por `INSERT`.
* `(id_categoria, precio DESC) WHERE activo` en `producto`, sin `INCLUDE`: el planificador no lo usa, +27 % de WAL por `INSERT`.

## 8. Decisión final, riesgos y pendientes

**Se crea un solo índice**, `idx_producto_categoria_precio`, en [`indices.sql`](indices.sql).

**Riesgos del índice aceptado (a defender oralmente):**

1. **`UPDATE` de `stock`.** `stock` forma parte del índice (`INCLUDE`), así que cada actualización de stock obliga a mantenerlo (+50 % de tiempo por `UPDATE`, medido). Hoy los triggers de `restricciones.sql` solo *leen* el stock, no lo descuentan. Si en la Semana 6 los procedimientos descuentan stock en cada venta, ese costo pasa a ser por línea de venta y la decisión debe revisarse (alternativa: sacar `stock` del `INCLUDE`, a costa de volver a leer el heap para esa columna).
2. **Depende del autovacuum.** El `Index Only Scan` solo evita el heap si las páginas están marcadas como visibles; sobre una tabla con muchos cambios recientes aparecerán `Heap Fetches` y el beneficio baja hacia el del índice sin `INCLUDE`.
3. **Tamaño.** 3,3 MB frente a los 360 kB del índice del TP1 (9×). Irrelevante hoy, pero es un trade-off explícito.
4. **Redundancia con el heredado.** Con `idx_producto_categoria_precio`, `idx_producto_categoria_activo` (de `schema.sql`) queda redundante para esta consulta y se podría eliminar para ahorrar escritura. No se hace acá porque la consigna pide no modificar lo heredado; queda como pendiente para la próxima entrega. Las cifras de escritura de la sección 5 se midieron con **ambos** presentes (el peor caso).

## 9. Cómo reproducir

Sobre `bd2_trabajo` (recreada con `createdb -T bd2_proyecto`, o restaurada desde el dump), con backup previo y confirmando `SELECT current_database();`:

```bash
psql -U postgres -d bd2_trabajo -X -c "VACUUM ANALYZE"

# Planes antes/después (cada "después" corre en BEGIN … ROLLBACK)
psql -U postgres -d bd2_trabajo -X -f food-store/medicion_planes.sql > food-store/planes_tp5_parteA.txt

# Costo de escritura: una ronda por ejecución; el informe usó 15 y tomó la mediana
for i in $(seq 1 15); do
  psql -U postgres -d bd2_trabajo -X -A -t -f food-store/medicion_escritura.sql
done

# Latencia con muchas repeticiones (ejemplo con C3; guardar la consulta en c3.sql)
pgbench -U postgres -n -M simple -c 1 -T 5 -f c3.sql bd2_trabajo
```

Para crear el índice aceptado: `psql -U postgres -d bd2_trabajo -f food-store/indices.sql` (primero dentro de `BEGIN; … ROLLBACK;`).

---

*Partes B y C del TP5: este archivo se completa con la verificación de equivalencia de las vistas y la medición de la vista materializada cuando esas partes se cierren.*
