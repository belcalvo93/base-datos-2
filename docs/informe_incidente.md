# Informe de incidente — TP Unidad 5 (Parte C)

**Responsable:** Elías Tello
**Base de prueba:** `bd2_tp5u5` (copia de `bd2_tp4u4`), instancia local de desarrollo
**Versión del servidor:** *(completar con `SELECT version();`; el enunciado pide PostgreSQL 16 o superior)*
**Script del simulacro:** `sql/simulacro_incidente.sql`
**Limpieza posterior:** `sql/simulacro_limpieza.sql`
**Anonimizador del log:** `sql/anonimizar_log.sh`
**Log anonimizado:** `docs/log_simulacro_anonimizado.txt`

Todo el simulacro se ejecutó exclusivamente contra el entorno de desarrollo propio, sin tocar bases de otros equipos ni sistemas de terceros.

---

## 1. Escenario

Se simula un incidente de acceso indebido a través de la cuenta de aplicación `app_web`: alguien prueba claves contra `fn_autenticar`, consigue (o no) entrar, intenta leer toda la tabla `usuario` y, por último, intenta escalar privilegios hacia `admin_datos`.

Preparación (como `postgres`, antes de la marca `INICIO_SIMULACRO_U5`):

- Se creó un usuario de prueba con hash bcrypt real (`victima.prueba@example.test`, `id 4`), porque los usuarios de `data.sql` tienen hashes de relleno y no sirven para un login exitoso.
- Se cargaron 300 usuarios sintéticos (dominio reservado `.test`), para que la lectura masiva fuera realmente masiva: 304 usuarios en total, contando los 3 que ya había.
- Se subió `log_statement` a `all` durante la corrida. Con el nivel `mod` de la Parte B las llamadas a `fn_autenticar` y las lecturas (`SELECT`) no quedan registradas. Al terminar se vuelve a `mod` con `sql/simulacro_limpieza.sql`.

## 2. Secuencia ejecutada

| Paso | Acción | Rol | Resultado esperado | Resultado obtenido |
|---|---|---|---|---|
| 1 | 3 llamadas a `fn_autenticar` con clave incorrecta, cada una en una conexión nueva (R5 de la especificación de Kiro) | `app_web` | 0 filas | 0 filas las tres veces |
| 2 | 1 llamada a `fn_autenticar` con la clave correcta | `app_web` | 1 fila (`id`, `rol`) | 1 fila: `id 4`, rol `USUARIO` |
| 3 | `SELECT * FROM usuario` y `SELECT count(*) FROM usuario` | `app_web` | Permiso denegado | `ERROR: permiso denegado a la tabla usuario`, las dos veces |
| 4 | `GRANT admin_datos TO app_web` y `SET ROLE admin_datos` | `app_web` | Error | Ambos con `ERROR` (ver punto 3) |

## 3. Resultado del escalamiento

**El intento de escalamiento falló**, como prevé el diseño de la Parte A. No hay hallazgo. Salida de `psql`:

```text
psql:sql/simulacro_incidente.sql:96: ERROR:  se ha denegado el permiso para otorgar el rol «admin_datos»
DETALLE:  Sólo los roles con la opción ADMIN en el rol «admin_datos» pueden otorgar este rol.
psql:sql/simulacro_incidente.sql:97: ERROR:  se ha denegado el permiso para definir el rol «admin_datos»
```

Constancia posterior (como `postgres`): la consulta sobre `pg_auth_members` para el rol `admin_datos` devolvió **0 filas**; ningún rol de bajo privilegio quedó como miembro.

La lectura masiva también falló: `app_web` no tiene `SELECT` sobre `usuario` (solo `EXECUTE` sobre `fn_autenticar`, que corre como `SECURITY DEFINER`).

## 4. Anonimización del log

El log crudo se recortó entre las marcas `INICIO_SIMULACRO_U5` y `FIN_SIMULACRO_U5` y se anonimizó con `sql/anonimizar_log.sh` antes de dárselo a la IA. El script reemplaza:

- mails por alias sintéticos (`usuario_NNN@ejemplo.test`; el mismo mail recibe siempre el mismo alias);
- la contraseña del segundo argumento de `fn_autenticar` por `CLAVE_REDACTADA_N` (una contraseña distinta recibe un `N` distinto: se oculta el secreto pero se conserva que los intentos no son todos iguales);
- los puertos por `PUERTO`, las IP que no son loopback por `IP_ANONIMA` y la ruta del `pg_hba.conf` por `<RUTA>`.

También repara las tildes, porque el log mezcla mensajes en UTF-8 y en WIN1252. Se conservan marcas de tiempo y PID, porque sin ellos no se puede reconstruir la secuencia. El log crudo no se guarda en el repositorio.

Después del script se revisó a mano: no queda ningún mail, nombre, contraseña, IP ni ruta de la máquina, y el archivo tiene 39 líneas.

## 5. Respuesta completa de la IA

Herramienta: OpenCode, modo Plan, sesión nueva. Modelo: *(completar)*.

Prompt: se le entregó únicamente el contenido de `docs/log_simulacro_anonimizado.txt`, con el pedido de reconstruir lo ocurrido paso a paso y de proponer una hipótesis de contención, sin agregar contexto adicional.

Respuesta, sin recortar:

```text
Reconstrucción Paso a Paso

1. Inicio del Simulacro (`19:46:48.258`):
   * El usuario administrativo `postgres` se conecta a la base de datos `bd2_tp5u5` y deja constancia del inicio de la prueba: `SELECT 'INICIO_SIMULACRO_U5' AS marca;`.
2. Fase de Fuerza Bruta / Credential Stuffing (`19:46:48.283` – `19:46:48.411`):
   * El usuario de aplicación `app_web` abre múltiples conexiones consecutivas desde la IP local (`::1`) utilizando autenticación SCRAM-SHA-256.
   * En cada sesión, ejecuta repetidamente la función de validación con diferentes credenciales (`SELECT * FROM fn_autenticar('usuario_001@ejemplo.test', 'CLAVE_REDACTADA_N');`). Esto evidencia un ataque automatizado de fuerza bruta o prueba de credenciales.
3. Intento de Exfiltración y Exploración de Datos (`19:46:48.419`):
   * Al comprometer o avanzar en la sesión (`pid 7024`), el atacante intenta consultar directamente información sensible de la tabla de usuarios:
      * `SELECT * FROM usuario;` $\rightarrow$ Denegado por permisos.
      * `SELECT count(*) FROM usuario;` $\rightarrow$ Denegado por permisos.
4. Intento de Escalamiento de Privilegios (`19:46:48.420`):
   * Ante el bloqueo de lectura directa, el actor intenta elevar sus privilegios en el motor de base de datos:
      * `GRANT admin_datos TO app_web;` $\rightarrow$ Rechazado (requiere opción `ADMIN`).
      * `SET ROLE admin_datos;` $\rightarrow$ Rechazado (permiso denegado para definir dicho rol).
5. Finalización del Simulacro (`19:46:48.452`):
   * Un usuario con privilegios elevados (`postgres`) se conecta al finalizar y registra la marca de cierre: `SELECT 'FIN_SIMULACRO_U5' AS marca;`.

Hipótesis de Contención y Mitigación
Ante un escenario de fuerza bruta de autenticación combinada con intentos de escalamiento de privilegios, se proponen las siguientes medidas de contención:

1. Aislamiento y Revocación Inmediata:
   * Terminar las sesiones activas del rol `app_web` sospechoso utilizando `pg_terminate_backend(pid)`.
   * Rotar inmediatamente las credenciales (contraseña SCRAM) del usuario `app_web` en la base de datos y en los secretos de la aplicación.
2. Limitación de Tasas (Rate Limiting) y Bloqueo de Origen:
   * Implementar un mecanismo de bloqueo temporal por IP o cuenta en la capa de aplicación (o mediante extensiones/firewalls a nivel de red como `fail2ban`) tras detectar un umbral de llamadas fallidas consecutivas a `fn_autenticar`.
3. Auditoría de Funciones (`SECURITY DEFINER`):
   * Revisar que la función `fn_autenticar` no esté exponiendo información privilegiada (como hashes de contraseñas o datos de usuarios inactivos) mediante fugas de errores o tiempos de respuesta diferenciales.
4. Monitoreo y Alertas en Tiempo Real (SIEM):
   * Configurar alertas automáticas ante patrones anómalos en los logs de PostgreSQL, específicamente ante ráfagas de conexiones cortas seguidas de errores de permisos (`permiso denegado`) o intentos fallidos de comandos `GRANT` / `SET ROLE`.
```

## 6. Contraste entre la reconstrucción de la IA y lo ejecutado

| Qué acertó la IA | Qué omitió | Qué afirmó sin sustento en el log |
|---|---|---|
| La secuencia y las horas: marca de inicio (19:46:48.258), conexiones de `app_web` con SCRAM (19:46:48.283 a .411), lecturas denegadas (.419), `GRANT` y `SET ROLE` rechazados (.420) y marca de cierre (.452). | Que el log del motor **no registra el resultado de `fn_autenticar`**: los cuatro intentos aparecen idénticos como `SELECT`, así que no se puede saber cuáles fallaron ni si alguno entró. No recomendó verificarlo en la aplicación. | **"Fuerza bruta / credential stuffing".** Son 4 intentos en unos 130 ms contra **una sola cuenta**. El credential stuffing prueba credenciales filtradas contra muchas cuentas, y la fuerza bruta implica volumen. Lo único respaldado por el log es que fueron repetidos y automatizados (intervalos de unos 40 ms). |
| Que la lectura y el escalamiento ocurrieron en la misma sesión (`pid 7024`) que el último `fn_autenticar`. | Que **no hubo impacto**: ningún dato leído y ningún privilegio cambiado; todo lo hostil terminó en `ERROR`. No cerró el balance del incidente. | **"Al comprometer o avanzar en la sesión".** El log no muestra que el inicio de sesión haya sido exitoso; la IA lo da por hecho. |
| Que ambas acciones fueron rechazadas y por qué (permiso denegado; falta la opción `ADMIN`). | Que **todas las conexiones, incluidas las de `postgres`, vienen del mismo origen (`::1`)**: el "atacante" y el administrador comparten origen, lo que en un caso real sería un dato importante. | **La intención** ("el atacante intenta", "ante el bloqueo… intenta elevar"). El log da el orden de los hechos, no el motivo. |
| Las medidas de límite de intentos por cuenta u origen y las alertas sobre ráfagas de `permiso denegado`. | Las desconexiones y la duración de cada sesión (unos 59 ms), la fecha y la zona horaria. | **Contención que no cuadra con el log:** terminar con `pg_terminate_backend` sesiones de `app_web` que según el log **ya se habían cerrado** (el `pid 7024` se desconectó a las 19:46:48.452); **rotar la contraseña de `app_web`**, que es la cuenta que usa la propia aplicación (apuntaría a la cuenta equivocada y tumbaría la aplicación), cuando el log señala a `usuario_001`, un usuario de la aplicación; y auditar **fugas por errores o tiempos** en `fn_autenticar`, sin ninguna evidencia en el log. |
| | Que los intentos apuntan a **una única cuenta** (`usuario_001`): mencionó el alias pero no sacó la consecuencia sobre el alcance. | |

**Un detalle sobre el contexto.** Las marcas `INICIO_SIMULACRO_U5` y `FIN_SIMULACRO_U5` quedaron dentro del log y la IA las recogió ("Inicio del Simulacro", "Finalización del Simulacro"). Eso le dio contexto que el enunciado pide no darle. Se necesitaban para recortar el log, y quedó anotado como mejora (punto 8).

## 7. Decisión de contención

Con la evidencia de este log, el equipo decide lo siguiente para un caso real:

1. **Verificar primero en los registros de la aplicación si alguno de los 4 intentos contra la cuenta `usuario_001` tuvo éxito**, porque el log del motor no lo dice. Solo si hubo un acceso exitoso se trata la cuenta como comprometida: forzar el cambio de contraseña (con `fn_resetear_password`, que está permitido para cuentas con rol `USUARIO`) e invalidar sus sesiones.
2. **Limitar los intentos por cuenta y por origen en la aplicación** (bloqueo temporal tras N fallos consecutivos). El motor no puede hacerlo por sí solo: `fn_autenticar` responde "sin filas" y no un error de autenticación.
3. **No rotar la contraseña de `app_web` ni terminar sesiones por ahora.** No hay evidencia de que esa cuenta esté comprometida, y las sesiones ya estaban cerradas.
4. **Mantener el diseño de permisos de la Parte A.** La lectura masiva y el escalamiento fallaron; no hace falta revertir roles.
5. **Registrar los intentos fallidos de `fn_autenticar` en una tabla de auditoría**, como mejora futura, para no depender del nivel de log del servidor.

Esta decisión es del equipo, tomada a partir de la evidencia del log y del contraste del punto 6. No es una acción ejecutada automáticamente a partir de lo que sugirió la IA.

## 8. Qué hacer distinto

- Con `log_statement = 'mod'` las llamadas a `fn_autenticar` y las lecturas **no quedan registradas**. Para el simulacro hubo que subir a `all`, y aun así el log no distingue un intento fallido de uno exitoso.
- Las marcas del script le dieron contexto a la IA. La próxima vez conviene reemplazarlas en el anonimizador por etiquetas neutras antes de entregar el log.
- Conviene registrar el resultado de la autenticación (éxito o fallo) en algún lugar que el motor sí deje en el log, por ejemplo con un `RAISE LOG` dentro de la función.
