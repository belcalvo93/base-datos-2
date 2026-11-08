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
- **Mejora propuesta**: usar `pg_dumpall --globals-only` para roles y aplicarlos por separado.

## Objetivos de recuperación (laboratorio)

- **RPO previsto:** 24 h (un respaldo diario; como máximo se pierde un día de cambios).
- **RTO previsto:** 15 min (crear la base, restaurar y validar).
- Se mide el RTO observado con cronómetro: empieza antes de `createdb foodstore_restore_test` y termina cuando pasan las validaciones. El RPO observado es la antigüedad del respaldo usado al momento del simulacro.

## Uso de OpenCode

OpenCode puede generar la primera versión de los scripts a partir de este SPEC y de `AGENTS.md`. Cada comando se lee, se entiende y se prueba a mano antes de aceptarlo. Las correcciones se anotan en el informe.
