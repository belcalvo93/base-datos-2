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
-- CONFIG: ajustar los tres generate_series para la prueba reducida.
-- En la prueba se reducen LOS TRES contadores, no solo el de pedidos.
-- El cuello de botella de ORDER BY random() depende del tamaño de la
-- tabla barrida: mantener 50.000 productos y 20.000 clientes como dominio
-- de selección daría una estimación de tiempo no representativa.
--
-- Prueba reducida:
--   generate_series(1, 500)   → producto
--   generate_series(1, 200)   → cliente
--   generate_series(1, 500)   → pedido
--
-- Producción:
--   generate_series(1, 50000)  → producto
--   generate_series(1, 20000)  → cliente
--   generate_series(1, 200000) → pedido
```

El operador edita únicamente esos tres números antes de ejecutar. No hay lógica
condicional dentro del script: la parametrización es manual y explícita, igual
que en el script de cátedra.

**Procedimiento:**

1. Abrir `db/carga_masiva.sql` y ajustar los tres límites de `generate_series`
   a los valores de prueba reducida.
2. Verificar `SELECT current_database();` → debe devolver `bd2_tp3`.
3. Ejecutar dentro de `BEGIN` / `ROLLBACK` y anotar el tiempo que reporta el
   cliente (`psql` muestra `Time:` al final de cada sentencia).
4. Si el tiempo es aceptable y no hay errores, restaurar los valores de
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
específicos del escenario ejecutado.

### 11.1 Prueba reducida (500 productos, 200 clientes, 500 pedidos)

Ejecutada dentro de `BEGIN` / `ROLLBACK`, sin errores, y con los conteos:

- `SELECT COUNT(*) FROM producto` → valor anterior + 500
- `SELECT COUNT(*) FROM cliente` → valor anterior + 200
- `SELECT COUNT(*) FROM pedido` → valor anterior + 500
- `SELECT COUNT(*) FROM detalle_pedido` → entre 500 y 2.000

### 11.2 Producción (50.000 productos, 20.000 clientes, 200.000 pedidos)

Ejecutada dentro de `BEGIN` / `COMMIT`, sin errores, y con los conteos:

- `SELECT COUNT(*) FROM producto` → valor anterior + 50.000
- `SELECT COUNT(*) FROM cliente` → valor anterior + 20.000
- `SELECT COUNT(*) FROM pedido` → valor anterior + 200.000
- `SELECT COUNT(*) FROM detalle_pedido` → entre 200.000 y 800.000

### 11.3 Criterios comunes (ambos escenarios)

3. No existe ningún `id_pedido` en `detalle_pedido` sin su correspondiente fila
   en `pedido`.
4. No existe ningún `precio_unitario` NULL ni negativo en `detalle_pedido`.
5. Todos los productos generados tienen `activo = TRUE` y `stock >= 50`.
