# Revisión de código asistida por IA — Unidad 5 (Seguridad, roles y auditoría)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `base-datos-2`
**Base de comprobación:** `bd2_tp5u5` (dentro de `BEGIN … ROLLBACK`) y Git Bash (`bash -n`)

---

## 1. Alcance de la revisión (9 scripts de la Unidad 5)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `sql/funciones_auth.sql` | Extensión `pgcrypto`, `fn_autenticar` y `fn_resetear_password` (`SECURITY DEFINER`, `search_path = public, pg_temp`) | Revisado y corregido | Hallazgo 4 |
| `sql/mv_ventas_categoria_mes.sql` | Vista materializada `mv_ventas_categoria_mes` para el rol de reportes gerenciales | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.1) |
| `sql/roles.sql` | Modelo de mínimo privilegio: 4 roles de grupo `NOLOGIN`, 3 roles de login, `REVOKE` de `PUBLIC` y `GRANT` granulares | Revisado y corregido | Hallazgo 1 |
| `sql/verificacion_roles.sql` | Auditoría de catálogos (`\du`, `role_table_grants`, `role_column_grants`, `\dp`, `\ddp`) y pruebas funcionales con `SET ROLE` en `ROLLBACK` | Revisado y actualizado (08/11/2026) | Hallazgo 16 |
| `sql/auditoria_test.sql` | Configuración de `logging_collector`, `log_connections`, `log_disconnections`, `log_statement = 'mod'` y lectura del log en `WIN1252` | Revisado y corregido | Hallazgo 5 |
| `sql/simulacro_incidente.sql` | Simulacro controlado sobre `bd2_tp5u5`: 3 logins fallidos, 1 exitoso, intento de lectura masiva de `usuario` e intento de escalada a `admin_datos` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.2) |
| `sql/simulacro_limpieza.sql` | Restaura `log_statement = 'mod'`, verifica membresías y elimina los usuarios sintéticos `@example.test` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.2) |
| `sql/anonimizar_log.sh` | Recorta el tramo `INICIO_SIMULACRO_U5`..`FIN_SIMULACRO_U5` y anonimiza mails, claves, puertos, IPs y rutas antes de enviar el log a una IA | Revisado con propuesta descartada (08/11/2026) | Hallazgo 16 |
| `sql/usuario_anon.sql` | Crea y puebla `usuario_anon` con datos sintéticos deterministas sin contraseñas ni datos personales reales | Revisado con propuesta descartada (08/11/2026) | Hallazgo 16 |

---

## 2. Revisión detallada de los scripts pendientes

### 2.1 `sql/mv_ventas_categoria_mes.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Es idempotente (`DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_mes;`).
  - No filtra por `c.activo = TRUE` ni `p.activo = TRUE`: a diferencia del catálogo vivo, el reporte contable histórico debe conservar las ventas pasadas aunque el producto o la categoría se hayan dado de baja posteriormente.
  - No incluye sentencias `GRANT` dentro del script de creación: delega todos los permisos a `sql/roles.sql` para mantener un único punto de administración de seguridad.

### 2.2 `sql/simulacro_incidente.sql` y `sql/simulacro_limpieza.sql` — Revisados sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Ambos scripts confirman la base inicial con `SELECT current_database();` y operan exclusivamente sobre `bd2_tp5u5`.
  - `simulacro_incidente.sql` no guarda la contraseña de `postgres` en el archivo (documenta el uso de variable de sesión o `pgpass.conf`), usa el dominio reservado RFC 2606 `@example.test` para los 301 usuarios sintéticos, delimita el tramo del log con las marcas `INICIO_SIMULACRO_U5` y `FIN_SIMULACRO_U5` y verifica al cierre que `pg_auth_members` devuelva `0 filas` para `admin_datos`.
  - `simulacro_limpieza.sql` restablece `ALTER SYSTEM SET log_statement = 'mod'; SELECT pg_reload_conf();`, incluye una guarda defensiva con `pg_has_role('app_web', 'admin_datos', 'MEMBER')` por si el escalamiento hubiera prosperado, borra únicamente las filas `WHERE mail LIKE '%@example.test'` y comprueba que queden `0` usuarios de prueba.

### 2.3 `sql/anonimizar_log.sh`, `sql/usuario_anon.sql` y `sql/verificacion_roles.sql` — Hallazgo 16

- **Propuesta 1 de la IA (en `sql/anonimizar_log.sh`):** reemplazar el segundo argumento de `fn_autenticar(mail, clave)` por una máscara fija `'***'` y usar una expresión regular general `s/[A-Za-z0-9._%+-]+@[A-Za-z0-9_-]+/ redactado /g` para anonimizar direcciones de correo.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en Git Bash sobre el formato real del log (`docs/log_simulacro_anonimizado.txt`):**
    1. Si todas las contraseñas fallidas se reemplazan por la misma cadena fija `'***'`, quien audita el log anonimizado pierde la información de si los 3 fallos fueron reintentos automáticos con la misma clave o un ataque probando claves distintas. La función `anon_clave()` de `anonimizar_log.sh` (líneas 70–73) asigna alias numerados estables (`CLAVE_REDACTADA_1`, `CLAVE_REDACTADA_2`, `CLAVE_REDACTADA_3`, `CLAVE_REDACTADA_4`), ocultando el secreto real pero preservando la cardinalidad de intentos distintos.
    2. El `log_line_prefix` configurado en la Parte B es `'%m [%p] %q%u@%d %r %a '`, que imprime `app_web@bd2_tp5u5` y `postgres@bd2_tp5u5`. Una expresión regular de correo que no exija al menos un punto en el dominio (`(\.[A-Za-z0-9-]+)+`, línea 92) confunde `app_web@bd2_tp5u5` con un email y sobreescribe el rol y la base en todas las líneas del log, impidiendo identificar con qué cuenta de motor se ejecutó el ataque.

- **Propuesta 2 de la IA (en `sql/usuario_anon.sql`):** definir `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` en `usuario_anon` y generar el campo `contrasena` llamando a `crypt('anon_' || id, gen_salt('bf'))` por cada fila.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en `bd2_tp5u5`:** si `id` es `IDENTITY`, cualquier hueco en la numeración de `usuario` desalinea los `id` entre `usuario` y `usuario_anon` a menos que se fuerce `OVERRIDING SYSTEM VALUE`, y además calcular 303 hashes Blowfish (`gen_salt('bf')`) agrega costo de CPU innecesario y produce hashes reales válidos que dependen de una semilla aleatoria en cada corrida. El script actual copia `id` de forma determinista y fija `'hash_no_valido'` (que nunca coincide con la salida de `crypt()`, inhabilitando por completo la autenticación sobre la tabla anonimizada), lo que se verifica en la consulta de control 2 (`filas_con_datos_reales_o_hash_invalido = 0`).

- **Corrección aplicada en `sql/verificacion_roles.sql` (integrada con el Bloque B):**
  - Al ampliar `sql/verificacion_roles.sql` para comprobar en motor las decisiones de `docs/decisiones_auditoria_roles.md`, la subconsulta propuesta inicialmente para probar `H4` como `rol_soporte` filtraba `WHERE rol = 'USUARIO' AND eliminado = FALSE`, lo cual fallaba con `ERROR: permiso denegado a la tabla usuario` porque `rol_soporte` no tiene permiso `SELECT` sobre la columna `eliminado` (`F3`). Se corrigió quitando `AND eliminado = FALSE` de la subconsulta exterior (la función `fn_resetear_password` ya lo verifica internamente como `SECURITY DEFINER`), quedando comprobado en `docs/verificacion_roles.txt`.
