# Informe de incidente — TP Unidad 5 (Parte C)

**Responsable:** Elías Tello
**Base de prueba:** `bd2_tp5u5` (copia de `bd2_tp4u4`), instancia local de desarrollo
**Versión del servidor:** *(completar con `SELECT version();`; el enunciado pide PostgreSQL 16 o superior)*
**Script del simulacro:** `sql/simulacro_incidente.sql`
**Limpieza posterior:** `sql/simulacro_limpieza.sql`
**Log anonimizado:** `docs/log_simulacro_anonimizado.txt`

Todo el simulacro se ejecutó exclusivamente contra el entorno de desarrollo propio, sin tocar bases de otros equipos ni sistemas de terceros.

---

## 1. Escenario

Se simula un incidente de acceso indebido a través de la cuenta de aplicación `app_web`: un atacante prueba claves contra `fn_autenticar`, consigue entrar, intenta leer toda la tabla `usuario` y, por último, intenta escalar privilegios hacia `admin_datos`.

*(Completar: qué usuario de prueba se creó, cuántos usuarios sintéticos se cargaron y con qué nivel de `log_statement` se corrió.)*

## 2. Secuencia ejecutada

| Paso | Acción | Rol | Resultado esperado |
|---|---|---|---|
| 1 | 3 llamadas a `fn_autenticar` con clave incorrecta, cada una en una conexión nueva (R5 de la especificación de Kiro) | `app_web` | 0 filas |
| 2 | 1 llamada a `fn_autenticar` con la clave correcta | `app_web` | 1 fila (`id`, `rol`) |
| 3 | `SELECT * FROM usuario` y `SELECT count(*) FROM usuario` | `app_web` | Permiso denegado |
| 4 | `GRANT admin_datos TO app_web` y `SET ROLE admin_datos` | `app_web` | Error |

*(Completar con lo que realmente ocurrió, pegando la salida de `psql`.)*

## 3. Resultado del escalamiento

*(Completar. El enunciado pide dejar constancia de si el intento de escalamiento falló. Pegar el mensaje de error y el resultado de la consulta de membresías de `admin_datos`, que debe dar 0 filas. Si NO falló, es un hallazgo: señalar el defecto de la Parte A y cómo se corrigió.)*

## 4. Anonimización del log

El log crudo se recortó entre las marcas `INICIO_SIMULACRO_U5` y `FIN_SIMULACRO_U5` y se anonimizó con `sql/anonimizar_log.sh` antes de dárselo a la IA. El script reemplaza mails por alias sintéticos (`usuario_NNN@ejemplo.test`), la contraseña del segundo argumento de `fn_autenticar` por `CLAVE_REDACTADA`, los puertos por `PUERTO`, las IP que no son loopback por `IP_ANONIMA` y la ruta del `pg_hba.conf` por `<RUTA>`. Se conservan marcas de tiempo y PID, porque sin ellos no se puede reconstruir la secuencia. El log crudo no se guarda en el repositorio.

*(Completar: qué se revisó a mano después del script y si quedó algo por corregir.)*

## 5. Respuesta completa de la IA

*(Pegar acá, sin recortar, la respuesta de OpenCode. Indicar el modelo y si el prompt incluyó solo el log anonimizado y el pedido de reconstruir y proponer una hipótesis de contención.)*

## 6. Contraste entre la reconstrucción de la IA y lo ejecutado

| Qué acertó la IA | Qué omitió | Qué afirmó sin sustento en el log |
|---|---|---|
| | | |

*(Completar. Mirar en particular: fechas u horas mal inferidas, causas asumidas sin evidencia, pasos que el log no registra y confusión entre un intento fallido y uno exitoso.)*

## 7. Decisión de contención

*(Completar con la medida que tomaría el equipo en un caso real: bloquear el origen, revertir un rol, forzar el cambio de contraseñas u otra.)*

Esta decisión es del equipo, tomada a partir de la evidencia del log y del contraste del punto 6. No es una acción ejecutada automáticamente a partir de lo que sugirió la IA.

## 8. Qué hacer distinto

*(Opcional: límites del log nativo que se vieron durante el simulacro, por ejemplo que con `log_statement = 'mod'` las llamadas a `fn_autenticar` y las lecturas no quedan registradas.)*
