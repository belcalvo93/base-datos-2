# Spec — Tabla `usuario` y vista `vista_usuario_reportes` (TP5 Parte B)

**Archivos de implementación:**
- Tabla y tipo: `food-store/schema.sql` (sección nueva al final, sin
  tocar las tablas existentes)
- Vista: `food-store/views.sql`

**Contexto:** la consigna del TP5 (punto 4.2, Parte B) pide una vista
que oculte la columna `contraseña` de una tabla de login. El esquema
propio de Food Store no tiene ese caso de uso: `cliente` no maneja
autenticación. Por indicación directa del profesor Sergio Neira
(documentada en `docs/duia/duia_parte5.md`, sección "Decisiones de
diseño"), se agrega una tabla `usuario` separada de `cliente`, con
columnas `contrasena` y `rol`. Las tablas existentes no se modifican.

---

## Nota sobre divergencias de convención

El DDL de esta sección fue confirmado por la cátedra y se reproduce
exactamente. Dos puntos divergen de las convenciones establecidas en
`food-store/schema.sql`; ambos son intencionales:

| Elemento | Convención del proyecto | En esta spec | Motivo |
|---|---|---|---|
| PK | `id_<tabla>` (ej. `id_cliente`) | `id` | DDL exacto confirmado por el profesor |
| Tipo ENUM | `<nombre>_enum` (ej. `forma_pago_enum`) | `rol` (sin sufijo) | DDL exacto confirmado por el profesor |

No se adaptaron al estilo del proyecto para no desviarse del DDL
oficial de la cátedra. Si en una defensa oral se pregunta por estas
diferencias, la respuesta es: "el DDL fue confirmado explícitamente
por el profesor; se respetó tal cual."

---

## 1. Tipo ENUM `rol`

Dominio cerrado con dos valores posibles:

| Valor | Descripción |
|---|---|
| `'USUARIO'` | Usuario estándar sin privilegios de administración |
| `'ADMIN'` | Usuario con privilegios de administración |

Declaración:

```sql
CREATE TYPE rol AS ENUM ('USUARIO', 'ADMIN');
```

Se usa como tipo de la columna `usuario.rol`. Al igual que
`forma_pago_enum`, usar un ENUM en lugar de `VARCHAR` con CHECK
garantiza que el motor rechace cualquier valor fuera del dominio y
hace explícita la lista de opciones en el catálogo.

El script es idempotente: `DROP TYPE IF EXISTS rol CASCADE` antes de
`CREATE TYPE`.

---

## 2. Tabla `usuario`

### DDL confirmado por la cátedra

```sql
CREATE TYPE rol AS ENUM ('USUARIO', 'ADMIN');

CREATE TABLE usuario (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(80)  NOT NULL,
    apellido    VARCHAR(80)  NOT NULL,
    mail        VARCHAR(120) NOT NULL UNIQUE,
    celular     VARCHAR(30),
    contrasena  VARCHAR(255) NOT NULL,
    rol         rol          NOT NULL DEFAULT 'USUARIO',
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
```

### Columnas

| Columna | Tipo | Notas |
|---|---|---|
| `id` | `BIGINT` IDENTITY PK | Clave sustituta generada por el motor. Diverge de la convención `id_<tabla>` del proyecto (ver nota) |
| `nombre` | `VARCHAR(80)` NOT NULL | |
| `apellido` | `VARCHAR(80)` NOT NULL | |
| `mail` | `VARCHAR(120)` NOT NULL UNIQUE | Clave candidata; análogo a `email` en `cliente` |
| `celular` | `VARCHAR(30)` | Nullable; análogo a `telefono` en `cliente` |
| `contrasena` | `VARCHAR(255)` NOT NULL | Almacena el hash de la contraseña; nunca el valor en texto plano |
| `rol` | `rol` NOT NULL DEFAULT `'USUARIO'` | ENUM con valores `'USUARIO'` y `'ADMIN'` |
| `eliminado` | `BOOLEAN` NOT NULL DEFAULT FALSE | Baja lógica. Semánticamente equivalente a `activo = TRUE` en `categoria` y `producto`, con lógica invertida: `eliminado = FALSE` significa vigente |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT now() | Auditoría de creación; igual que en todas las tablas del proyecto |

### Baja lógica

`usuario` implementa baja lógica mediante `eliminado BOOLEAN NOT NULL
DEFAULT FALSE`. La lógica está invertida respecto a `categoria` y
`producto` (que usan `activo = TRUE` para indicar vigencia), pero el
efecto es equivalente:

- **Usuario vigente:** `eliminado = FALSE`
- **Usuario dado de baja:** `UPDATE usuario SET eliminado = TRUE WHERE id = <id>;`
- **Consultas operativas:** filtrar por `WHERE eliminado = FALSE`

No se usa `DELETE` físico sobre `usuario`.

### Relación con las tablas existentes

`usuario` es una tabla independiente, sin FK hacia `cliente`, `pedido`
ni ninguna otra tabla del esquema. Representa un actor de sistema
(login) distinto del actor de negocio (`cliente`). No se modifica
ninguna tabla existente.

### Idempotencia

El bloque en `schema.sql` incluye:

```sql
DROP TABLE IF EXISTS usuario CASCADE;
DROP TYPE  IF EXISTS rol     CASCADE;
```

antes de los `CREATE`, en línea con el patrón del resto del archivo.

---

## 3. Vista `vista_usuario_reportes`

### Propósito

Exponer los datos de `usuario` para reportes y administración,
ocultando la columna `contrasena`. Esta vista cumple el criterio de
seguridad del punto 4 de la Parte B: quien consulta la vista puede
ver todos los atributos operativos del usuario (incluyendo `rol` y
`eliminado`) sin acceder al hash de la contraseña.

### Consulta base

```sql
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM usuario
WHERE eliminado = FALSE;
```

Solo se exponen usuarios vigentes (`eliminado = FALSE`). No se incluye
`contrasena`.

### Columnas de la vista

| Columna | Tabla origen | Tipo origen | Notas |
|---|---|---|---|
| `id` | `usuario` | `BIGINT` | PK de `usuario` |
| `nombre` | `usuario` | `VARCHAR(80) NOT NULL` | |
| `apellido` | `usuario` | `VARCHAR(80) NOT NULL` | |
| `mail` | `usuario` | `VARCHAR(120) NOT NULL` | |
| `celular` | `usuario` | `VARCHAR(30)` | Nullable |
| `rol` | `usuario` | `rol NOT NULL` | `'USUARIO'` o `'ADMIN'` |
| `eliminado` | `usuario` | `BOOLEAN NOT NULL` | Siempre `FALSE` en esta vista (filtro del WHERE) |
| `created_at` | `usuario` | `TIMESTAMPTZ NOT NULL` | |

No se incluye `contrasena`. Es la única columna excluida
intencionalmente, y es el propósito central de la vista.

### Restricciones de implementación

- Las columnas se listan explícitamente; no se usa `SELECT *`.
- Vista de solo lectura: sin `WITH CHECK OPTION`, sin trigger `INSTEAD OF`.
- Idempotente: `CREATE OR REPLACE VIEW vista_usuario_reportes AS ...`

### Criterio de aceptación

La vista es correcta cuando ambas direcciones del `EXCEPT` devuelven
exactamente 0 filas:

```sql
-- Dirección 1: filas en la vista que no están en la consulta base
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM vista_usuario_reportes
EXCEPT
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM usuario
WHERE eliminado = FALSE;

-- Dirección 2: filas en la consulta base que no están en la vista
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM usuario
WHERE eliminado = FALSE
EXCEPT
SELECT id, nombre, apellido, mail, celular, rol, eliminado, created_at
FROM vista_usuario_reportes;
```

Ambas consultas deben devolver `(0 rows)`.

### Verificación adicional — columna `contrasena` ausente

Confirmar que la vista no expone `contrasena`:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'vista_usuario_reportes'
  AND column_name = 'contrasena';
```

Debe devolver `(0 rows)`.

---

## 4. Datos de prueba

Tres usuarios de ejemplo para verificar la vista. Los valores de
`contrasena` son hashes placeholder no legibles (hex aleatorio), nunca
texto plano — coherentes con el propósito de la columna (almacenar el
hash, jamás la contraseña).

| mail | rol | eliminado | Rol en la verificación |
|---|---|---|---|
| `n.gonzalez@foodstore.com` | `ADMIN` | `FALSE` | Cobertura del valor ADMIN del ENUM |
| `m.rios@foodstore.com` | `USUARIO` | `FALSE` | Cobertura del valor USUARIO del ENUM |
| `s.luna@foodstore.com` | `USUARIO` | `TRUE` | Prueba que la vista filtra eliminados (no aparece en ningún lado del EXCEPT) |

```sql
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol, eliminado)
VALUES
    ('Nicole', 'González', 'n.gonzalez@foodstore.com', '+54 9 11 5555-0101',
     '3f7a9c1e5b2d4f6a8c0e1d2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b', 'ADMIN', FALSE),
    ('Matías', 'Ríos',     'm.rios@foodstore.com',     '+54 9 11 5555-0102',
     '9c3e2d1f4a6b8c5d7e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d', 'USUARIO', FALSE),
    ('Sofía',  'Luna',     's.luna@foodstore.com',     '+54 9 11 5555-0103',
     'b0a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c', 'USUARIO', TRUE);
```
