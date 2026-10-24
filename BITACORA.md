# Bitácora de uso de IA — TP Unidad 5

Registro de cada interacción relevante con la IA (OpenCode, Kiro, Claude Code) del TP de la Unidad 5 (roles, auditoría, incidentes y protección de datos). Cada integrante completa **solo la sección de su parte**, así los cambios de cada uno no se pisan al mezclar las ramas. La Parte E consolida todo al final.

Requisitos del enunciado: un registro por cada parte en la que se usó OpenCode, y señalar al menos un caso en el que la IA propuso algo incorrecto, inseguro o de más, y cómo se detectó y corrigió. Si se usa una herramienta distinta de OpenCode, se declara.

## Parte A — Roles y permisos de mínimo privilegio

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte B — Activación y prueba de la auditoría

*Nota de herramienta:* En esta parte se utilizó el asistente de IA en entorno de desarrollo siguiendo el flujo de modo Plan y validación en motor sobre `bd2_tp5u5`.

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| Proponer el plan y el script `sql/auditoria_test.sql` para activar los parámetros de auditoría de la Parte B (`log_connections`, `log_disconnections`, `log_statement`) y ejecutar la secuencia de prueba (lectura, inserción, actualización e intento de login fallido) sobre `bd2_tp5u5`. | Propuso activar `logging_collector = 'on'`, `log_connections = 'on'`, `log_disconnections = 'on'`, `log_statement = 'mod'` y `log_line_prefix = '%m [%p] %q%u@%d %r %a '` con `ALTER SYSTEM` y `pg_reload_conf()`, reconectar con `\c bd2_tp5u5` y ejecutar un bloque `BEGIN … ROLLBACK` con un `SELECT`, un `INSERT` y un `UPDATE`. Para que la lectura también se viera en el log, planteó pasar `log_statement` a `'all'`. | **Corregido (exceso de alcance si se deja `'all'` global):** Dejar `log_statement = 'all'` a nivel servidor con `ALTER SYSTEM` auditaría todas las lecturas de todas las bases y catálogos, exponiendo datos en cada `SELECT` y llenando el log. Se mantuvo `log_statement = 'mod'` a nivel servidor (como pide la consigna) y se ejecutó primero un `SELECT` sobre `categoria` (para comprobar que `'mod'` no lo registra) y luego un `SET LOCAL log_statement = 'all'` acotado solo a un `SELECT` de prueba dentro de la transacción antes de volver a `'mod'`. |
| Proponer un comando de `psql` para leer las últimas líneas del archivo de log activo (`pg_current_logfile()`) luego de provocar el intento de inicio de sesión fallido. | Propuso ejecutar `SELECT pg_read_file(pg_current_logfile(), GREATEST(0, (pg_stat_file(pg_current_logfile())).size - 4096), 4096);`. | **Incorrecto (detectado al ejecutar en el motor):** Al correrlo en `bd2_tp5u5`, PostgreSQL devolvió `ERROR: secuencia de bytes no válida para codificación «UTF8»: 0xf3 0x6e 0x20 0x72`. La IA asumió que el archivo de log estaba en `UTF8`, pero en Windows (`Spanish_Argentina.1252`) el colector escribe los mensajes del servidor (`"conexión recibida"`, `"autentificación"`) en `WIN1252`. Se corrigió leyendo el archivo con codificación `Windows-1252` (`convert_from(pg_read_binary_file(...), 'WIN1252')` / `Get-Content -Encoding Default`) y se actualizó la nota en `sql/auditoria_test.sql`. |
| Redactar `docs/informe_auditoria.md` (puntos 1, 3 y 4 de la Parte B) a partir del fragmento real capturado en `docs/log_auditoria_prueba.txt`. | Redactó la tabla de parámetros configurados, el análisis de qué aporta el fragmento (quién, qué, cuándo, desde dónde), las tres limitaciones del log nativo frente a `pgaudit` y la respuesta de tres oraciones del punto 4 sobre el log como activo sensible y sus permisos en SO y motor. | **Aceptado tras revisión:** Se verificó que los timestamps (`20:34:31` y `20:35:13`), los PIDs (`[18652]` y `[41436]`) y los mensajes citados en el informe coincidan exactamente con las líneas de `docs/log_auditoria_prueba.txt`. |

## Parte C — Simulacro de incidente de acceso indebido

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte D — Anonimización y verificación de equivalencia

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| | | |

## Parte E — Cierre

### Caso más significativo de error o imprecisión de la IA

*Pendiente (Parte E, punto 2).*

### Nota sobre el historial de Git

*Pendiente (Parte E, punto 3).*
