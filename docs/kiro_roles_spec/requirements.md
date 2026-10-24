# Requisitos de Roles PostgreSQL — Food Store TP U5

## Objetivo

Diseñar y documentar un sistema de control de acceso basado en roles (RBAC) para la base de datos Food Store que satisfaga los requisitos del TP Unidad 5, incluyendo roles de grupo, roles de login, y una política de privilegios que permita un simulacro de pruebas de seguridad con resultados predecibles.

## Requisitos

### R1: Roles de grupo (NOLOGIN)

| Rol | Propósito |
|-----|-----------|
| `rol_app_lectura` | Permite solo lectura de datos de negocio públicos (productos) |
| `rol_app_escritura` | Permite lectura + escritura en pedidos y detalles; ejecución de procedimientos transaccionales |
| `rol_soporte` | Permite consultar datos de usuarios (sin datos sensibles como contraseña) para tareas de soporte |
| `rol_reportes` | Permite acceder a datos agregados para panel gerencial, sin datos personales de clientes ni usuarios |

**Criterio de aceptación:** Los cuatro roles existen con NOLOGIN y tienen USAGE sobre el esquema public.

### R2: Roles de login

| Rol | Propósito | Privilegios especiales |
|-----|-----------|------------------------|
| `app_web` | Aplicación web que autentica usuarios finales | Miembro de `rol_app_lectura` + `rol_app_escritura` |
| `admin_datos` | Administrador de datos para mantenimiento | `CREATEDB` + `CREATEROLE`, sin `SUPERUSER` |
| `rol_reportes_login` *(nuevo)* | Login para herramientas de BI/reportes | Miembro de `rol_reportes` |

**Criterio de aceptación:** Los roles de login pueden conectarse a la base y tienen asignados los roles de grupo correspondientes.

### R3: Permisos sobre objetos existentes

| Objeto | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` |
|--------|-------------------|---------------------|---------------|----------------|
| `vista_productos_vigentes` | SELECT | (heredado) | - | - |
| `pedido` | - | SELECT, INSERT, UPDATE | - | - |
| `detalle_pedido` | - | SELECT, INSERT, UPDATE | - | - |
| `registrar_pedido()` | - | EXECUTE | - | - |
| `usuario` (columnas) | - | - | SELECT (id, nombre, apellido, mail, rol) | - |
| `vista_pedidos_cliente` | - | - | SELECT | - |
| `fn_resetear_password()` | - | - | EXECUTE | - |
| `mv_ventas_categoria_mes` *(nueva)* | - | - | - | SELECT |
| `vista_usuario_reportes` | - | - | - | (quitado: exponía datos personales) |

**Criterio de aceptación:** Verificable con `information_schema.role_table_grants` y `role_column_grants`.

### R4: Función de autenticación

- `fn_autenticar(p_mail TEXT, p_pass TEXT)` debe ejecutarse con privilegios del propietario (SECURITY DEFINER)
- `search_path` debe estar fijo a `public, pg_temp` para evitar hijacking de esquema
- `app_web` debe tener permiso EXECUTE sobre la función
- `PUBLIC` debe tener REVOKE ALL sobre la función

**Criterio de aceptación:** `app_web` puede ejecutar fn_autenticar SIN tener SELECT sobre la tabla `usuario`.

### R5: Seguridad contra escalamiento (simulacro)

El diseño debe garantizar que el siguiente escenario falle como se indica:

| Paso | Operación | Resultado esperado |
|------|-----------|--------------------|
| 1 | 3 intentos de login fallidos contra `fn_autenticar` | Fallan (autenticación incorrecta) |
| 2 | 1 login exitoso como usuario válido | Exitoso |
| 3 | Lectura masiva de tabla `usuario` | **Falla**: el rol no tiene SELECT sobre `usuario` |
| 4 | Intento de dar membresía `admin_datos` a un rol de bajo privilegio | **Falla**: en PostgreSQL 16+ se requiere opción ADMIN sobre admin_datos; el rol simulacro no la tiene |

**Criterio de aceptación:** El rol usado en el simulacro no tiene permisos para leer `usuario` ni para otorgar membresías.

### R6: Privilegios por defecto (ALTER DEFAULT PRIVILEGES)

1. Las tablas creadas en el futuro por `admin_datos` deben tener SELECT asignado a `rol_reportes`.
2. Las funciones creadas en el futuro por `admin_datos` NO deben tener EXECUTE para PUBLIC.

**Criterio de aceptación:** Verificable consultando `information_schema.default_privileges`.

### R7: Ownership de admin_datos

`admin_datos` debe ser OWNER del esquema `public` y de todos los objetos existentes (tablas, vistas, vista materializada, funciones y el procedimiento `registrar_pedido`).

**Justificación:** Sin esta cesión de propiedad, ALTER DEFAULT PRIVILEGES no aplica y las funciones SECURITY DEFINER ejecutarían como postgres (superusuario).

**Criterio de aceptacion:** Verificable consultando `pg_class.relowner` y `information_schema.schema_privileges`.

---

## Definiciones

- **Usuario de negocio**: cliente que realiza pedidos (tabla `cliente`)
- **Usuario del sistema**: empleado que accede a la base (tabla `usuario`, roles PostgreSQL)
- **Datos sensibles**: contraseña hasheada (`contrasena`), número de teléfono (`celular`)
- **Datos agregados**: sumas, conteos, promedios por categoría/período (sin identificación personal)

---

## Notas

- La tabla `usuario` tiene un ENUM `rol` de negocio (USUARIO/ADMIN), **no** es un rol de PostgreSQL.
- El permiso a nivel de columna sobre `usuario` para `rol_soporte` cumple el requisito de la consigna.
- La vista materializada `mv_ventas_categoria_mes` es nueva y debe crearse como parte del script derivado de esta spec.
- Ajustes posteriores a la revisión del SQL (Parte A.2): se restauraron `SELECT` de `rol_soporte` sobre `vista_pedidos_cliente` (Clase 1, sección 4.3) y `EXECUTE` sobre `fn_resetear_password` (Clase 2, sección 2.3; la matriz inicial los omitió por error), y `registrar_pedido()` pasa a `SECURITY DEFINER` con `search_path = public, pg_temp` para operar sobre `producto` sin grants de tabla extra.