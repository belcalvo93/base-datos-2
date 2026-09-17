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
