# Informe de Auditoría — TP Unidad 5 (Parte B)

**Responsable:** Hernán González  
**Base de prueba:** `bd2_tp5u5` (copia de `bd2_tp4u4`)  
**Script de prueba:** `sql/auditoria_test.sql`  
**Evidencia de log:** `docs/log_auditoria_prueba.txt`

---

## 1. Parámetros de auditoría configurados en el servidor

Se activaron los parámetros de auditoría nativa a nivel de instancia mediante `ALTER SYSTEM` (que persiste los cambios en `postgresql.auto.conf`) y se aplicaron en caliente con `SELECT pg_reload_conf();`, sin reiniciar el servicio:

| Parámetro | Valor configurado | Propósito en la auditoría |
| --- | --- | --- |
| `logging_collector` | `'on'` | Habilita el proceso colector que captura `stderr` y escribe los eventos en archivos dentro del directorio `log/` de datos. |
| `log_connections` | `'on'` | Registra cada intento de conexión entrante, el método de autenticación aplicado (`scram-sha-256`), la regla de `pg_hba.conf` coincidente y la autorización de la sesión. |
| `log_disconnections` | `'on'` | Registra el cierre de cada sesión e informa la duración total (`session time`), usuario, base y dirección de origen. |
| `log_statement` | `'mod'` | Registra todas las sentencias DDL (`CREATE`, `ALTER`, `DROP`, `GRANT`, `REVOKE`) más las operaciones DML que modifican datos (`INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`). |
| `log_line_prefix` | `'%m [%p] %q%u@%d %r %a '` | Antepone en cada línea: marca de tiempo con milisegundos (`%m`), PID del proceso backend (`%p`), usuario y base (`%u@%d`), host/IP y puerto del cliente (`%r`) y aplicación cliente (`%a`). |

---

## 2. Secuencia de prueba ejecutada

Con `sql/auditoria_test.sql` se ejecutó dentro de un bloque `BEGIN; … ROLLBACK;` la siguiente secuencia sobre `bd2_tp5u5`, seguida de un intento de conexión con contraseña inválida desde consola:

1. **Lectura bajo `log_statement = 'mod'`:** `SELECT id_categoria, nombre, activo FROM categoria WHERE nombre = 'Panificados';` → **no aparece en el log**, comprobando que el nivel `'mod'` omite consultas de solo lectura.
2. **Lectura habilitando `'all'` localmente en la transacción (`SET LOCAL log_statement = 'all'`):** `SELECT id, mail, rol, eliminado FROM usuario WHERE id = 1;` → **sí queda registrada** en el log (`20:34:32.141`), tras lo cual se restablece `SET LOCAL log_statement = 'mod'`.
3. **Inserción (`INSERT`):** alta de la categoría `'Auditoria Prueba U5'` (`20:34:32.165`) → registrada por `'mod'`.
4. **Actualización (`UPDATE`):** baja lógica `SET activo = FALSE WHERE nombre = 'Auditoria Prueba U5'` (`20:34:32.166`) → registrada por `'mod'`.
5. **Desconexión:** cierre de la sesión `[18652]` con duración `0:00:00.240` (`20:34:32.167`).
6. **Intento de inicio de sesión fallido:** nueva conexión `[41436]` desde `::1(52682)` que produce `FATAL: la autentificación password falló para el usuario «postgres»` (`20:35:13.902`).

---

## 3. Análisis del fragmento de log: utilidad y límites frente a `pgaudit`

### Qué información útil aporta el fragmento capturado

| Dimensión | Evidencia en `docs/log_auditoria_prueba.txt` | Utilidad para reconstruir hechos |
| --- | --- | --- |
| **Cuándo** | `2026-10-23 20:34:31.953 -03` y `session time: 0:00:00.240` | Permite ordenar cronológicamente con precisión de milisegundos cada paso y medir cuánto duró abierta la sesión. |
| **Quién** | `postgres@bd2_tp5u5`, `identidad=«postgres» método=scram-sha-256` | Identifica el rol de base de datos que ejecutó las acciones (o la cuenta objetivo en el `FATAL` de autenticación fallida). |
| **Desde dónde** | `::1(52673)` / `::1(52682)`, aplicación `psql`, PID `[18652]` / `[41436]`, `pg_hba.conf:117` | Informa la IP y el puerto origen del cliente, el programa utilizado y el PID que vincula todas las sentencias de una misma conexión. |
| **Qué** | `LOG: statement: INSERT...`, `UPDATE...`, `SELECT...` y `FATAL: la autentificación password falló...` | Muestra el texto SQL exacto enviado al motor y los fallos de autenticación. |

### Qué queda fuera del alcance del mecanismo nativo (y qué resolvería `pgaudit`)

1. **Falta de granularidad por objeto en lecturas (todo o nada):** Con `log_statement = 'mod'` las lecturas (`SELECT`) no dejan rastro (un atacante o usuario interno podría extraer toda la tabla `usuario` sin aparecer en el log). Si se cambia globalmente a `log_statement = 'all'`, se registran absolutamente todos los `SELECT` de todas las tablas y catálogos, degradando el rendimiento y generando un volumen de log inmanejable. La extensión **`pgaudit`** permite auditar por objeto (`Object Audit Logging`), registrando `SELECT` únicamente sobre tablas críticas (como `usuario` o `cliente`) sin auditar el resto del esquema.
2. **Sin detalle fila por fila ni valores antes/después:** El log nativo solo registra el texto de la consulta enviada; no indica cuántas filas devolvió un `SELECT`, qué registros concretos fueron alcanzados por un `WHERE`, ni los valores previos (`OLD`) y nuevos (`NEW`) de cada fila modificada por un `UPDATE` o `DELETE` (ni siquiera explicita en la línea del `INSERT`/`UPDATE` que la transacción terminó luego en `ROLLBACK` si no se audita el cierre transaccional).
3. **Consultas dentro de funciones y clasificación estructurada:** Cuando una aplicación opera a través de funciones (como `fn_autenticar` o `fn_resetear_password`), el log nativo solo muestra la llamada exterior, mientras que `pgaudit` desglosa las sentencias ejecutadas internamente y etiqueta cada evento por categoría (`READ`, `WRITE`, `DDL`, `ROLE`) y objeto afectado.

---

## 4. El archivo de log como activo sensible y permisos de acceso

Sí, el archivo de log es en sí mismo un **activo altamente sensible**, ya que almacena en texto claro las consultas ejecutadas —que suelen contener datos personales como correos, nombres o teléfonos en cláusulas `INSERT` y `WHERE`, e incluso credenciales si un administrador ejecuta un comando con contraseña literal— además de exponer la estructura de tablas, nombres de usuarios, direcciones IP y rutas internas del servidor (`pg_hba.conf`). Por el principio de mínimo privilegio y de separación de funciones, solo deberían poder leerlo la cuenta de sistema operativo del servicio PostgreSQL y el personal autorizado de administración o seguridad/auditoría, nunca los roles operativos de la aplicación (`app_web`, `rol_app_lectura`, `rol_app_escritura`). En el sistema operativo debe resguardarse con permisos exclusivos para la cuenta del servicio y administradores (`log_file_mode = 0600` en sistemas POSIX o ACL restringida en Windows), y dentro del motor el uso de funciones de lectura del sistema de archivos (`pg_read_file`, `pg_read_binary_file`) debe permanecer restringido a superusuarios o a un rol de auditoría específico mediante `pg_read_server_files`.
