# Auditoría de `sql/roles.sql` contra `docs/kiro_roles_spec/design.md`

## Contexto

Auditoría de solo lectura (no se modificó ningún archivo ni se ejecutó nada contra la base). Se revisaron
`sql/roles.sql`, `sql/funciones_auth.sql` y `sql/mv_ventas_categoria_mes.sql`, junto con los objetos de los que
dependen: `food-store/views.sql`, `food-store/procedimientos.sql`, `food-store/restricciones.sql` y
`food-store/schema.sql`. Dominio de seguridad (gobernanza CRITICAL): todo lo de abajo es una propuesta; quien lo
aplica es la autora, primero con `BEGIN … ROLLBACK`.

**Veredicto general:** el script cumple la matriz de la spec casi línea por línea. Los problemas importantes
están en **la propia spec** (dos decisiones que contradicen el mínimo privilegio) y en **lo que el script no
limpia ni controla** (permisos viejos, otras bases del clúster, scripts que se vuelven a ejecutar).

| # | Hallazgo | Severidad | ¿Cumple la spec? |
|---|----------|-----------|------------------|
| H1 | `rol_app_escritura` tiene INSERT/UPDATE directo sobre `pedido` y `detalle_pedido` | Alta | Sí: el defecto está en la spec |
| H2 | `DEFAULT PRIVILEGES` da SELECT sobre **toda** tabla/vista futura a `rol_reportes` | Alta (a futuro) | Sí: el defecto está en la spec |
| H3 | `rol_reportes_login` hereda permisos de `rol_reportes` en **otras bases** (bd2_tp3) | Alta (a verificar) | No lo contempla |
| H4 | `fn_resetear_password` permite a soporte resetear la contraseña de un ADMIN | Media | No lo contempla |
| H5 | Contraseñas fijas en el repo, y se resetean cada vez que se ejecuta el script | Media | — |
| F1 | Volver a ejecutar `procedimientos.sql` le saca SECURITY DEFINER a `registrar_pedido` | Alta (funcional) | — |
| F2 | Nadie puede refrescar la MV; el DROP+CREATE borra sus grants | Media | No lo contempla |
| F3 | `rol_soporte` no tiene login; no puede ver `eliminado` | Baja | Sí |
| F4 | `mes` de la MV depende del `TimeZone` de la sesión y es `timestamptz`, no fecha | Baja | No: la spec dice "primer día del mes" |
| R1 | El script no revoca permisos previos: no es declarativo | Alta | — |
| R2 | `views.sql` vuelve a crear el GRANT a `vista_usuario_reportes` y el rol con LOGIN | Alta | — |
| M1–M4 | Mantenimiento: ownership hardcodeado, DDL ejecutado como postgres, sin control de "nada de más" | Media | — |

---

## 1. Lo que un rol puede hacer y no debería

### H1 — `rol_app_escritura`: DML directo sobre `pedido` y `detalle_pedido`

`roles.sql:87` → `GRANT SELECT, INSERT, UPDATE ON pedido, detalle_pedido TO rol_app_escritura;`

La matriz de la spec lo pide (líneas 24–25), pero **contradice la justificación de la misma spec** (línea 8:
*"mediante el procedimiento transaccional, sin acceso directo a tablas sensibles"*). Con ese grant, `app_web`:

- **Puede inyectar o adulterar ventas sin pasar por `registrar_pedido`:**
  `INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES ('2024-01-01', 'EFECTIVO', 1);` funciona (no hay
  trigger sobre `pedido`, la FK la valida el dueño, y la identidad no exige USAGE sobre la secuencia). Además,
  `UPDATE pedido SET fecha = …, id_cliente = …` funciona sobre **cualquier** pedido. Los dos casos alteran
  `mv_ventas_categoria_mes` en el próximo REFRESH (manipulación del panel gerencial), y se crean pedidos vacíos,
  lo que la regla del procedimiento prohíbe.
- **Sobre `detalle_pedido` el grant es inútil por accidente:** los triggers `fn_verificar_*` son SECURITY INVOKER
  y hacen `SELECT … FROM producto`, que `app_web` no puede leer. Por eso todo INSERT/UPDATE directo falla con
  *permission denied for table producto*. El día que alguien le dé SELECT sobre `producto` a la app, queda
  habilitado `UPDATE detalle_pedido SET precio_unitario = 0`, que **rompe R4** (precio histórico congelado).

**Corrección:** solo EXECUTE sobre el procedimiento, más SELECT para consultar pedidos.
```sql
REVOKE INSERT, UPDATE ON pedido, detalle_pedido FROM rol_app_escritura;
GRANT  SELECT          ON pedido, detalle_pedido TO   rol_app_escritura;
```
Hay que actualizar la matriz de `design.md` (Kiro) y registrarlo en el DUIA.

### H2 — `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES TO rol_reportes`

`roles.sql:113-114`. En PostgreSQL, `ON TABLES` abarca tablas, **vistas y vistas materializadas**. Si
`admin_datos` vuelve a ejecutar `schema.sql` (que hace `DROP … CASCADE` + `CREATE`), `rol_reportes` recibe
automáticamente SELECT sobre `usuario` (**con `contrasena`**), `cliente` (email, teléfono) y
`vista_cliente_completo`. Eso destruye la justificación del rol (*"sin datos personales"*) y el punto 3 de la
spec. Hoy no pasa solo porque todo se crea como `postgres` (ver M2): la regla es una bomba de tiempo.

**Corrección recomendada:** acotar el automatismo a un esquema que solo contenga agregados.
```sql
-- Deshacer el default actual
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    REVOKE SELECT ON TABLES FROM rol_reportes;

-- Esquema exclusivo para objetos de BI: acá sí, todo lo nuevo es legible por reportes
CREATE SCHEMA IF NOT EXISTS reportes AUTHORIZATION admin_datos;
REVOKE ALL ON SCHEMA reportes FROM PUBLIC;
GRANT USAGE ON SCHEMA reportes TO rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA reportes
    GRANT SELECT ON TABLES TO rol_reportes;
```
Así se mantiene la demostración de `ALTER DEFAULT PRIVILEGES` que pide la spec, pero el automatismo queda en un
lugar donde es seguro. La MV pasaría a `reportes.mv_ventas_categoria_mes` (ver §5.3) y `rol_reportes` ya no
necesitaría USAGE sobre `public`. Si la cátedra exige que todo quede en `public`, la alternativa mínima es
borrar el default y otorgar cada objeto de reportes de forma explícita.

### H3 — Los roles son de clúster, los GRANT son por base

`views.sql:178` otorgó `SELECT ON vista_usuario_reportes TO rol_reportes` en **bd2_tp3** (verificado el
23/09 según el comentario, línea 180). `roles.sql` solo revoca eso en la base donde se ejecuta. Como
`rol_reportes_login` es miembro de `rol_reportes` y PUBLIC tiene CONNECT por defecto en todas las bases, es
muy probable que hoy `rol_reportes_login` pueda conectarse a bd2_tp3 y leer **celular** de todos los usuarios.
Lo mismo vale para cualquier grant viejo a `app_web`/`rol_app_*` en otras bases.

**A verificar (solo lectura, conectado a bd2_tp3 como postgres):**
```sql
SELECT has_database_privilege('rol_reportes_login', current_database(), 'CONNECT') AS puede_conectar,
       has_table_privilege('rol_reportes_login', 'vista_usuario_reportes', 'SELECT') AS lee_usuarios;
```
**Corrección (en `roles.sql`, se aplica a la base actual):**
```sql
DO $$
BEGIN
    EXECUTE format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, admin_datos',
                   current_database());
END $$;
```
El ACL de base **no se copia** con `createdb -T`, así que tiene que estar en el script y no hacerse a mano. En
bd2_tp3 habría que ejecutar `REVOKE SELECT ON vista_usuario_reportes FROM rol_reportes;` y el mismo REVOKE
CONNECT. `bd2_proyecto` no se toca (regla de AGENTS.md), pero cambiar su ACL de base no altera su contenido:
es decisión de la autora.

### H4 — Soporte puede tomar una cuenta ADMIN

`fn_resetear_password` es SECURITY DEFINER y actualiza **cualquier** usuario no eliminado. Una persona de
soporte puede resetear la contraseña de un `rol = 'ADMIN'` y entrar a la aplicación web como administrador
(`fn_autenticar` devuelve `rol`). Es una escalada a nivel de aplicación. Además, si el id no existe o está
eliminado, la función no hace nada **en silencio**.

**Corrección** (en `funciones_auth.sql`; `CREATE OR REPLACE` conserva el dueño y los grants):
```sql
CREATE OR REPLACE FUNCTION fn_resetear_password(
    p_usuario_id BIGINT, p_nueva TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_nueva IS NULL OR length(p_nueva) < 8 THEN
        RAISE EXCEPTION 'La nueva contraseña debe tener al menos 8 caracteres';
    END IF;

    -- Soporte no puede resetear cuentas ADMIN: evita la toma de cuentas privilegiadas.
    UPDATE usuario
    SET    contrasena = crypt(p_nueva, gen_salt('bf'))
    WHERE  id = p_usuario_id AND eliminado = FALSE AND rol <> 'ADMIN';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario % inexistente, eliminado o ADMIN: no se resetea', p_usuario_id;
    END IF;
END;
$$;
```
La exclusión de ADMIN es una regla de negocio: la decide la autora y hay que agregarla a la spec.

### H5 — Contraseñas en el script

`roles.sql:38-43` deja la misma contraseña para los tres logins, versionada en git, y **cada vez que se ejecuta
el script se pisa** cualquier contraseña que se haya rotado. Propuesta: el script fija solo los atributos y la
contraseña se carga fuera del repo.
```sql
ALTER ROLE app_web WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
-- y una sola vez, interactivo (no queda en el historial ni en el repo):
-- \password app_web
```
De paso, `rol_reportes` conserva la contraseña `'reportes123'` de `views.sql`. Es inofensiva con NOLOGIN, pero
conviene `PASSWORD NULL`.

---

## 2. Lo que le falta a un rol para cumplir su función

### F1 — `registrar_pedido` pierde SECURITY DEFINER si se vuelve a ejecutar `procedimientos.sql`

`CREATE OR REPLACE PROCEDURE` conserva el dueño y los permisos, pero **todo atributo que no figure en el comando
vuelve a su valor por defecto**: SECURITY INVOKER y sin `SET search_path`. Después de volver a ejecutar
`procedimientos.sql`, `CALL registrar_pedido(...)` desde `app_web` falla (*permission denied for table
producto*). El atributo tiene que vivir en la definición, igual que ya pasa en `funciones_auth.sql`:
```sql
CREATE OR REPLACE PROCEDURE registrar_pedido(
    p_id_cliente BIGINT,
    p_forma_pago forma_pago_enum,
    p_items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ … $$;
```
El `ALTER PROCEDURE` de `roles.sql:76-78` puede quedar como red de seguridad.

### F2 — La MV no tiene responsable de refresco

- Solo el dueño (`admin_datos`) o un superusuario puede ejecutar `REFRESH`. No hay procedimiento ni tarea, así
  que reportes leerá datos congelados en el momento de la creación. En PG17 existe el privilegio `MAINTAIN`
  para delegar el refresco sin ceder la propiedad (`GRANT MAINTAIN ON … TO <rol_job>`).
- Para que el refresco no bloquee a los lectores hace falta `REFRESH … CONCURRENTLY`, que exige un índice
  único. `(categoria, mes)` es único porque `categoria.nombre` es UNIQUE. Es un requisito funcional, no de
  rendimiento, así que no necesita la justificación con EXPLAIN que pide AGENTS.md para los índices.
- `mv_ventas_categoria_mes.sql` hace DROP + CREATE: **borra el grant y deja como dueño a quien lo ejecute**.
  Si se vuelve a ejecutar solo, reportes pierde el acceso hasta que se vuelva a ejecutar `roles.sql`. Esto ya
  está documentado en el header, pero conviene la verificación de §6.

### F3 — `rol_soporte`

- No hay ningún login miembro, así que hoy nadie puede ejercer el rol. La spec no lo exige; si se quiere probar
  de punta a punta: `CREATE ROLE soporte_login LOGIN IN ROLE rol_soporte;`.
- El grant por columnas excluye `eliminado`, así que soporte no puede distinguir a un usuario dado de baja (al
  que el reseteo ignora). `eliminado` no es sensible: sugiero agregarlo a la lista
  `(id, nombre, apellido, mail, rol, eliminado)`, actualizando la spec.

### F4 — Columna `mes` de la MV

`DATE_TRUNC('month', pe.fecha)` sobre `timestamptz` devuelve `timestamptz` calculado con el `TimeZone` de la
sesión que hace el REFRESH. Un pedido del 31/10 a las 23:30 hora argentina cae en noviembre si se refresca con
TimeZone UTC. La spec dice "primer día del mes", que es un `date`:
```sql
DATE_TRUNC('month', pe.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes
```
(Cambia el tipo de la columna: hay que revisar las consultas que la usan.)

### Lo que sí está bien y no hay que tocar

- `fn_autenticar`: SECURITY DEFINER, `search_path` fijo con `pg_temp` al final, `crypt` sin concatenar, EXECUTE
  solo para `app_web`. `app_web` no tiene ningún acceso a `usuario` (pasos 3 y 4 del simulacro cubiertos).
- El grant por columnas a soporte, el REVOKE previo de tabla (que en PostgreSQL también revoca los privilegios
  de columna) y el REVOKE de `vista_usuario_reportes`.
- Las vistas son propiedad de `admin_datos` y no son `security_invoker`: soporte y lectura no necesitan nada
  sobre las tablas base.
- `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` sin `IN SCHEMA`: correcto, y el
  comentario explica bien el porqué (también cubre procedimientos).
- Que las funciones de trigger conserven EXECUTE para PUBLIC es inofensivo, como dice `verificacion_roles.sql`.

---

## 3. Robustez e idempotencia del script

### R1 — Solo agrega permisos, nunca limpia

El script otorga lo que dice la matriz, pero no garantiza que no quede **nada más**. Cualquier grant de una
versión anterior (por ejemplo, `app_web` con SELECT sobre `usuario` del roles.sql original, que la spec dice que
existía), una membresía de más (`GRANT pg_read_all_data TO …`) o un grant a PUBLIC sobrevive a la ejecución. El
punto 4 de la spec ("app_web no tiene SELECT sobre usuario") hoy depende de que nadie lo haya otorgado antes.
**Corrección:** un bloque "reset" antes de los GRANT (incluido en §4). Ojo con una trampa: **no** hacer
`REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC`, porque las funciones de pgcrypto (`crypt`,
`gen_salt`) viven en `public`, pertenecen a postgres, y `admin_datos` las ejecuta gracias a PUBLIC. Sin ese
grant, `fn_autenticar` y `fn_resetear_password` se rompen. El reset de rutinas tiene que excluir los miembros
de la extensión.

### R2 — `views.sql` contradice a `roles.sql`

`views.sql:170-178` crea `rol_reportes` con **LOGIN** y le otorga SELECT sobre `vista_usuario_reportes` (que
incluye celular). Si alguien vuelve a ejecutar `views.sql` después de `roles.sql`, la exposición que eliminó el
punto 3 de la spec vuelve. **Corrección:** borrar ese bloque de `views.sql` (o dejarlo comentado con la
referencia a que la política vive en `sql/roles.sql`), igual que ya hacen `funciones_auth.sql` y la MV ("Sin
GRANT/REVOKE").

### R3 — CREATE sobre `public`

PG15+ ya no le da CREATE a PUBLIC, pero si la base viene de un dump antiguo podría tenerlo, y eso es lo que
habilita el hijacking que el `search_path` fijo intenta evitar. Es barato blindarlo:
`REVOKE CREATE ON SCHEMA public FROM PUBLIC;`

---

## 4. Mantenimiento a futuro (tablas y funcionalidades nuevas)

**M1 — Ownership hardcodeado.** `roles.sql:53-72` lista objeto por objeto. Una tabla, vista o función nueva
queda en manos de postgres sin que nadie lo note, y si es SECURITY DEFINER **corre como superusuario**, que es
justo el riesgo que el punto 5 de la spec quiere evitar. Conviene reemplazar la lista por un loop sobre el
catálogo que excluya los objetos de extensiones (§5.1).

**M2 — El DDL se ejecuta como postgres, así que los DEFAULT PRIVILEGES nunca se aplican.**
`ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos` solo actúa sobre objetos **creados por admin_datos**. Hoy todo
se crea como postgres (`funciones_auth.sql` se ejecuta antes de que exista `admin_datos`). El orden
recomendado:

1. `sql/00_roles_base.sql`: secciones 1–2 de roles.sql (crear roles y atributos) + `ALTER SCHEMA public OWNER`
   + loop de ownership.
2. Scripts de objetos con `SET ROLE admin_datos;` al inicio (excepto `CREATE EXTENSION`, que queda como
   postgres): `funciones_auth.sql`, `mv_ventas_categoria_mes.sql`, y a futuro cualquier DDL nuevo.
3. `sql/roles.sql`: ownership de respaldo + reset + grants + defaults.

**M3 — Esquema `reportes`** (H2). Agregar un agregado nuevo para BI pasa a ser "crearlo en `reportes`" y no hay
que tocar `roles.sql`.

**M4 — Control de "nada de más".** `verificacion_roles.sql` muestra lo que hay, pero no falla si aparece algo
que no estaba en la matriz. Las consultas de §6 devuelven **0 filas** si todo está bien y sirven de regresión
cada vez que se agrega un objeto.

**Checklist para cada tabla o función nueva** (vale la pena agregarla a `design.md`):
1. ¿Quién es el dueño? Siempre `admin_datos` (con SET ROLE o con el loop).
2. ¿Qué rol de grupo la necesita y con qué privilegio? Agregar una fila a la matriz **antes** de escribir el GRANT.
3. Si es una función: ¿necesita SECURITY DEFINER? Si sí, `SET search_path = public, pg_temp` en la definición
   (no en un ALTER aparte) y EXECUTE solo al rol de la matriz.
4. Si tiene datos personales: nunca en `reportes`; para soporte, grant por columnas o vista.
5. Ejecutar `roles.sql` y la verificación de §6 (0 filas).

---

## 5. SQL propuesto

### 5.1 `sql/roles.sql` revisado

```sql
-- =====================================================================
-- roles.sql — Food Store, TP Unidad 5 (Parte A)
-- Orden: último. Ejecutar como postgres. Declarativo: limpia y vuelve a otorgar.
-- =====================================================================

-- 0) Guarda: nunca sobre la plantilla.
DO $$
BEGIN
    IF current_database() = 'bd2_proyecto' THEN
        RAISE EXCEPTION 'roles.sql no se ejecuta sobre la plantilla bd2_proyecto';
    END IF;
END $$;

-- 1) Roles de grupo: NOLOGIN, sin atributos, sin contraseña residual.
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_app_lectura', 'rol_app_escritura',
                              'rol_soporte', 'rol_reportes'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I', r);
        END IF;
        EXECUTE format('ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
                       'NOREPLICATION NOBYPASSRLS PASSWORD NULL', r);
    END LOOP;
END $$;

-- 2) Roles de login: atributos forzados; la contraseña se carga con \password, fuera del repo.
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['app_web', 'admin_datos', 'rol_reportes_login'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I', r);
        END IF;
    END LOOP;
END $$;

ALTER ROLE app_web            WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE rol_reportes_login WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE admin_datos        WITH LOGIN NOSUPERUSER CREATEDB   CREATEROLE   NOREPLICATION NOBYPASSRLS;

-- 3) Membresías: se quitan las que no están en la matriz y se otorgan las que sí.
-- (admin_datos queda afuera: en PG16+ recibe ADMIN sobre los roles que crea.)
DO $$
DECLARE
    m RECORD;
BEGIN
    FOR m IN
        SELECT g.rolname AS grupo, u.rolname AS miembro
        FROM pg_auth_members am
        JOIN pg_roles g ON g.oid = am.roleid
        JOIN pg_roles u ON u.oid = am.member
        WHERE u.rolname IN ('app_web', 'rol_reportes_login', 'rol_app_lectura',
                            'rol_app_escritura', 'rol_soporte', 'rol_reportes')
          AND (u.rolname, g.rolname) NOT IN (('app_web', 'rol_app_lectura'),
                                             ('app_web', 'rol_app_escritura'),
                                             ('rol_reportes_login', 'rol_reportes'))
    LOOP
        EXECUTE format('REVOKE %I FROM %I', m.grupo, m.miembro);
    END LOOP;
END $$;

GRANT rol_app_lectura, rol_app_escritura TO app_web;
GRANT rol_reportes TO rol_reportes_login;

-- 4) Ownership: admin_datos es dueña del esquema y de TODO objeto propio de public
-- (excluye miembros de extensiones como pgcrypto). Cubre objetos futuros sin editar la lista.
ALTER SCHEMA public OWNER TO admin_datos;

DO $$
DECLARE
    o RECORD;
BEGIN
    FOR o IN
        SELECT c.relname, c.relkind
        FROM pg_class c
        WHERE c.relnamespace = 'public'::regnamespace
          AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
          AND c.relowner <> 'admin_datos'::regrole
          AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.classid = 'pg_class'::regclass
                            AND d.objid = c.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER %s public.%I OWNER TO admin_datos',
                       CASE o.relkind WHEN 'v' THEN 'VIEW'
                                      WHEN 'm' THEN 'MATERIALIZED VIEW'
                                      WHEN 'f' THEN 'FOREIGN TABLE'
                                      ELSE 'TABLE' END,
                       o.relname);
    END LOOP;

    FOR o IN
        SELECT p.oid::regprocedure AS firma, p.prokind
        FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.proowner <> 'admin_datos'::regrole
          AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.classid = 'pg_proc'::regclass
                            AND d.objid = p.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER %s %s OWNER TO admin_datos',
                       CASE o.prokind WHEN 'p' THEN 'PROCEDURE'
                                      WHEN 'a' THEN 'AGGREGATE'
                                      ELSE 'FUNCTION' END,
                       o.firma);
    END LOOP;

    FOR o IN
        SELECT t.typname
        FROM pg_type t
        WHERE t.typnamespace = 'public'::regnamespace
          AND t.typtype = 'e'
          AND t.typowner <> 'admin_datos'::regrole
          AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.classid = 'pg_type'::regclass
                            AND d.objid = t.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER TYPE public.%I OWNER TO admin_datos', o.typname);
    END LOOP;
END $$;

-- Red de seguridad: la definición canónica vive en procedimientos.sql (ver F1).
ALTER PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB)
    SECURITY DEFINER
    SET search_path = public, pg_temp;

-- 5) Base y esquema: solo los roles del proyecto se conectan; nadie más crea en public.
DO $$
BEGIN
    EXECUTE format('REVOKE CONNECT, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rol_app_lectura, rol_app_escritura, '
                   'rol_soporte, rol_reportes, admin_datos', current_database());
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 6) Reset: se quita todo a PUBLIC y a los roles del proyecto antes de otorgar.
REVOKE ALL ON ALL TABLES    IN SCHEMA public
    FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
         app_web, rol_reportes_login;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
    FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
         app_web, rol_reportes_login;
-- Rutinas: a los roles sí; a PUBLIC no en bloque (pgcrypto vive en public y admin_datos lo usa).
REVOKE ALL ON ALL ROUTINES  IN SCHEMA public
    FROM rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
         app_web, rol_reportes_login;
REVOKE ALL ON SCHEMA public
    FROM rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
         app_web, rol_reportes_login;

-- PUBLIC pierde EXECUTE en rutinas propias que no son de trigger ni de extensión.
DO $$
DECLARE
    f regprocedure;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.prorettype <> 'trigger'::regtype
          AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.classid = 'pg_proc'::regclass
                            AND d.objid = p.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC', f);
    END LOOP;
END $$;

-- 7) Grants según la matriz (design.md, con H1 aplicado).
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;

GRANT SELECT ON vista_productos_vigentes TO rol_app_lectura;

-- Escritura solo por el procedimiento: SELECT para consultar, sin INSERT/UPDATE directo.
GRANT SELECT ON pedido, detalle_pedido TO rol_app_escritura;
GRANT EXECUTE ON PROCEDURE registrar_pedido(BIGINT, forma_pago_enum, JSONB) TO rol_app_escritura;

GRANT SELECT ON mv_ventas_categoria_mes TO rol_reportes;

-- Soporte: resumen de pedidos e identificación; nunca celular ni contrasena.
GRANT SELECT ON vista_pedidos_cliente TO rol_soporte;
GRANT SELECT (id, nombre, apellido, mail, rol) ON usuario TO rol_soporte;
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT) TO rol_soporte;

GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT) TO app_web;

-- 8) Default privileges para objetos que cree admin_datos.
-- Se deshace el SELECT automático en public: expondría usuario/cliente si se recrean (H2).
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    REVOKE SELECT ON TABLES FROM rol_reportes;
-- Sin IN SCHEMA: el EXECUTE a PUBLIC es un default global y no se puede revocar por esquema.
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Opción recomendada: esquema reportes con SELECT automático (ver bloque de H2).
```

Notas para defenderlo en el oral:
- La sección 6 deja el script **declarativo**: lo que no está en la sección 7 no existe después de ejecutarlo.
- `REVOKE ALL ON ALL TABLES` incluye vistas, vistas materializadas y privilegios de columna. Por eso
  `REVOKE SELECT ON vista_usuario_reportes` y `REVOKE SELECT ON usuario FROM rol_soporte` ya no hacen falta
  como líneas sueltas.
- Las secuencias de identidad cambian de dueño junto con su tabla (`ALTER TABLE … OWNER` arrastra las
  secuencias propias).
- PG16+: `REVOKE rol FROM miembro` ejecutado por postgres revoca las membresías otorgadas por postgres. Si
  alguna la otorgó otro rol, hace falta `GRANTED BY`; la consulta de §6 lo detecta.

### 5.2 `food-store/procedimientos.sql`
Agregar `SECURITY DEFINER` y `SET search_path = public, pg_temp` en la cabecera del `CREATE OR REPLACE
PROCEDURE` (F1). El cuerpo no cambia.

### 5.3 `sql/mv_ventas_categoria_mes.sql`
```sql
DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_mes;

CREATE MATERIALIZED VIEW mv_ventas_categoria_mes AS
SELECT
    c.nombre                                                                AS categoria,
    DATE_TRUNC('month', pe.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes,
    SUM(dp.cantidad * dp.precio_unitario)                                   AS total_ventas,
    COUNT(DISTINCT pe.id_pedido)                                            AS cantidad_pedidos,
    SUM(dp.cantidad)                                                        AS unidades_vendidas
FROM categoria c
JOIN producto p        ON p.id_categoria = c.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
JOIN pedido pe         ON pe.id_pedido = dp.id_pedido
GROUP BY 1, 2
WITH DATA;

-- Requisito de REFRESH … CONCURRENTLY (no bloquea lectores); único porque categoria.nombre es UNIQUE.
CREATE UNIQUE INDEX idx_mv_ventas_categoria_mes_categoria_mes
    ON mv_ventas_categoria_mes (categoria, mes);

-- Refresco (responsabilidad de admin_datos, p. ej. después de cada carga):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_categoria_mes;
```
Con la opción del esquema `reportes`: `CREATE MATERIALIZED VIEW reportes.mv_ventas_categoria_mes …`, creada
con `SET ROLE admin_datos` para que la tome el default privilege.

### 5.4 `food-store/funciones_auth.sql`
`fn_resetear_password` con la guarda de ADMIN, la validación de longitud y el `NOT FOUND` (H4).

### 5.5 `food-store/views.sql`
Quitar el bloque `DO $$ … CREATE ROLE rol_reportes LOGIN …` y `GRANT SELECT ON vista_usuario_reportes TO
rol_reportes` (líneas 161–187), o dejarlos comentados con una referencia a `sql/roles.sql` (R2).

### 5.6 `docs/kiro_roles_spec/design.md` (para que lo revise Kiro)
- Matriz: `pedido` y `detalle_pedido` → solo SELECT (H1).
- Sección ALTER DEFAULT PRIVILEGES: quitar el SELECT automático en `public`; esquema `reportes` (H2).
- Agregar CONNECT por base y REVOKE a PUBLIC (H3), la regla de `fn_resetear_password` (H4) y el checklist de §4.
- Registrar en `docs/duia/` qué se aceptó y qué se descartó.

---

## 6. Verificación (agregar a `sql/verificacion_roles.sql`; cada consulta debe devolver 0 filas)

```sql
-- a) Privilegios de tabla/vista/MV que no están en la matriz (pg_class sí incluye MVs).
WITH esperado(grantee, objeto, priv) AS (VALUES
    ('rol_app_lectura',   'vista_productos_vigentes', 'SELECT'),
    ('rol_app_escritura', 'pedido',                   'SELECT'),
    ('rol_app_escritura', 'detalle_pedido',           'SELECT'),
    ('rol_reportes',      'mv_ventas_categoria_mes',  'SELECT'),
    ('rol_soporte',       'vista_pedidos_cliente',    'SELECT'))
SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END AS grantee,
       c.relname, a.privilege_type
FROM pg_class c
CROSS JOIN LATERAL aclexplode(c.relacl) a
WHERE c.relnamespace = 'public'::regnamespace
  AND a.grantee <> c.relowner
  AND (CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
       c.relname, a.privilege_type) NOT IN (SELECT * FROM esperado);

-- b) Privilegios por columna que no están en la matriz.
SELECT a.attrelid::regclass AS tabla, a.attname, x.grantee::regrole AS grantee, x.privilege_type
FROM pg_attribute a
CROSS JOIN LATERAL aclexplode(a.attacl) x
WHERE a.attrelid::regclass::text = 'usuario'
  AND NOT (x.grantee = 'rol_soporte'::regrole AND x.privilege_type = 'SELECT'
           AND a.attname IN ('id', 'nombre', 'apellido', 'mail', 'rol'));

-- c) SECURITY DEFINER sin search_path fijo.
SELECT p.oid::regprocedure
FROM pg_proc p
WHERE p.prosecdef AND p.pronamespace = 'public'::regnamespace
  AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%');

-- d) Rutinas propias (no trigger, no extensión) ejecutables por PUBLIC.
SELECT p.oid::regprocedure
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.prorettype <> 'trigger'::regtype
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
                  AND d.objid = p.oid AND d.deptype = 'e')
  AND has_function_privilege('public', p.oid, 'EXECUTE');

-- e) Objetos de public que no son de admin_datos (excluye extensiones).
SELECT c.relname, pg_get_userbyid(c.relowner)
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND c.relowner <> 'admin_datos'::regrole;
```

Pruebas funcionales nuevas (dentro de `BEGIN … ROLLBACK`, porque escriben):
```sql
BEGIN;
SET ROLE app_web;
INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES (now(), 'EFECTIVO', 1); -- debe FALLAR (H1)
ROLLBACK;

BEGIN;
SET ROLE app_web;
CALL registrar_pedido(1, 'EFECTIVO', '[{"id_producto": 1, "cantidad": 1}]');      -- debe FUNCIONAR (F1)
ROLLBACK;

BEGIN;
SET ROLE rol_soporte;
SELECT fn_resetear_password((SELECT id FROM usuario WHERE rol = 'ADMIN' LIMIT 1), 'clave_nueva_123'); -- debe FALLAR (H4)
ROLLBACK;

SET ROLE rol_reportes_login;
SELECT count(*) FROM cliente;  -- debe FALLAR
RESET ROLE;
```
Además, en bd2_tp3, la consulta de H3.

---

## Si se aprueba este plan

No se modifica nada: el entregable es esta auditoría. Lo que sigue queda a cargo de la autora, según
AGENTS.md: Kiro ajusta `design.md` (§5.6); después se generan los cambios de §5 en una sesión limpia por spec,
se leen línea por línea y se ejecutan en `bd2_trabajo` con backup + `BEGIN … ROLLBACK` primero, y se registran
en el DUIA.
