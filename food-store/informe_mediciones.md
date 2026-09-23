# Informe de mediciones — TP5

Mediciones de las tres partes: el plan de indexado (A), la verificacion de equivalencia de
las vistas (B) y la vista materializada (C).

---

# Parte A — Plan de indexado

## 1. Resumen

Sobre C1, C2 y C3 se evaluaron cuatro índices: se **acepta uno** y se descartan tres. Las tres consultas que hoy sí hacen `Seq Scan` (P4-A, P4-B y S4-A) se especificaron en Kiro y se le pidió a OpenCode una propuesta por consulta: en las tres concluyó que **ningún índice se justifica**, la medición lo confirma y las tres quedan descartadas (sección 6).

| Índice | Consulta | Decisión | Motivo en una línea |
|---|---|---|---|
| `(id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo` | C1 | **Aceptado** | `Bitmap Heap Scan + Sort` → `Index Only Scan` sin `Sort`: 10,5 → 3,1 ms, 527 → 86 buffers |
| `(id_categoria, precio DESC) WHERE activo` (hipótesis original de la spec) | C1 | Descartado | El planificador no lo usa; tiempo idéntico al base |
| `(id_cliente, fecha DESC)` | C2 | Descartado | Devuelve 24 filas, el `Sort` es insignificante; sin cambio de plan ni de tiempo |
| `(id_producto, id_pedido)` | C3 | Descartado (**sobreindexación**) | Superconjunto del índice existente; mismo plan, mismo tiempo, +17 % de WAL por INSERT |
| `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)` | P4-A | Descartado | Lee el 100 % de la tabla y sigue con `Seq Scan` (743 → 735 ms); 24 MB y +21 % de WAL por INSERT |
| Ninguno (el índice existente alcanza) | P4-B | Descartado | `idx_detalle_pedido_id_producto` ya sirve; el `Seq Scan` es una decisión de costos del planificador (con `random_page_cost = 1.1` baja de 258 a 110 ms sin índice nuevo) |
| `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` | S4-A | Descartado | Agrega todo el histórico; plan y tiempo no cambian (2.219 → 2.246 ms) |

Sentencia final aceptada: [`food-store/indices.sql`](indices.sql). Planes completos: [`food-store/planes_tp5_parteA.txt`](planes_tp5_parteA.txt).

## 2. Entorno y método

**Base.** `bd2_tp3`, restaurada con `pg_restore` desde `bd2_tp3_actualizada_20260919.dump` (generado con `pg_dump` 17.11 el 19/09/2026). Conteos verificados tras restaurar: 5 categorías, 20.005 clientes, 50.011 productos, 200.005 pedidos, 499.263 detalles. Los índices de partida son los tres del TP1 (`idx_producto_categoria_activo`, `idx_pedido_id_cliente`, `idx_detalle_pedido_id_producto`) más los de PK/UNIQUE. El dump incluye además las vistas de la Parte B y la tabla `usuario`; no participan de esta parte.

**Motor.** PostgreSQL 17.11 sobre Windows 11. La medición se hizo en una **instancia temporal** en el puerto 5433 con configuración por defecto (`shared_buffers` 128 MB, `work_mem` 4 MB, `random_page_cost` 4), separada de `bd2_proyecto` y `bd2_trabajo`, que no se tocaron. Toda la base cabe en caché: las mediciones son *en caliente*.

**Estadísticas.** `pg_restore` no carga estadísticas del planificador, por eso se corrió `VACUUM ANALYZE` después de restaurar (esto además deja armado el mapa de visibilidad, necesario para el `Index Only Scan`).

**Protocolo.** Todo índice de prueba se creó dentro de `BEGIN; … ROLLBACK;` (`protocolo_seguridad.md`, paso 2). Antes de cada `EXPLAIN` la consulta se ejecutó una vez para calentar la caché.

**Lectura (consigna 4).** `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`, una corrida de calentamiento + 5 corridas medidas; se informa la **mediana**. `medicion_planes.sql` imprime una sola ejecución por sección (la que figura en `planes_tp5_parteA.txt`); las medianas de 5 se obtuvieron repitiendo cada `EXPLAIN` con un ciclo aparte, que no está como script en el repo. Como C2 y C3 duran décimas de milisegundo, cada estado se midió además con `pgbench` (`-n -M simple -c 1 -T 5`, 3 repeticiones, miles de ejecuciones por repetición). La latencia de `pgbench` incluye transferir las filas al cliente, por eso es mayor que el `Execution Time` en C1.

**Escritura (consigna 5).** [`food-store/medicion_escritura.sql`](medicion_escritura.sql): 500 `INSERT` individuales por tabla (con los triggers de `restricciones.sql` activos) y 500 `UPDATE` de `stock`, cada estado en su propia transacción con `ROLLBACK`, 15 rondas, mediana. Se mide **tiempo** y **bytes de WAL** generados (ver sección 5 sobre por qué las dos métricas). La carga 5 (el índice de P4-A) se agregó después de las cargas 1-4, con su propio par de estados base; una segunda tanda de 15 rondas del script completo reprodujo el WAL de las cargas 1-4 con diferencias menores a 1 punto porcentual (el tiempo varió hasta ~30 puntos porcentuales, por eso el WAL es la métrica de referencia).

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

Las tres specs de Kiro de C1, C2 y C3 apuntan a consultas operativas frecuentes cuyo plan todavía admite mejoras (el `Sort`, el acceso al heap): se evaluaron tal como estaban especificadas (sección 4). Para las tres consultas que sí hacen `Seq Scan` (P4-A, P4-B y S4-A) se redactaron specs nuevas, revisadas en Kiro, y se le pidió a OpenCode una propuesta por cada una (sección 6).

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

**Antes** (índice del TP1 `idx_pedido_id_cliente`) y **después** (con `(id_cliente, fecha DESC)` creado): el plan es el mismo, solo cambia el `Execution Time` por ruido.

```text
Sort  (cost=50.62..50.64 rows=10) (actual time=0.109..0.111 rows=24)
  Sort Key: p.fecha DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=28
  ->  Nested Loop  (cost=4.66..50.45 rows=10)
        ->  Index Scan using cliente_pkey on cliente c  (cost=0.29..8.30 rows=1)
        ->  Bitmap Heap Scan on pedido p  (cost=4.37..42.05 rows=10)
              Heap Blocks: exact=23
              ->  Bitmap Index Scan on idx_pedido_id_cliente  (cost=0.00..4.37 rows=10)
Execution Time: 0.150 ms   (antes)  /  0.157 ms   (después, mismo plan)
```

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

**Antes** (índice del TP1 `idx_detalle_pedido_id_producto`):

```text
Sort  (cost=139.97..140.00 rows=11) (actual time=0.149..0.151 rows=27)
  Sort Key: ped.fecha DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=138
  ->  Nested Loop  (cost=4.93..139.78 rows=11)
        ->  Bitmap Heap Scan on detalle_pedido dp  (cost=4.51..46.97 rows=11)
              Heap Blocks: exact=27
              ->  Bitmap Index Scan on idx_detalle_pedido_id_producto  (cost=0.00..4.50 rows=11)
        ->  Index Scan using pedido_pkey on pedido ped  (cost=0.42..8.44 rows=1)
Execution Time: 0.179 ms
```

**Después** (con `(id_producto, id_pedido)` creado): idéntico salvo el nombre del índice, con el mismo costo total (139,97..140,00), los mismos 138 buffers y los mismos 27 bloques de heap.

```text
              ->  Bitmap Index Scan on idx_detalle_producto_pedido  (cost=0.00..4.50 rows=11)
Execution Time: 0.332 ms
```

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

**Carga 5 — el índice de P4-A** `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)`, con su propio par de estados base (55,0 y 55,6 ms; 207.048 y 207.128 bytes de WAL):

| Estado | Tiempo | Δ tiempo | WAL (bytes) | Δ WAL |
|---|---:|---:|---:|---:|
| Descartado `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)` | 88,4 ms | +60 % | 251.432 | **+21,4 %** |

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

Las consultas P4-A, P4-B y S4-A hacen `Seq Scan` sobre `detalle_pedido`. Para cada una se siguió el flujo de la consigna: spec → revisión en Kiro → propuesta de OpenCode → medición → decisión. Las specs son [`spec_indice_facturacion_categoria.md`](specs/spec_indice_facturacion_categoria.md) (P4-A), [`spec_indice_productos_nunca_vendidos.md`](specs/spec_indice_productos_nunca_vendidos.md) (P4-B) y [`spec_indice_facturacion_categoria_mes.md`](specs/spec_indice_facturacion_categoria_mes.md) (S4-A). Antes de las specs hubo una prueba exploratoria sin spec; se conserva como «Medición previa» dentro de cada una, y se rehízo con el flujo completo.

### 6.1 Sesiones de OpenCode

Modo Plan (no ejecuta ni edita), una sesión limpia por spec, con el mismo prompt (ver `docs/duia/duia_parte5.md`). Los exports de las sesiones identifican modelo y archivos abiertos:

| Sesión | Consulta | Modelo | Archivos que abrió | Propuesta |
|---|---|---|---|---|
| 1 | P4-A | `ling-3.0-flash-fin-free` | spec, `schema.sql`, `queries.sql` e **`indices.sql`** | Ningún índice |
| 2 | P4-A (prompt con la línea «leé únicamente los archivos que te indico») | `ling-3.0-flash-fin-free` | los mismos cuatro: **abrió `indices.sql` igual** | Ningún índice |
| 3 | P4-B | `gemini-3.5-flash-lite` | spec, `schema.sql`, `queries.sql` | Ningún índice |
| 4 | S4-A | `gemini-3.5-flash-lite` | spec, `schema.sql`, `queries.sql` | Ningún índice |

**Límite de las sesiones 1 y 2:** `indices.sql` ya traía la medición de un índice cubriente descartado para las analíticas, y OpenCode la cita como prueba. Su conclusión coincide con la medición, pero no es independiente de ella. Para las sesiones 3 y 4 se ocultaron `indices.sql`, este informe y los planes mientras duró la sesión; OpenCode solo abrió los tres archivos permitidos. Que las sesiones 1 y 2 ignoraran la instrucción de leer solo los archivos indicados es una observación sobre el agente.

### 6.2 P4-A — facturación por categoría

Lee el 100 % de las 499.263 filas de `detalle_pedido`. Se midió el índice cubriente que la consulta necesita, `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)`: incluye `id_detalle` porque la consulta hace `COUNT(dp.id_detalle)`. La prueba exploratoria previa usaba `INCLUDE (id_pedido, cantidad, precio_unitario)`, sin `id_detalle`, y por eso no podía dar un `Index Only Scan`; OpenCode lo advirtió en su razonamiento y se rehízo con el índice correcto.

| | Plan | Mediana de 5 (misma corrida) |
|---|---|---:|
| Sin índice | `Seq Scan` en `detalle_pedido` | 743 ms |
| Índice de la prueba previa (sin `id_detalle`) | `Seq Scan` | 711 ms |
| **`INCLUDE (id_detalle, cantidad, precio_unitario)`** | **`Seq Scan`** | **735 ms** |

El planificador ignora el índice. Pesa 24 MB frente a los 33 MB de la tabla (73 %), así que recorrerlo no ahorra lectura, y cuesta **+21,4 % de WAL** por `INSERT` en `detalle_pedido` (sección 5). **Descartado:** no cumple la condición 1 (el `Seq Scan` no desaparece) ni la 2 (la mejora es del 1 %, no del 30 %).

### 6.3 P4-B — productos nunca vendidos

No necesita un índice nuevo: `idx_detalle_pedido_id_producto` (4,5 MB frente a 33 MB) ya permite un `Index Only Scan`. El planificador no lo elige por sus estimaciones de costo (17.586 contra 18.338, casi un empate). Lo que se midió:

| Situación | Plan | Mediana |
|---|---|---:|
| Por defecto (`random_page_cost = 4`) | `Seq Scan` + `Hash Anti Join` | 258 ms |
| Forzando `enable_seqscan = off` | `Merge Anti Join` + `Index Only Scan` | 112 ms |
| `random_page_cost = 1.1` (valor habitual en SSD) | el mismo, **elegido por el planificador** | 110 ms |

Una primera medición forzando `enable_seqscan = off` había dado 133 ms (planes, corrida única); la segunda dio 112 ms, ambas 2 a 2,3 veces más rápido. OpenCode acertó el diagnóstico: el cuello de botella no es un índice que falta sino el parámetro de costo. **Descartado** cualquier índice nuevo: uno sobre `id_producto` sería una copia del existente y el plan no puede cambiar respecto de él. `random_page_cost` es un parámetro del servidor y queda fuera de esta parte; se deja como observación (sección 8).

### 6.4 S4-A — facturación por categoría y mes

Agrega todo el histórico y hace `Seq Scan` en `detalle_pedido`, `pedido`, `producto` y `categoria`. El índice `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` sí contiene todas las columnas que S4-A usa de `detalle_pedido`: plan y tiempo no cambian (2.219 → 2.246 ms). El costo está en el `Hash Join`, la agregación y el ordenamiento externo (23 MB a disco), no en el acceso. **Descartado:** no cumple las condiciones 1 y 2. La mejora corresponde a la vista materializada de la Parte C, que OpenCode también señaló.

### 6.5 Lo que se verificó de las respuestas de OpenCode

Las respuestas se trataron como hipótesis y se contrastaron con el motor. Coinciden en lo esencial (ningún índice) pero tuvieron errores:

* **Cifras incorrectas:** «~20K productos activos» (son 50.010) y «5 categorías activas» (son 4); «+24-27 % de WAL» para el índice de P4-A, cifra sin sustento (el 26 y el 27 % del repo corresponden a otros índices); «+17 % de WAL», tomado del índice de C3 y no del analizado; una «query C del TP4» que no existe.
* **Generalización falsa** (sesiones 1, 2 y 4): «un `Seq Scan` siempre supera a cualquier índice cuando se lee toda la tabla». P4-B lo contradice: un `Index Only Scan` sobre un índice de 4,5 MB la deja en menos de la mitad del tiempo.
* **Imprecisión** (sesión 3): dice que `UNIQUE (id_pedido, id_producto)` cubre `id_producto`; empieza por `id_pedido`, así que solo `idx_detalle_pedido_id_producto` sirve para buscar por producto.

**Conclusión.** Un `Seq Scan` que lee la mayoría de la tabla es la elección correcta, no un síntoma. Ningún índice nuevo mejora estas tres consultas. Para S4-A el camino es la vista materializada de la Parte C; para P4-B, el ajuste de un parámetro de costo, no un índice.

## 7. Propuesta descartada por sobreindexación (consigna 6)

**Descartado: `CREATE INDEX idx_detalle_producto_pedido ON detalle_pedido (id_producto, id_pedido)`** (C3).

1. **Redundante.** Su primera columna es exactamente la del índice existente `idx_detalle_pedido_id_producto`; todo lo que sirve el nuevo, lo sirve el viejo. Un índice compuesto solo justifica su existencia si aporta algo que el prefijo no da.
2. **No aporta lo que promete.** La hipótesis era que `id_pedido` ayudaría al join. No ayuda: el join con `pedido` va por `pedido_pkey`, y `cantidad` y `precio_unitario` igual se leen del heap. Mismo plan, mismo costo estimado, mismos 27 bloques, tiempos indistinguibles.
3. **`id_pedido` ya está cubierto** por la restricción `UNIQUE (id_pedido, id_producto)`.
4. **Tiene costo en la tabla que más se escribe:** +17 % de WAL por cada `INSERT` en `detalle_pedido`, más el espacio y el mantenimiento en cada `UPDATE`/`DELETE`.

También se descartaron por el mismo criterio (índice que no cambia el plan pero se mantiene en cada escritura):

* `(id_cliente, fecha DESC)` en `pedido`: prefijo del existente, 24 filas, +26 % de WAL por `INSERT`.
* `(id_categoria, precio DESC) WHERE activo` en `producto`, sin `INCLUDE`: el planificador no lo usa, +27 % de WAL por `INSERT`.
* `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)` en `detalle_pedido` (P4-A): el planificador lo ignora, pesa 24 MB frente a 33 MB de tabla, sin mejora medible (743 → 735 ms) y +21 % de WAL por `INSERT` en la tabla más escrita. Además, su primera columna repite la de `idx_detalle_pedido_id_producto`.

## 8. Decisión final, riesgos y pendientes

**Se crea un solo índice**, `idx_producto_categoria_precio`, en [`indices.sql`](indices.sql).

**Riesgos del índice aceptado (a defender oralmente):**

1. **`UPDATE` de `stock`.** `stock` forma parte del índice (`INCLUDE`), así que cada actualización de stock obliga a mantenerlo (+50 % de tiempo por `UPDATE`, medido). Hoy los triggers de `restricciones.sql` solo *leen* el stock, no lo descuentan. Si en la Semana 6 los procedimientos descuentan stock en cada venta, ese costo pasa a ser por línea de venta y la decisión debe revisarse (alternativa: sacar `stock` del `INCLUDE`, a costa de volver a leer el heap para esa columna).
2. **Depende del autovacuum.** El `Index Only Scan` solo evita el heap si las páginas están marcadas como visibles; sobre una tabla con muchos cambios recientes aparecerán `Heap Fetches` y el beneficio baja hacia el del índice sin `INCLUDE`.
3. **Tamaño.** 3,3 MB frente a los 360 kB del índice del TP1 (9×). Irrelevante hoy, pero es un trade-off explícito.
4. **Redundancia con el heredado.** Con `idx_producto_categoria_precio`, `idx_producto_categoria_activo` (de `schema.sql`) queda redundante para esta consulta y se podría eliminar para ahorrar escritura. No se hace acá porque la consigna pide no modificar lo heredado; queda como pendiente para la próxima entrega. Las cifras de escritura de la sección 5 se midieron con **ambos** presentes (el peor caso).

5. **`random_page_cost` (P4-B).** Con el valor por defecto (4, pensado para discos mecánicos) el planificador prefiere el `Seq Scan` en la consulta de productos nunca vendidos; con 1,1 usa el índice existente y baja de 258 a 110 ms. Es un parámetro del servidor: no se modificó porque está fuera de esta parte (no es un índice) y afectaría a todas las consultas. Queda como observación para quien administre el servidor.

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

### GRANT sobre vista_usuario_reportes

Para que la vista pueda usarse en reportes sin dar acceso a la tabla usuario, se creo un rol de prueba
(`rol_reportes`, sin permisos por defecto) y se le otorgo SELECT unicamente sobre la vista:

    GRANT SELECT ON vista_usuario_reportes TO rol_reportes;

Probado en el motor (23/09/2026):

- `SELECT * FROM vista_usuario_reportes` con `rol_reportes` -> devuelve las 2 filas esperadas.
- `SELECT * FROM usuario` con el mismo rol -> `ERROR: permiso denegado a la tabla usuario`.

Confirma que el rol accede a los datos filtrados de la vista pero no puede leer la tabla base directamente.
Script en `views.sql`, al final del archivo.

---

# Parte C — Vista materializada

Vista materializada sobre el reporte de facturación por categoría y mes (Consulta A de la Semana 4,
`docs/informe_tp4_semana4.md`). Spec: `specs/spec_vista_materializada_parteC.md`. Implementación:
`materializadas.sql`.

**Base de medición:** `bd2_tp3` (base compartida del grupo), 50.011 productos, 200.005 pedidos y 499.263 detalles, `ANALYZE` corrido. Las mediciones se re-ejecutaron sobre esta base para que los tiempos sean comparables con los del resto del equipo.
Mediciones con `EXPLAIN (ANALYZE, BUFFERS)`.

> **Nota sobre la base.** Esta parte se midió sobre `practica_bd2` (500.151 detalles), que no es la base
> de la Parte A: esa se midió sobre el dump `bd2_tp3_actualizada_20260919.dump` (499.263 detalles). Los
> milisegundos de las dos partes no son comparables entre sí. Por ejemplo, la misma consulta de
> facturación por categoría y mes (S4-A en la Parte A) da 2.219 ms en el dump y 870 ms acá, en otra
> máquina y otra base. Lo que se compara dentro de esta parte (consulta contra vista) es consistente.
> No se re-midió sobre el dump.

| | Consulta sin materializar | Vista materializada |
|---|---|---|
| Tiempo de ejecucion | 410,104 ms | **0,028 ms** |
| Nodo principal del plan | `Parallel Hash Join` (2 workers) + `Sort` `external merge` (7.968 kB a disco) | `Seq Scan` sobre la vista |
| Filas devueltas | 100 (tras 398.846 filas intermedias) | 100 |

La mejora es de ~**14.647x**. El plan pasa de cruzar ~500.000 líneas de `detalle_pedido` y ~200.000
`pedido` con sort externo a disco para devolver 100 filas, a leer las 100 filas ya calculadas. La
diferencia de búferes lo confirma: la consulta original leyó 7.197 búferes compartidos y escribió 2.893
a disco temporal (el sort); la vista leyó **2 búferes**. El `rows=100` de la vista coincide con el
`rows=100` del `GroupAggregate` del plan original: se materializo exactamente el resultado que antes
exigía procesar ~400.000 filas.

**Tiempo del `REFRESH`:** `REFRESH MATERIALIZED VIEW CONCURRENTLY` corrió en **0,397 s** (0 filas
actualizadas: no hubo cambios entre el `CREATE` y el `REFRESH`). Es el costo que se paga a cambio: la
vista se lee en 0,028 ms pero refrescarla cuesta ~0,4 s. Conviene porque se lee muchísimas más veces de
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
