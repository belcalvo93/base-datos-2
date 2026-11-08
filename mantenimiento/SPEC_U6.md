# SPEC_U6 — Plan de mantenimiento de Food Store

**Motor:** PostgreSQL 17.11 (cumple 16+) sobre Windows 11 · **Terminal:** Git Bash
**Base principal:** `foodstore` (copia de `bd2_tp3`) · **Base de restauración:** `foodstore_restore_test`

## Tareas automatizadas

| Tarea | Archivo | Frecuencia | Condición de éxito (evidencia) |
|-------|---------|-----------|--------------------------------|
| Respaldo de `foodstore` | `backup_foodstore.sh` | Diaria | `pg_dump` termina con código 0, existe `.dump` con tamaño > 0, verificación `pg_restore -l` exitosa, SHA256 en `.sha256`, y el log registra `PASS` con tamaño y hash |
| Chequeo de salud | `health_check.sql` | Diaria | La salida muestra los 4 controles: tamaño, conexiones, estado de tablas y consultas activas |
| Revisión de mantenimiento | `maintenance.sql` | Semanal | Se registran tuplas muertas, último autovacuum/autoanalyze y la acción tomada con su justificación |
| Restauración de prueba | `restore_test.sh` | Semanal | Verificación SHA256 antes de restaurar, autorización escrita en log, `current_database()` del destino confirmada, `pg_restore --exit-on-error`, huella restaurada = respaldo, 8 indicadores de integridad en 0 |

## Requisitos del respaldo

1. **Formato custom** (`-Fc`), para poder restaurar con `pg_restore`.
2. **Nombre con fecha y hora**: `foodstore_AAAAMMDD_HHMMSS.dump`.
3. **Huella de referencia** (`.conteo`): generada con `conteo_referencia.sql` antes del respaldo - filas por tabla, total facturado (suma de `cantidad * precio_unitario`), estructura (tablas, vistas, restricciones, índices).
4. **Verificación inmediata**: `pg_restore -l` apenas se genera para validar que el archivo no esté corrupto.
5. **SHA256**: hash del `.dump` guardado en archivo `.sha256` (formato de `sha256sum`: hash y nombre del archivo).
6. **Log**: cada ejecución agrega una línea en `logs/backup_foodstore.log` con `PASS`/`FAIL`, tamaño en bytes, hash SHA256, cantidad de objetos en el TOC, nombre del `.conteo` y tiempo de ejecución.
7. Si `pg_dump` o `pg_restore -l` fallan, el script registra `FAIL`, borra archivos incompletos y termina con código != 0.

## Reglas de seguridad

- **Sin contraseñas** en scripts ni en el repo: la clave va en `%APPDATA%\postgresql\pgpass.conf` o en la variable `PGPASSWORD` de la sesión. `.env` y `*.dump` no se versionan.
- **`foodstore` nunca se elimina ni se reemplaza.** Los comandos destructivos (`dropdb`, `pg_restore`) solo apuntan a `foodstore_restore_test`. Antes de ejecutar, se confirma con `SELECT current_database();`.
- **Autorización escrita** antes de borrar `foodstore_restore_test`: el script pide confirmación y la registra en `logs/restore_test.log`.
- **Verificación SHA256** antes de restaurar: si el hash no coincide con `.sha256`, se aborta.

## Mantenimiento (maintenance.sql)

- **ANALYZE/VACUUM solo si el diagnóstico lo justifica**: se ejecutan solo cuando las métricas superan los umbrales de autovacuum (`threshold + scale_factor * filas`).
- **Nunca VACUUM FULL**: bloquea la tabla con ACCESS EXCLUSIVE.
- **Estado antes y después**: mostrar `last_vacuum`, `last_autovacuum`, `last_analyze` y `last_autoanalyze` de cada tabla antes y después de cualquier acción.

## Validaciones posteriores a la restauración

1. **Huella igual al respaldo**: salida de `conteo_referencia.sql` en la base restaurada debe ser idéntica a la del archivo `.conteo`.
2. **8 indicadores de integridad** (todos deben ser 0):
   - precio negativo, stock negativo, cantidad no positiva, precio_unitario negativo
   - detalle sin pedido, detalle sin producto, pedido sin cliente, producto sin categoría

## Alcance de la restauración

- **No recupera roles ni permisos**: usa `--no-owner --no-privileges`.
- **Roles y permisos**: se respaldan aparte con `pg_dumpall --globals-only --no-role-passwords` (ver "Programación y retención").

## Objetivos de recuperación (laboratorio)

- **RPO previsto:** 24 h (un respaldo diario; como máximo se pierde un día de cambios).
- **RTO previsto:** 15 min (crear la base, restaurar y validar).
- Se mide el RTO observado con cronómetro: empieza antes de `createdb foodstore_restore_test` y termina cuando pasan las validaciones. El RPO observado es la antigüedad del respaldo usado al momento del simulacro.

## Uso de OpenCode

OpenCode puede generar la primera versión de los scripts a partir de este SPEC y de `AGENTS.md`. Cada comando se lee, se entiende y se prueba a mano antes de aceptarlo. Las correcciones se anotan en el informe.

## Programación y retención (TPI Parcial II)

**Objetivo:** que el respaldo corra solo todos los días, sin que nadie lo dispare a mano, y que no llene el disco. Cumple el objetivo 7 de la consigna (respaldo programado).

### Programación

- **Herramienta:** Programador de tareas de Windows. La tarea se llama `FoodStore_Backup_Diario`. La crea `programar_respaldo.ps1` y la borra `quitar_respaldo.ps1`.
- **Frecuencia y hora:** diaria, 21:00 hora local. Coincide con el RPO previsto de 24 h.
- **PC apagada a esa hora:** la tarea corre apenas se pueda (`StartWhenAvailable`), para que un día perdido no deje un hueco de más de 24 h.
- **Cuenta:** el usuario actual, solo con la sesión iniciada. No se guarda ninguna contraseña en la tarea. La clave de PostgreSQL sigue en `pgpass.conf`.
- **Comando:** `bash.exe` de Git for Windows ejecutando `backup_foodstore.sh` con ruta absoluta, porque el Programador no hereda el PATH de Git Bash. La tarea define `ORIGEN=programada`.
- **Una sola instancia a la vez** (`MultipleInstances = IgnoreNew`): si un respaldo sigue corriendo, no se lanza otro encima.
- **Por qué `.ps1`:** `schtasks` por sí solo no permite `StartWhenAvailable`. Con los cmdlets de PowerShell (`New-ScheduledTaskSettingsSet`, `Register-ScheduledTask`) sí.

### Retención

- Se conservan **7 días** (`RETENCION_DIAS`, por defecto 7).
- Un **juego** es `.dump` + `.conteo` + `.sha256` + `_globals.sql` con el mismo sello de fecha. Se borra el juego completo, nunca archivos sueltos.
- La limpieza corre **solo después de un PASS**. Si el respaldo de hoy falló, no se borra nada.
- **Nunca deja menos de 3 juegos** (`RETENCION_MIN_JUEGOS`, por defecto 3), aunque sean viejos. Una racha de fallas no puede dejar la carpeta vacía.
- Cada limpieza deja una línea `RETENCION` en `logs/backup_foodstore.log` con los juegos eliminados y los que quedan.
- `BACKUP_DIR` se puede pisar con una variable de entorno para probar en otra carpeta sin tocar los respaldos reales.

### Roles y permisos

- Paso nuevo del script: `pg_dumpall --globals-only --no-role-passwords` guarda `foodstore_AAAAMMDD_HHMMSS_globals.sql`.
- **Contiene:** `CREATE ROLE`, pertenencias entre roles, `ALTER ROLE … SET` y tablespaces. **No contiene datos de tablas.**
- `--no-role-passwords` evita guardar los hashes de contraseña. Después de restaurar los roles, las contraseñas se asignan a mano.
- Si este paso falla, el respaldo completo se registra como FAIL (un respaldo sin roles no alcanza para recuperar el sistema).
- No se versiona: la carpeta `backups/` está ignorada por Git.
- **Limitación:** el `_globals.sql` recupera los roles y sus atributos, no los permisos sobre las tablas. Esos permisos están dentro del `.dump`; `restore_test.sh` restaura con `--no-privileges`, así que no los recupera. Para recuperarlos hay que restaurar los roles primero y el dump sin esa opción.
- **Restauración:** el `_globals.sql` es SQL plano: se aplica con `psql` conectado a la base `postgres`, nunca con `pg_restore`.

### Fallas

- Cualquier falla registra FAIL en el log, borra los archivos incompletos y termina con código distinto de 0. En el Programador queda como «Último resultado» distinto de 0.
- Cómo se detecta: `tail -n 3 mantenimiento/logs/backup_foodstore.log` y el estado de la tarea. No hay aviso por correo (limitación declarada).

### Corrección pendiente del TP6

- La guarda de `maintenance.sql` usa `\quit`, que sale con código 0 aunque la base no sea la esperada. Debe terminar con código distinto de 0 para que una automatización detecte el error.

### Criterios de aceptación (medibles)

1. `schtasks /query /tn FoodStore_Backup_Diario /v /fo list` muestra la tarea diaria, a las 21:00 y en estado Listo.
2. Al menos 2 líneas `PASS` con `origen=programada` en `logs/backup_foodstore.log`, y al menos una disparada por el horario real, no por `schtasks /run`.
3. Cada PASS deja `.dump`, `.conteo`, `.sha256` y `_globals.sql`.
4. Retención, probada con `BACKUP_DIR` de prueba: se borran los juegos de más de 7 días, nunca quedan menos de 3, y si el respaldo falla no se borra nada.
5. `_globals.sql` no contiene hashes de contraseña: `grep -c "SCRAM-SHA-256"` da 0.
6. `maintenance.sql` contra una base equivocada termina con código distinto de 0.
7. Lo anterior sigue funcionando: `restore_test.sh` da PASS con huella 11/11 sobre el respaldo nuevo.

### Riesgo declarado

- Los respaldos viven en el mismo disco que la base. Si el disco falla se pierden los dos. Mejora fuera de alcance: copiar el juego a un disco externo o a la nube.
