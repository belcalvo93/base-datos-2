# Base de datos — contexto del proyecto

## Motor y entorno

- **PostgreSQL** (versión compatible con `GENERATED ALWAYS AS IDENTITY` y `TIMESTAMPTZ`).
- El esquema se ejecuta desde `sql/schema.sql`; los datos de carga inicial desde `sql/datos.sql`.
- Los scripts son idempotentes: `schema.sql` elimina con `DROP … IF EXISTS … CASCADE` antes de recrear.

---

## Tablas

### `categoria`
Agrupa productos. Participación **parcial** respecto a `producto`: puede existir una categoría vacía (p. ej., recién creada).

| Columna | Tipo | Notas |
|---|---|---|
| `id_categoria` | `BIGINT` IDENTITY PK | Clave sustituta, generada por el motor |
| `nombre` | `VARCHAR(80)` NOT NULL UNIQUE | Nombre único de la categoría |
| `activo` | `BOOLEAN` NOT NULL DEFAULT TRUE | Baja lógica (ver sección aparte) |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT now() | Auditoría de creación |

---

### `cliente`
Personas que realizan pedidos. `email` es clave candidata (restricción UNIQUE, R6). `nombre` y `apellido` están separados para permitir búsquedas y ordenamientos independientes. `telefono` es opcional (`NULL` permitido).

| Columna | Tipo | Notas |
|---|---|---|
| `id_cliente` | `BIGINT` IDENTITY PK | |
| `nombre` | `VARCHAR(80)` NOT NULL | |
| `apellido` | `VARCHAR(80)` NOT NULL | |
| `email` | `VARCHAR(150)` NOT NULL UNIQUE | Clave candidata (R6) |
| `telefono` | `VARCHAR(30)` | Nullable |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT now() | |

---

### `producto`
Artículos disponibles para la venta. Participación **total** respecto a `categoria`: todo producto pertenece a exactamente una categoría (`id_categoria NOT NULL`).

| Columna | Tipo | Notas |
|---|---|---|
| `id_producto` | `BIGINT` IDENTITY PK | |
| `nombre` | `VARCHAR(120)` NOT NULL | |
| `descripcion` | `TEXT` | Nullable |
| `precio` | `NUMERIC(10,2)` NOT NULL CHECK ≥ 0 | Precio de lista vigente (R5) |
| `stock` | `INTEGER` NOT NULL DEFAULT 0 CHECK ≥ 0 | Stock actual (R5) |
| `activo` | `BOOLEAN` NOT NULL DEFAULT TRUE | Baja lógica (ver sección aparte) |
| `id_categoria` | `BIGINT` NOT NULL FK → `categoria` | `ON DELETE RESTRICT` |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT now() | |

---

### `pedido`
Cabecera de una orden de compra. Participación **total** respecto a `cliente`: todo pedido pertenece a un cliente registrado (`id_cliente NOT NULL`). La fecha usa `TIMESTAMPTZ` con `DEFAULT now()`; en la carga inicial se usan fechas fijas para que las consultas por rango sean estables al reejecutar.

| Columna | Tipo | Notas |
|---|---|---|
| `id_pedido` | `BIGINT` IDENTITY PK | |
| `fecha` | `TIMESTAMPTZ` NOT NULL DEFAULT now() | |
| `forma_pago` | `forma_pago_enum` NOT NULL | Ver sección ENUM |
| `id_cliente` | `BIGINT` NOT NULL FK → `cliente` | `ON DELETE RESTRICT` |

---

### `detalle_pedido`
Tabla intermedia N:M entre `pedido` y `producto`. Registra las líneas de cada pedido.

- Tiene clave sustituta propia (`id_detalle`) más una restricción `UNIQUE (id_pedido, id_producto)` para impedir que el mismo producto aparezca en más de una línea dentro del mismo pedido.
- `precio_unitario` congela el precio histórico en el momento de la venta (R4). Es independiente del `precio` vigente en `producto`.
- `subtotal` **no se almacena**: se recalcula siempre como `cantidad * precio_unitario`. Almacenarlo crearía una dependencia transitiva que rompería 3FN.

| Columna | Tipo | Notas |
|---|---|---|
| `id_detalle` | `BIGINT` IDENTITY PK | |
| `cantidad` | `INTEGER` NOT NULL CHECK > 0 | |
| `precio_unitario` | `NUMERIC(10,2)` NOT NULL CHECK ≥ 0 | Precio histórico congelado (R4) |
| `id_pedido` | `BIGINT` NOT NULL FK → `pedido` | `ON DELETE CASCADE` |
| `id_producto` | `BIGINT` NOT NULL FK → `producto` | `ON DELETE RESTRICT` |

---

## Convenciones de nombres

| Elemento | Convención | Ejemplo |
|---|---|---|
| Tablas | `snake_case`, singular | `detalle_pedido` |
| Columnas | `snake_case` | `precio_unitario` |
| PKs | `id_<tabla>` | `id_categoria` |
| FKs | `id_<tabla referenciada>` | `id_cliente` |
| Índices | `idx_<tabla>_<columna(s)>` | `idx_pedido_id_cliente` |
| Tipos ENUM | `<nombre>_enum` en minúsculas | `forma_pago_enum` |
| Valores ENUM | Mayúsculas | `'EFECTIVO'`, `'TARJETA'` |
| Auditoría de creación | `created_at TIMESTAMPTZ` | — |
| Baja lógica | `activo BOOLEAN` | — |

Los scripts SQL usan comentarios de bloque con separadores `-- ---` para delimitar cada objeto, y comentarios en línea para justificar cada decisión de diseño.

---

## Baja lógica (`activo`)

Las tablas `categoria` y `producto` implementan baja lógica mediante la columna `activo BOOLEAN NOT NULL DEFAULT TRUE`. **No se usa `DELETE` físico sobre estas entidades.**

Reglas de aplicación:

- **Dar de baja:** `UPDATE <tabla> SET activo = FALSE WHERE id_<tabla> = <id>;`
- **Consultas operativas:** siempre filtrar por `WHERE activo = TRUE` para excluir registros inactivos.
- **`ON DELETE RESTRICT`** en las FKs garantiza que una categoría con productos no pueda borrarse a nivel de base de datos; se da de baja lógicamente en su lugar.
- El producto `'Helado 1L'` y la categoría `'Congelados'` están inactivos en la carga inicial: sirven como casos de prueba del patrón.

El índice parcial `idx_producto_categoria_activo` soporta la consulta más frecuente sobre esta combinación:

```sql
-- Listar productos vigentes de una categoría
SELECT * FROM producto
WHERE id_categoria = <id> AND activo = TRUE;
```

---

## Tipo ENUM `forma_pago_enum`

Dominio cerrado con tres valores posibles:

| Valor | Descripción |
|---|---|
| `'EFECTIVO'` | Pago en efectivo |
| `'TARJETA'` | Pago con tarjeta de débito o crédito |
| `'TRANSFERENCIA'` | Transferencia bancaria |

Declaración:

```sql
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');
```

Se usa como tipo de la columna `pedido.forma_pago`. Elegir un ENUM en lugar de un `VARCHAR` con CHECK garantiza que la base de datos rechace cualquier valor fuera del dominio, y hace explícita la lista de opciones en el catálogo del motor.

Para agregar un valor nuevo al ENUM (requiere privilegios suficientes y es irreversible sin recrear el tipo):

```sql
ALTER TYPE forma_pago_enum ADD VALUE 'CRYPTO';
```

---

## Índices

| Índice | Tabla | Columna(s) | Motivo |
|---|---|---|---|
| `idx_pedido_id_cliente` | `pedido` | `id_cliente` | Historial de compras de un cliente |
| `idx_producto_categoria_activo` | `producto` | `id_categoria` WHERE `activo = TRUE` | Productos vigentes por categoría |
| `idx_detalle_pedido_id_producto` | `detalle_pedido` | `id_producto` | Reconstruir detalles de un pedido; ver en qué pedidos apareció un producto |

---

## Política de integridad referencial

| FK | `ON DELETE` | Justificación |
|---|---|---|
| `producto.id_categoria` → `categoria` | `RESTRICT` | Una categoría con productos no puede borrarse físicamente; se da de baja lógicamente |
| `pedido.id_cliente` → `cliente` | `RESTRICT` | Protege el historial de pedidos |
| `detalle_pedido.id_pedido` → `pedido` | `CASCADE` | Una línea de detalle no tiene sentido sin su pedido |
| `detalle_pedido.id_producto` → `producto` | `RESTRICT` | Protege el historial de ventas; el producto se da de baja lógicamente |

---

## Carga inicial (`datos.sql`)

- Las PKs **no se insertan explícitamente**: son `GENERATED ALWAYS AS IDENTITY`, el motor las asigna.
- Las FKs se resuelven con subconsultas sobre claves naturales (`nombre`, `email`) para que los scripts sean legibles y no dependan del orden de inserción ni de IDs hardcodeados.
- `detalle_pedido.precio_unitario` usa valores históricos menores al precio de lista vigente en algunos registros, para demostrar la independencia entre precio histórico y precio actual (R4).
- Las fechas de `pedido` son explícitas (no `now()`) para que las consultas por rango devuelvan resultados estables en cada reejecución.
