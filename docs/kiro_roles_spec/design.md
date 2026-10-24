# Diseño de Roles PostgreSQL — Food Store TP U5

## Justificación de roles (una oración cada uno)

| Rol | Justificación |
|-----|---------------|
| `rol_app_lectura` | Permite a la aplicación web leer productos vigentes sin acceso a datos de clientes, pedidos ni usuarios. |
| `rol_app_escritura` | Permite a la aplicación web registrar pedidos y sus detalles solo mediante el procedimiento transaccional, con consulta directa (SELECT) de pedidos y líneas pero sin INSERT ni UPDATE directo. |
| `rol_soporte` | Permite a personal de soporte ver identificación de usuarios (nombre, mail, rol) y el resumen de pedidos, sin acceso a contraseña ni teléfono. |
| `rol_reportes` | Permite a herramientas de BI leer datos agregados de ventas por categoría y mes, sin datos personales de clientes ni usuarios. |
| `app_web` | Login para la aplicación web; hereda permisos de lectura y escritura para operar el negocio. |
| `admin_datos` | Login con privilegios de creación de roles y bases de datos para administración, sin ser superusuario. |
| `rol_reportes_login` | Login dedicado para herramientas de reportes; miembro del grupo de reportes para acceso exclusivo a datos agregados. |

---

## Matriz rol × objeto × privilegio

| Rol | Objeto | Privilegio | Justificación |
|-----|--------|------------|---------------|
| `rol_app_lectura` | `public` (esquema) | USAGE | Necesario para acceder a cualquier objeto |
| `rol_app_lectura` | `vista_productos_vigentes` | SELECT | Catálogo público de productos |
| `rol_app_escritura` | `public` (esquema) | USAGE | Necesario para acceder a cualquier objeto |
| `rol_app_escritura` | `pedido` | SELECT | Consulta de pedidos; el alta es solo vía `registrar_pedido()` |
| `rol_app_escritura` | `detalle_pedido` | SELECT | Consulta de líneas; el alta es solo vía `registrar_pedido()` |
| `rol_app_escritura` | `registrar_pedido()` | EXECUTE | Procedimiento transaccional |
| `rol_soporte` | `public` (esquema) | USAGE | Necesario para acceder a cualquier objeto |
| `rol_soporte` | `usuario` (columnas: id, nombre, apellido, mail, rol) | SELECT | Ver identificación de usuarios sin datos sensibles |
| `rol_soporte` | `vista_pedidos_cliente` | SELECT | Resumen de pedidos para soporte (Clase 1, sección 4.3) |
| `rol_soporte` | `fn_resetear_password()` | EXECUTE | Reseteo de contraseña para soporte (Clase 2, sección 2.3); nunca sobre usuarios ADMIN |
| `rol_reportes` | `public` (esquema) | USAGE | Necesario para acceder a cualquier objeto |
| `rol_reportes` | `mv_ventas_categoria_mes` | SELECT | Datos agregados para panel gerencial |
| `app_web` | `public` (esquema) | USAGE | Heredado de grupos |
| `app_web` | `rol_app_lectura` | MEMBER | Hereda permisos de lectura |
| `app_web` | `rol_app_escritura` | MEMBER | Hereda permisos de escritura |
| `app_web` | `fn_autenticar()` | EXECUTE | Autenticación de usuarios |
| `admin_datos` | `public` (esquema) | ALL | Dueño del esquema |
| `rol_reportes_login` | `public` (esquema) | USAGE | Heredado de grupos |
| `rol_reportes_login` | `rol_reportes` | MEMBER | Hereda permisos de reportes |

---

## Decisiones de diseño (puntos 1 a 6)

### Punto 1: fn_autenticar - SECURITY INVOKER vs. DEFINER

**Decisión:** Convertir a SECURITY DEFINER con search_path fijo.

**Justificación:** Al ser SECURITY DEFINER, la función ejecuta con privilegios del propietario (admin_datos) y no necesita que app_web tenga SELECT sobre la tabla usuario. Esto permite revocar todo acceso directo a usuario desde app_web, blindando la contraseña hasheada. El SET de search_path evita hijacking de esquema.

**Consecuencia:** app_web no tiene ningún privilegio sobre la tabla usuario, garantizando que el paso 3 del simulacro falle. Además, debe hacerse REVOKE ALL ON FUNCTION FROM PUBLIC y GRANT EXECUTE solo a app_web.

---

### Punto 2: Exposición de celular en rol_soporte

**Decisión:** Usar permiso a nivel de columna sobre la tabla usuario, sin crear vista nueva.

**Justificación:** La consigna exige permiso a nivel de columna. Se otorgan solo las columnas necesarias (id, nombre, apellido, mail, rol), excluyendo celular y contrasena. Esto cumple con el principio de mínimo privilegio y evita la creación de objetos redundantes. Se revoca el SELECT que tenía sobre vista_usuario_reportes.

**Consecuencia:** rol_soporte puede ver identificación básica de usuarios y el resumen de pedidos (Clase 1, sección 4.3), pero no datos personales como celular ni contraseña.

---

### Punto 3: Objetos de solo lectura para rol_reportes

**Decisión:** Crear una vista materializada `mv_ventas_categoria_mes` con datos agregados de ventas por categoría y mes, y quitarle el acceso a `vista_usuario_reportes`.

**Justificación:** Un panel gerencial no necesita datos personales. La vista materializada proporciona los datos de negocio necesarios (ventas por categoría y período) sin exponer información identificable. Se quitó el acceso a vista_usuario_reportes para eliminar la exposición de datos personales que hoy existe en el script original.

**Definición de la vista materializada (sin SQL en esta spec):**

- Columna `categoria`: nombre de la categoría del producto
- Columna `mes`: primer día del mes (truncado a mes) de la fecha del pedido
- Columna `total_ventas`: suma de (cantidad × precio_unitario) de todos los detalles de pedidos de esa categoría en ese mes
- Columna `cantidad_pedidos`: cantidad de pedidos distintos que incluyen productos de esa categoría en ese mes
- Columna `unidades_vendidas`: suma de cantidad de todos los detalles de pedidos de esa categoría en ese mes

**Nota:** No se filtra por productos o categorías activos, porque se perderían registros de ventas históricas de productos o categorías que en la actualidad están dados de baja.

---

### Punto 4: Garantía de falla en el simulacro

**Decisión:** No otorgar SELECT sobre ninguna tabla o vista que exponga datos sensibles a app_web, y no darle ADMIN sobre admin_datos.

**Justificación:** El simulacro usa app_web (o un rol basado en él). Al no tener SELECT sobre `usuario`, `cliente`, ni ninguna vista que exponga esos datos, el paso 3 falla. El paso 4 falla porque en PostgreSQL 16+, para otorgar la membresía de admin_datos a otro rol se necesita tener la opción ADMIN sobre admin_datos; app_web no tiene ni CREATEROLE ni ADMIN, por lo tanto no puede conceder membresías.

**Verificación del diseño:**

| Paso simulacro | Por qué falla |
|----------------|---------------|
| 3. Lectura masiva de usuario | app_web no tiene SELECT sobre `usuario` (solo EXECUTE en fn_autenticar) |
| 4. Dar membresía admin_datos a rol bajo | En PostgreSQL 16+ se requiere opción ADMIN sobre admin_datos para otorgar membresías; app_web no tiene ni CREATEROLE ni ADMIN |

---

### Punto 5: admin_datos como dueño del esquema y objetos

**Decisión:** admin_datos es el OWNER del esquema public y de todos los objetos existentes (tablas, vistas, vista materializada, funciones).

**Justificación:** Sin esta cesión de propiedad, ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos no aplica a ningún objeto (solo aplica a los creados por ese rol). Además, las funciones SECURITY DEFINER ejecutarían como postgres (superusuario), lo cual es un riesgo de seguridad. Al hacer a admin_datos dueño, esas funciones corren con privilegios de admin_datos, no de superusuario.

**Consecuencia:** Las funciones fn_autenticar y fn_resetear_password y el procedimiento registrar_pedido ejecutarán como admin_datos, no como postgres. registrar_pedido se pasa a SECURITY DEFINER con search_path fijo para leer/actualizar producto y disparar sus triggers sin otorgar permisos de tabla a rol_app_escritura.

---

### Punto 6: Rol de login adicional

**Decisión:** Crear `rol_reportes_login` como login miembro de `rol_reportes`.

**Justificación:** Permite asignar credenciales dedicadas a herramientas de BI o reportes automatizados, separando la identidad de la aplicación web (app_web) de la de análisis. Cumple con el principio de separación de funciones.

---

## ALTER DEFAULT PRIVILEGES

1. Las tablas futuras creadas por admin_datos heredan SELECT para rol_reportes.
2. Las funciones futuras creadas por admin_datos NO reciben EXECUTE para PUBLIC.

**Justificación del punto 2:** PostgreSQL otorga EXECUTE a PUBLIC por defecto en funciones. Esto fue lo que hubo que revocar a mano en fn_resetear_password. Definir el DEFAULT PRIVILEGES evita tener que hacerlo manualmente en cada función nueva.

Esto asegura que cualquier tabla nueva que admin_datos cree sea automáticamente legible por el rol de reportes, y que cualquier función nueva no quede ejecutable por cualquiera sin un grant explícito.

---

## Resumen de cambios respecto a sql/roles.sql original

| Cambio | Original | Nuevo |
|--------|----------|-------|
| fn_autenticar | SECURITY INVOKER | SECURITY DEFINER + search_path |
| app_web sobre usuario | SELECT (implícito por INVOKER) | Ninguno (solo EXECUTE en función) |
| rol_soporte | SELECT en vista_usuario_reportes | SELECT (columnas) en tabla usuario + SELECT en vista_pedidos_cliente (Clase 1, sección 4.3); se revoca vista_usuario_reportes |
| registrar_pedido | SECURITY INVOKER | SECURITY DEFINER + search_path |
| fn_resetear_password | EXECUTE en funciones_auth | EXECUTE para rol_soporte (restaurado); no resetea ADMIN, mínimo 8 caracteres, error si no aplica (Parte A.4) |
| rol_app_escritura sobre pedido/detalle_pedido | SELECT, INSERT, UPDATE | Solo SELECT; el alta es vía registrar_pedido (Parte A.4) |
| rol_reportes | Sin objeto dedicado | SELECT en mv_ventas_categoria_mes |
| DEFAULT PRIVILEGES | No definido | SELECT en tablas futuras para rol_reportes; funciones futuras sin EXECUTE para PUBLIC |
| Rol login adicional | Solo app_web, admin_datos | Agregado rol_reportes_login |

---

## Criterios de verificación

```sql
-- Verificar existencia de roles
\du

-- Verificar privilegios de tablas
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public';

-- Verificar privilegios de columnas
SELECT grantee, table_name, column_name, privilege_type
FROM information_schema.role_column_grants
WHERE table_schema = 'public' AND table_name = 'usuario';

-- Verificar DEFAULT PRIVILEGES
SELECT *
FROM information_schema.default_privileges
WHERE grantee = 'rol_reportes';

-- Verificar que app_web no tiene SELECT sobre usuario
SELECT grantee, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'app_web' AND table_name = 'usuario';
```

## Ajustes posteriores a la revisión del SQL (Parte A.2)

Estos ajustes se agregaron después de revisar el SQL propuesto porque la matriz inicial omitió el resumen de pedidos de soporte (Clase 1, sección 4.3) y el reseteo de contraseña (Clase 2, sección 2.3), y porque `registrar_pedido` necesita operar sobre `producto` sin grants de tabla extra.

## Ajustes posteriores a la auditoría (Parte A.4)

Estos cambios vienen de la auditoría de la Parte A.4 (`docs/auditoria_roles_ia.md`).

**rol_app_escritura: solo SELECT sobre `pedido` y `detalle_pedido`.** La matriz original le daba INSERT y UPDATE, lo que contradecía la justificación del rol ("mediante el procedimiento transaccional"). Con ese grant, `app_web` podía insertar pedidos vacíos o con fecha arbitraria y cambiar `fecha` o `id_cliente` de cualquier pedido, lo que altera `mv_ventas_categoria_mes`. Sobre `detalle_pedido` el INSERT/UPDATE directo ya fallaba (los triggers son SECURITY INVOKER y leen `producto`), pero quedaba latente un `UPDATE` de `precio_unitario` que rompería R4 si la app recibiera SELECT sobre `producto`. Toda alta pasa por `registrar_pedido()` (SECURITY DEFINER). Como la base ya tenía aplicado el GRANT anterior, `roles.sql` hace primero `REVOKE INSERT, UPDATE`.

**fn_resetear_password: reglas de uso.**
- No resetea usuarios con `rol = 'ADMIN'`: si no, soporte podría fijar la contraseña de un administrador y entrar a la aplicación web como ADMIN (escalada a nivel de aplicación).
- La nueva contraseña debe tener al menos 8 caracteres (y no puede ser NULL).
- Si el usuario no existe, está eliminado o es ADMIN, la función lanza `RAISE EXCEPTION` en lugar de no hacer nada en silencio.