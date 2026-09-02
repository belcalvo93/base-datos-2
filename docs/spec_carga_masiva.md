# Spec — Script de carga masiva de datos (TP3)

**Archivo de salida:** `db/carga_masiva.sql`  
**Contexto:** Trabajo Práctico 3 — Unidad 2, optimización de consultas.  
**Base de trabajo:** bd2_tp3 (creada como copia de bd2_trabajo mediante `CREATE DATABASE bd2_tp3 TEMPLATE bd2_trabajo`, para preservar intacta la entrega del TP2)

---

## 1. Propósito

Generar un volumen de datos realista sobre el esquema del proyecto para que las
consultas del TP3 tengan masa suficiente donde demostrar diferencias de
rendimiento entre estrategias de indexación. El script es una adaptación del
`Genera_registros.sql` de la cátedra al esquema propio del proyecto.

---

## 2. Equivalencias con el script de cátedra

El script de referencia fue escrito sobre un esquema distinto. La tabla de
equivalencias siguiente fija las traducciones que aplica este script; no existe
ninguna otra.

| Script cátedra | Este proyecto | Notas |
|---|---|---|
| `usuario` | `cliente` | Misma semántica |
| `usuario_id` | `id_cliente` | Convención `id_<tabla>` |
| `categoria_id` | `id_categoria` | Ídem |
| `producto_id` | `id_producto` | Ídem |
| `pedido_id` | `id_pedido` | Ídem |
| `mail` | `email` | Columna renombrada |
| `celular` | — | No existe en este esquema; `telefono` es la columna equivalente (nullable) |
| `contrasena` | — | No existe; `cliente` no tiene campo de contraseña |
| `estado` (pedido) | — | No existe; el estado no forma parte del esquema de este proyecto |
| `subtotal` (detalle) | — | No se almacena; se recalcula como `cantidad * precio_unitario` (3FN, R4) |

---

## 3. Volúmenes objetivo

| Tabla | Filas a insertar |
|---|---|
| `categoria` | Las existentes (no se generan nuevas) |
| `producto` | 50.000 |
| `cliente` | 20.000 |
| `pedido` | 200.000 |
| `detalle_pedido` | Entre 1 y 4 líneas por pedido (200.000 – 800.000 filas) |

Las categorías no se generan porque las de la carga inicial (`datos.sql`) son
suficientes como dominio para asignar productos aleatorios. El script solo lee
sus `id_categoria` existentes.

---

## 4. Estructura del script

El script tiene **cuatro bloques de INSERT**, en el orden que respeta las
dependencias de claves foráneas:

```
1. INSERT INTO producto      (depende de categoria — ya existente)
2. INSERT INTO cliente
3. INSERT INTO pedido        (depende de cliente)
4. INSERT INTO detalle_pedido (depende de pedido y producto)
```

Cada bloque es un único `INSERT … SELECT` que genera todas las filas de una vez
usando `generate_series`. No se usan cursores ni bucles PL/pgSQL, en línea con
el enfoque del script de cátedra.

---

## 5. Especificación columna por columna

### 5.1 `producto`

| Columna | Valor generado | Justificación |
|---|---|---|
| `id_producto` | Asignado por el motor (`GENERATED ALWAYS AS IDENTITY`) | No se inserta explícitamente |
| `nombre` | `'Producto ' \|\| i` donde `i` es el número de serie | Identificador único legible |
| `descripcion` | `NULL` | Columna nullable; no aporta a las consultas de rendimiento |
| `precio` | `ROUND((random() * 990 + 10)::NUMERIC, 2)` | Rango $10–$1000, dos decimales |
| `stock` | `(random() * 150 + 50)::INTEGER` | Rango 50–200 (ver Decisión D2) |
| `activo` | `TRUE` | Fijo (ver Decisión D4) |
| `id_categoria` | `id_categoria` aleatorio de los existentes en `categoria` | Selección con `ORDER BY random() LIMIT 1` en subquery o array precargado |
| `created_at` | `DEFAULT now()` | No se inserta; el motor lo completa |

### 5.2 `cliente`

| Columna | Valor generado | Justificación |
|---|---|---|
| `id_cliente` | Asignado por el motor | No se inserta explícitamente |
| `nombre` | `'Nombre' \|\| i` | Unicidad garantizada por el número de serie |
| `apellido` | `'Apellido' \|\| i` | Ídem |
| `email` | `'cliente' \|\| i \|\| '@mail.com'` | Cumple UNIQUE; formato válido |
| `telefono` | `NULL` | Columna nullable; simplifica la generación |
| `created_at` | `DEFAULT now()` | No se inserta |

### 5.3 `pedido`

| Columna | Valor generado | Justificación |
|---|---|---|
| `id_pedido` | Asignado por el motor | No se inserta explícitamente |
| `fecha` | `now() - (random() * INTERVAL '2 years')` | Distribuye pedidos en los últimos 2 años; rango estable para consultas por fecha |
| `forma_pago` | Selección aleatoria entre `'EFECTIVO'`, `'TARJETA'`, `'TRANSFERENCIA'` | Cubre todo el dominio del ENUM `forma_pago_enum` |
| `id_cliente` | `id_cliente` aleatorio de los recién insertados | `ORDER BY random() LIMIT 1` o `(random() * 19999 + 1)::BIGINT` relativo al rango generado |

### 5.4 `detalle_pedido`

| Columna | Valor generado | Justificación |
|---|---|---|
| `id_detalle` | Asignado por el motor | No se inserta explícitamente |
| `cantidad` | `(random() * 3 + 1)::INTEGER` | Rango 1–4; máximo 4 es seguro con stock mínimo 50 (ver Decisión D2) |
| `precio_unitario` | `p.precio` del producto asociado mediante JOIN | Precio histórico congelado (R4); ver Decisión D3 |
| `id_pedido` | `id_pedido` del pedido de la serie actual | Cada pedido recibe entre 1 y 4 líneas |
| `id_producto` | `id_producto` aleatorio de los recién insertados | Seleccionado con `ORDER BY random()` para cada línea |

#### Mecánica de generación de líneas por pedido

Para producir entre 1 y 4 líneas por pedido se itera sobre cada `id_pedido`
cruzado con una serie de `generate_series(1, n_lineas)` donde `n_lineas =
(random() * 3 + 1)::INTEGER`. La restricción `UNIQUE (id_pedido, id_producto)`
impide repetir el mismo producto en el mismo pedido; la selección aleatoria de
producto por línea puede colisionar en casos extremos. La estrategia de manejo
se documenta en la Decisión D6.

---

## 6. Decisiones de diseño

### D1 — Uso de `random()` y `ORDER BY random()`
Se conserva el enfoque del script de cátedra. No se sustituye por funciones
deterministas ni semillas fijas. Esto mantiene coherencia metodológica con la
materia y produce distribuciones estadísticamente uniformes suficientes para el
análisis de rendimiento.

### D2 — `producto.stock` entre 50 y 200
El trigger `trg_verificar_stock_suficiente` rechaza cualquier línea de
`detalle_pedido` cuya `cantidad` supere el `stock` del producto. Con `cantidad`
máxima 4 y `stock` mínimo 50, ninguna inserción puede violar esa regla y la
carga masiva no aborta. Generar stock desde 0 —como hace el script de cátedra—
provocaría miles de rechazos aleatorios.

### D3 — `precio_unitario` tomado por JOIN desde `producto.precio`
En este esquema no existe trigger que complete `precio_unitario` automáticamente
ni columna `subtotal`. El precio histórico se congela en el momento de la venta
(R4). Para la carga masiva, tomar `p.precio` del JOIN garantiza que el valor
insertado sea válido (`>= 0`) y coherente, sin necesidad de generarlo por
separado. Esto es una simplificación aceptable porque el objetivo del script es
el volumen, no la fidelidad histórica.

### D4 — `activo = TRUE` en todos los registros generados
El trigger `trg_verificar_producto_activo` rechaza cualquier línea de
`detalle_pedido` que referencie un producto con `activo = FALSE`. Los registros
inactivos existentes en la base (`'Helado 1L'`, `'Congelados'`) son casos de
prueba del TP2 y no se modifican. Todos los productos y categorías generados en
este script tienen `activo = TRUE`.

### D5 — Sin `BEGIN` / `COMMIT` en el archivo
La transacción es responsabilidad de quien ejecuta, según el protocolo de
seguridad del proyecto (`protocolo_seguridad.md`). El archivo solo contiene
sentencias DML puras. El operador envuelve la ejecución en `BEGIN` / `ROLLBACK`
para una prueba previa y luego repite con `BEGIN` / `COMMIT`.

### D6 — Colisión en la restricción `UNIQUE (id_pedido, id_producto)`
Al asignar productos aleatoriamente por línea, existe probabilidad de que una
línea elija el mismo producto que una línea anterior del mismo pedido. Estrategia
adoptada: generar productos distintos por línea ordenando aleatoriamente la
tabla `producto` y asignando por posición dentro de la serie (línea 1 = rank 1,
línea 2 = rank 2, etc.). Esto elimina la colisión sin aumentar la complejidad
del script más allá de lo que exige la materia.

### D7 — Sin `CREATE INDEX` ni `ANALYZE` en el archivo
Esas operaciones se ejecutan en scripts separados, después de confirmar la
carga. Incluirlas aquí mezclaría la fase de carga con la fase de análisis de
rendimiento, que son los dos escenarios que el TP3 quiere comparar.

---

## 7. Prueba previa con volumen reducido

Antes de ejecutar la carga completa se debe medir el tiempo con un volumen
reducido para detectar problemas de rendimiento o errores de integridad sin
comprometer la base.

**Parametrización:** el script define, al inicio del archivo, un bloque de
comentarios marcado con `-- CONFIG` que indica los valores de `generate_series`
para cada escenario:

```sql
-- CONFIG: ajustar los tres generate_series para cada escenario.
-- En la prueba se reducen LOS TRES contadores, no solo el de pedidos.
-- El cuello de botella de ORDER BY random() depende del tamaño de la
-- tabla barrida: mantener 50.000 productos y 20.000 clientes como dominio
-- de selección daría una estimación de tiempo no representativa.
--
-- Escenarios:
--   Prueba chica:     5.000 /  2.000 /   5.000  → producto/cliente/pedido
--   Prueba mediana:  10.000 /  4.000 /  10.000  → producto/cliente/pedido
--   Producción:      50.000 / 20.000 / 200.000  → producto/cliente/pedido
--
-- Configuración ACTIVA (Producción):
--   generate_series(1, 50000)  → producto
--   generate_series(1, 20000)  → cliente
--   generate_series(1, 200000) → pedido
-- ============================================================
```

El operador edita únicamente esos tres números antes de ejecutar, según el
escenario elegido. No hay lógica condicional dentro del script: la
parametrización es manual y explícita, igual que en el script de cátedra.

> **Nota sobre la herramienta de ejecución.** Durante el TP2 y parte del TP3,
> `psql` estuvo bloqueado por Smart App Control de Windows y el trabajo se
> hizo con pgAdmin (las corridas de 5.000 y 10.000 se midieron por bloque con
> `EXPLAIN ANALYZE` en pgAdmin). Desde el 01/09/2026 `psql` volvió a funcionar
> y la corrida de producción se ejecutó con `psql` desde Git Bash.

**Procedimiento:**

1. Abrir `db/carga_masiva.sql` y ajustar los tres límites de `generate_series`
   al escenario activo del CONFIG (chica, mediana o producción).
2. Verificar `SELECT current_database();` → debe devolver `bd2_tp3`.
3. Ejecutar dentro de `BEGIN` / `ROLLBACK` y anotar el tiempo que reporta el
   cliente (`Time:` al final de cada sentencia en `psql`; «Execution time» del
   plan en pgAdmin).
4. Si el tiempo es aceptable y no hay errores, pasar al escenario de
   producción y ejecutar con `BEGIN` / `COMMIT`.

---

## 8. Interacción con los triggers del TP2

Los dos triggers activos sobre `detalle_pedido` se ejecutan en cada fila
insertada (`BEFORE INSERT FOR EACH ROW`). Con los valores del script respetan
las reglas:

| Trigger | Regla que aplica | Condición segura en este script |
|---|---|---|
| `trg_verificar_producto_activo` | `activo = TRUE` | Todos los productos generados tienen `activo = TRUE` (D4) |
| `trg_verificar_stock_suficiente` | `cantidad <= stock` | `cantidad` máxima 4, `stock` mínimo 50 (D2) |

Los triggers **no se deshabilitan** durante la carga. Hacerlo requeriría
privilegios de superusuario y violaría la intención de la materia de mantener
las restricciones activas. El diseño de los valores generados los hace
innecesarios.

---

## 9. Restricciones de integridad activas durante la carga

Además de los triggers, las siguientes restricciones del motor aplican a cada
fila insertada y el script las respeta:

| Restricción | Tabla | Cumplimiento |
|---|---|---|
| `CHECK (precio >= 0)` | `producto` | Precio generado en rango $10–$1000 |
| `CHECK (stock >= 0)` | `producto` | Stock generado en rango 50–200 |
| `CHECK (cantidad > 0)` | `detalle_pedido` | Cantidad generada en rango 1–4 |
| `CHECK (precio_unitario >= 0)` | `detalle_pedido` | Tomado del `precio` del producto via JOIN |
| `UNIQUE (id_pedido, id_producto)` | `detalle_pedido` | Resuelto por asignación posicional (D6) |
| `email UNIQUE` | `cliente` | `'cliente' \|\| i \|\| '@mail.com'` es único por construcción |
| FK `id_cliente` → `cliente` | `pedido` | `id_cliente` se toma de los insertados en el bloque anterior |
| FK `id_producto` → `producto` | `detalle_pedido` | `id_producto` se toma de los insertados en el bloque anterior |
| FK `id_pedido` → `pedido` | `detalle_pedido` | `id_pedido` se toma de los insertados en el bloque anterior |
| FK `id_categoria` → `categoria` | `producto` | `id_categoria` se toma de las categorías existentes |

---

## 10. Lo que el script NO hace

- No hace `TRUNCATE` ni `DELETE` de datos previos. La carga es aditiva.
- No modifica `producto.stock` al insertar detalles (validación sin descuento,
  igual que en el TP2).
- No inserta categorías nuevas.
- No genera registros con `activo = FALSE`.
- No contiene `CREATE INDEX`, `ANALYZE`, `BEGIN` ni `COMMIT`.
- No hardcodea IDs; los rangos de FKs se derivan dinámicamente de los bloques
  anteriores dentro del mismo script.

---

## 11. Criterios de aceptación

El script se considera correcto cuando cumple todos los criterios comunes y los
específicos del escenario ejecutado (los tres escenarios del CONFIG, sección 7).

### 11.1 Prueba chica (5.000 productos, 2.000 clientes, 5.000 pedidos)

Ejecutada dentro de `BEGIN` / `ROLLBACK`, sin errores, y con los conteos:

- `SELECT COUNT(*) FROM producto` → valor anterior + 5.000
- `SELECT COUNT(*) FROM cliente` → valor anterior + 2.000
- `SELECT COUNT(*) FROM pedido` → valor anterior + 5.000
- `SELECT COUNT(*) FROM detalle_pedido` → entre 5.000 y 20.000

### 11.2 Prueba mediana (10.000 productos, 4.000 clientes, 10.000 pedidos)

Ejecutada dentro de `BEGIN` / `ROLLBACK`, sin errores, y con los conteos:

- `SELECT COUNT(*) FROM producto` → valor anterior + 10.000
- `SELECT COUNT(*) FROM cliente` → valor anterior + 4.000
- `SELECT COUNT(*) FROM pedido` → valor anterior + 10.000
- `SELECT COUNT(*) FROM detalle_pedido` → entre 10.000 y 40.000

### 11.3 Producción (50.000 productos, 20.000 clientes, 200.000 pedidos)

Ejecutada dentro de `BEGIN` / `COMMIT`, sin errores, y con los conteos:

- `SELECT COUNT(*) FROM producto` → valor anterior + 50.000
- `SELECT COUNT(*) FROM cliente` → valor anterior + 20.000
- `SELECT COUNT(*) FROM pedido` → valor anterior + 200.000
- `SELECT COUNT(*) FROM detalle_pedido` → entre 200.000 y 800.000

### 11.4 Criterios comunes (los tres escenarios)

1. No existe ningún `id_pedido` en `detalle_pedido` sin su correspondiente fila
   en `pedido`.
2. No existe ningún `precio_unitario` NULL ni negativo en `detalle_pedido`.
3. Todos los productos generados tienen `activo = TRUE` y `stock >= 50`.

### 11.5 Verificación de la distribución

Los conteos de 11.1–11.3 demuestran volumen, no distribución. La distribución
se verifica con consultas restringidas a las filas recién insertadas: cada
bloque del script inserta las filas más nuevas, así que el corte se hace con
`ORDER BY <pk> DESC LIMIT <n>` con `<n>` igual a la cantidad insertada (las
consultas quedaron armadas en `db/verificacion_carga_masiva.sql`).

`count(DISTINCT ...)` no sirve sobre columnas con pocos valores: con 5
categorías, `count(DISTINCT id_categoria)` da 5 esté la distribución rota o no.

- **`producto.id_categoria`** — agrupar por categoría las últimas `<n>` filas
  de `producto`. Correcto: repartido entre las 5 categorías. Roto: una sola
  categoría concentra todas las filas (el subquery no correlacionado se
  evalúa como InitPlan, una sola vez). En producción quedó repartido entre
  las 5.
- **`pedido.id_cliente`** — `count(DISTINCT id_cliente)` sobre las últimas
  `<n>` filas de `pedido`. En producción: **20.004** de 20.005 clientes.
- **`detalle_pedido.id_producto`** — `count(DISTINCT id_producto)` sobre las
  filas de detalle de los últimos pedidos. En producción: **50.008** de
  50.011 productos (los 3 faltantes son los preexistentes que el filtro
  `activo = TRUE AND stock >= 4` excluye).

## Mediciones — corrida de 5.000 (01/09/2026)

Base `bd2_tp3`, recreada desde `bd2_trabajo`. Todo dentro de
`BEGIN` / `ROLLBACK`, medido con `EXPLAIN ANALYZE` por bloque en pgAdmin.

### Antes de corregir el LATERAL

| Bloque | Filas | Tiempo |
|---|---|---|
| 1 — producto | 5.000 | 91,4 ms |
| 2 — cliente | 2.000 | 32,1 ms |
| 3 — pedido | 5.000 | 83,1 ms |
| 4 — detalle_pedido | 12.511 | 704,9 ms |
| **Total** | | **911,5 ms** |

Segunda corrida de los mismos bloques: 76,1 / 22,1 / 60,0 ms. La variación
entre corridas idénticas ronda el 15%, así que solo se consideran
significativas las diferencias muy superiores a ese margen.

### Hallazgo — nodo Materialize en el bloque 4

El plan mostró `Materialize (rows=4 loops=5005)` sobre un hijo con `loops=1`:
el subquery del `CROSS JOIN LATERAL` se evaluaba **una sola vez** y los 12.511
detalles se repartían entre los mismos 4 productos. Causa: el subquery no
referenciaba ninguna columna de `lpp`, así que el planificador lo trató como
independiente de la fila externa. `random()` no lo impide, porque la decisión
de materializar se toma antes de ejecutar.

Verificación empírica: `count(DISTINCT id_producto)` sobre `detalle_pedido`
daba **13**.

### Corrección aplicada

1. `ORDER BY random() + lpp.id_pedido * 0` — la referencia a `lpp` correlaciona
   el subquery y fuerza la reejecución por fila. `* 0` no altera el orden.
2. `WHERE activo = TRUE AND stock >= 4` — sin este filtro el sorteo alcanza
   productos preexistentes de `bd2_trabajo` que violan los triggers del TP2.
   Dos fallas reales durante la prueba: producto id 2 (`stock = 3`) contra
   `trg_verificar_stock_suficiente`, y producto id 10 (`activo = FALSE`) contra
   `trg_verificar_producto_activo`. El umbral 4 está atado a la cantidad máxima
   por línea (D2): si cambia una, cambia el otro.

### Después de corregir

| Métrica | Antes | Después |
|---|---|---|
| Bloque 4 | 704,9 ms | 9.891,1 ms |
| Productos distintos en detalle | 13 | 4.590 |
| Total de detalles | 12.511 | 12.493 |

Plan posterior: desaparece `Materialize`; `Seq Scan on producto` pasa a
`loops=5005`. `Filter: (activo AND (stock >= 4))` con
`Rows Removed by Filter: 3` — los tres productos preexistentes no vendibles.

El costo de obtener datos distribuidos es 14x en tiempo de carga. Se acepta:
con 13 productos distintos, `detalle_pedido.id_producto` no tendría
selectividad y la Parte 2 mediría un artefacto de la carga en lugar del
comportamiento real de un índice.

### Reparto del tiempo del bloque 4 (corrida de 5.000, corregida)

| Concepto | Tiempo |
|---|---|
| FK a pedido | 137,0 ms |
| FK a producto | 119,0 ms |
| `trg_verificar_producto_activo` | 201,4 ms |
| `trg_verificar_stock_suficiente` | 97,1 ms |
| Plan (Nested Loop + inserción) | resto |

En la corrida previa (sin corregir) los triggers eran el 74% del total. Tras la
corrección pasan a ser una fracción menor: el peso se desplaza al `Seq Scan`
repetido, que ahora sí se ejecuta por pedido.

## Mediciones — corrida de 10.000 (prueba mediana, con las tres correcciones)

Medido por bloque con `EXPLAIN ANALYZE` en pgAdmin (psql bloqueado por Smart
App Control; ver §7). Escenario de prueba mediana: 10.000 productos, 4.000
clientes, 10.000 pedidos, con las tres correcciones ya aplicadas. Esta corrida
es la misma que se usó para comparar la variante A contra la B del bloque 3
(variante A: bloque 3 = 9.676 ms; ver DUIA, uso 9).

| Bloque | Tiempo |
|---|---|
| 1 — producto | 276 ms |
| 2 — cliente | 39 ms |
| 3 — pedido | 9.676 ms |
| 4 — detalle_pedido | 38.193 ms |

## Mediciones — corrida de producción (01/09/2026, psql)

Ejecución completa de los cuatro bloques con `BEGIN` / `COMMIT` desde `psql`
en Git Bash sobre `bd2_tp3`. Desde esta fecha `psql` volvió a estar operativo
(ver §7). Escenario de producción: 50.000 productos, 20.000 clientes, 200.000
pedidos.

| Bloque | Tiempo | Filas insertadas |
|---|---|---|
| 1 — producto | 1,13 s | 50.000 |
| 2 — cliente | 0,27 s | 20.000 |
| 3 — pedido | 12:31,9 | 200.000 |
| 4 — detalle_pedido | 47:35,3 | 499.254 |
| **Total (suma bloques 1–4)** | **1:00:08** | |

El Total (1:00:08) es la **suma aritmética** de los cuatro tiempos por
sentencia que reportó `psql`; no es un tiempo medido de la transacción
completa (no se registró el transcurrido total del BEGIN / COMMIT). El bloque
4 concentra **~79%** del total (2855,3 s de 3608,6 s): es el costo del
`ORDER BY random()` reejecutado por pedido, el mismo peso que ya se documentó
en la corrida de 5.000.

Conteos finales tras el COMMIT (la carga es aditiva sobre los datos de
`datos.sql`):

| Tabla | Conteo final | Incremento |
|---|---|---|
| categoria | 5 | — |
| cliente | 20.005 | +20.000 |
| producto | 50.011 | +50.000 |
| pedido | 200.005 | +200.000 |
| detalle_pedido | 499.263 | +499.254 |

Distribución verificada tras el COMMIT:

- **`pedido.id_cliente`** — 20.004 clientes distintos con pedidos, de los
  20.005 existentes.
- **`detalle_pedido.id_producto`** — 50.008 productos distintos vendidos, de
  los 50.011. Los 3 que faltan son los preexistentes que el filtro
  `activo = TRUE AND stock >= 4` excluye (los mismos 3 que el `Filter` del
  bloque 4 descarta: `Rows Removed by Filter: 3` en la corrida de 5.000).
- **`producto.id_categoria`** — repartido entre las 5 categorías.

Operaciones posteriores a la carga:

- `ANALYZE` sobre las cinco tablas, después del COMMIT.
- Respaldo: `db/backups/bd2_tp3_poblada.dump` (9 MB).