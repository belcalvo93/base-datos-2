# Specs de vistas — TP5

**Archivo de implementación:** `food-store/views.sql`
**Contexto del TP:** Parte B (vistas obligatorias) y extras del proyecto
Food Store.

Las vistas se crean con `CREATE OR REPLACE VIEW` para que el script sea
idempotente. Ninguna spec de esta sección incluye `BEGIN`, `COMMIT`,
`CREATE INDEX` ni `ANALYZE`: esas operaciones son responsabilidad de
quien ejecuta, según el protocolo de seguridad del proyecto.

---

## Vista 1 — `vista_cliente_completo`

### Propósito

Exponer el perfil completo de contacto de cada cliente para uso interno.
Incluye email y teléfono, que son datos sensibles ausentes en
`vista_pedidos_cliente`. El contraste entre ambas vistas es intencional:
`vista_pedidos_cliente` oculta esos campos porque su caso de uso es
operativo (listar pedidos con datos mínimos del comprador);
`vista_cliente_completo` los expone porque su caso de uso es
administrativo (soporte, verificación de datos, comunicaciones directas).

### Consulta base

```sql
SELECT id_cliente, nombre, apellido, email, telefono
FROM cliente;
```

No aplica filtro de borrado lógico: la tabla `cliente` no tiene columna
`activo`. Todos los clientes registrados son visibles.

### Columnas de la vista

| Columna | Tipo origen | Notas |
|---|---|---|
| `id_cliente` | `BIGINT` | PK de `cliente` |
| `nombre` | `VARCHAR(80)` NOT NULL | |
| `apellido` | `VARCHAR(80)` NOT NULL | |
| `email` | `VARCHAR(150)` NOT NULL | Clave candidata (UNIQUE en la tabla base) |
| `telefono` | `VARCHAR(30)` | Nullable |

No se incluye `created_at`. No se agrega ninguna columna derivada ni
calculada.

### Restricciones de implementación

- Las columnas se listan explícitamente; no se usa `SELECT *`.
- Vista de solo lectura: sin `WITH CHECK OPTION`, sin trigger `INSTEAD OF`.
- Idempotente: `CREATE OR REPLACE VIEW vista_cliente_completo AS ...`

### Criterio de aceptación

La vista es correcta cuando ambas direcciones del `EXCEPT` devuelven
exactamente 0 filas:

```sql
-- Dirección 1: filas en la vista que no están en la tabla
SELECT id_cliente, nombre, apellido, email, telefono
FROM vista_cliente_completo
EXCEPT
SELECT id_cliente, nombre, apellido, email, telefono
FROM cliente;

-- Dirección 2: filas en la tabla que no están en la vista
SELECT id_cliente, nombre, apellido, email, telefono
FROM cliente
EXCEPT
SELECT id_cliente, nombre, apellido, email, telefono
FROM vista_cliente_completo;
```

Ambas consultas deben devolver `(0 rows)`.

---

## Vista 2 — `vista_pedidos_cliente`

### Propósito

Mostrar cada pedido junto con el nombre y apellido del cliente que lo
realizó, sin exponer datos sensibles (email, teléfono). Esta vista
cumple el criterio de seguridad del punto 4 de la Parte B: el caso de
uso es operativo (consultar pedidos con identificación mínima del
comprador), no administrativo. Para acceso completo al perfil de
contacto existe `vista_cliente_completo`.

### Consulta base

```sql
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente;
```

El JOIN es `INNER JOIN`: `pedido.id_cliente` es `NOT NULL` (FK con
participación total), por lo que todo pedido tiene exactamente un
cliente. No se pierden filas.

No aplica filtro de borrado lógico: ni `pedido` ni `cliente` tienen
columna `activo`.

### Columnas de la vista

| Columna | Tabla origen | Tipo origen | Notas |
|---|---|---|---|
| `id_pedido` | `pedido` | `BIGINT` | PK de `pedido` |
| `fecha` | `pedido` | `TIMESTAMPTZ NOT NULL` | Fecha y hora del pedido |
| `forma_pago` | `pedido` | `forma_pago_enum NOT NULL` | `EFECTIVO`, `TARJETA` o `TRANSFERENCIA` |
| `nombre` | `cliente` | `VARCHAR(80) NOT NULL` | Nombre del cliente |
| `apellido` | `cliente` | `VARCHAR(80) NOT NULL` | Apellido del cliente |

No se incluye `id_cliente`, `email`, `telefono` ni `created_at`.
No se agrega ninguna columna derivada ni calculada.

### Restricciones de implementación

- Las columnas se listan explícitamente; no se usa `SELECT *`.
- Vista de solo lectura: sin `WITH CHECK OPTION`, sin trigger `INSTEAD OF`.
- Idempotente: `CREATE OR REPLACE VIEW vista_pedidos_cliente AS ...`

### Criterio de aceptación

La vista es correcta cuando ambas direcciones del `EXCEPT` devuelven
exactamente 0 filas:

```sql
-- Dirección 1: filas en la vista que no están en la consulta base
SELECT id_pedido, fecha, forma_pago, nombre, apellido
FROM vista_pedidos_cliente
EXCEPT
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente;

-- Dirección 2: filas en la consulta base que no están en la vista
SELECT p.id_pedido, p.fecha, p.forma_pago, c.nombre, c.apellido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
EXCEPT
SELECT id_pedido, fecha, forma_pago, nombre, apellido
FROM vista_pedidos_cliente;
```

Ambas consultas deben devolver `(0 rows)`.

---

## Vista 3 — `vista_productos_vigentes`

### Propósito

Mostrar cada producto activo junto con el nombre de su categoría,
aplicando el filtro de vigencia en ambas tablas. La vista expone
únicamente productos y categorías con `activo = TRUE`: un producto
cuya categoría esté dada de baja no aparece, aunque el producto en sí
esté activo. Este comportamiento es correcto por diseño: una categoría
inactiva implica que ese segmento ya no está operativo.

### Consulta base

```sql
SELECT p.id_producto,
       p.nombre,
       p.precio,
       p.stock,
       c.nombre AS nombre_categoria
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.activo = TRUE
  AND c.activo = TRUE;
```

El JOIN es `INNER JOIN`: `producto.id_categoria` es `NOT NULL` (FK con
participación total), por lo que todo producto tiene exactamente una
categoría. El doble filtro `WHERE p.activo = TRUE AND c.activo = TRUE`
aplica la baja lógica de ambas tablas.

### Columnas de la vista

| Columna | Tabla origen | Tipo origen | Notas |
|---|---|---|---|
| `id_producto` | `producto` | `BIGINT` | PK de `producto` |
| `nombre` | `producto` | `VARCHAR(120) NOT NULL` | Nombre del producto |
| `precio` | `producto` | `NUMERIC(10,2) NOT NULL` | Precio de lista vigente |
| `stock` | `producto` | `INTEGER NOT NULL` | Stock actual |
| `nombre_categoria` | `categoria` | `VARCHAR(80) NOT NULL` | Alias de `categoria.nombre`; evita ambigüedad con `producto.nombre` |

No se incluye `descripcion`, `activo`, `id_categoria` ni `created_at`
de ninguna de las dos tablas. No se agrega ninguna columna derivada ni
calculada.

### Restricciones de implementación

- Las columnas se listan explícitamente; no se usa `SELECT *`.
- El alias `nombre_categoria` se declara en la consulta de la vista, no
  como alias de columna en la cabecera `CREATE VIEW`.
- Vista de solo lectura: sin `WITH CHECK OPTION`, sin trigger `INSTEAD OF`.
- Idempotente: `CREATE OR REPLACE VIEW vista_productos_vigentes AS ...`

### Criterio de aceptación

La vista es correcta cuando ambas direcciones del `EXCEPT` devuelven
exactamente 0 filas:

```sql
-- Dirección 1: filas en la vista que no están en la consulta base
SELECT id_producto, nombre, precio, stock, nombre_categoria
FROM vista_productos_vigentes
EXCEPT
SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.activo = TRUE AND c.activo = TRUE;

-- Dirección 2: filas en la consulta base que no están en la vista
SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.activo = TRUE AND c.activo = TRUE
EXCEPT
SELECT id_producto, nombre, precio, stock, nombre_categoria
FROM vista_productos_vigentes;
```

Ambas consultas deben devolver `(0 rows)`.
