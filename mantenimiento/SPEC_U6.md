# SPEC_U6 — Plan de mantenimiento de Food Store

**Motor:** PostgreSQL 17.11 (cumple 16+) sobre Windows 11 · **Terminal:** Git Bash
**Base principal:** `foodstore` (copia de `bd2_tp3`) · **Base de restauración:** `foodstore_restore_test`

## Tareas automatizadas

| Tarea | Archivo | Frecuencia | Condición de éxito (evidencia) |
|-------|---------|-----------|--------------------------------|
| Respaldo de `foodstore` | `backup_foodstore.sh` | Diaria | `pg_dump` termina con código 0, existe `backups/foodstore_AAAAMMDD_HHMMSS.dump` con tamaño > 0 y el log registra `OK` |
| Chequeo de salud | `health_check.sql` | Diaria | La salida muestra los 4 controles: tamaño, conexiones, estado de tablas y consultas activas |
| Revisión de mantenimiento | `maintenance.sql` | Semanal | Se registran tuplas muertas, último autovacuum/autoanalyze y la acción tomada con su justificación |
| Restauración de prueba | `restore_test.sh` (opcional) | Semanal | `foodstore_restore_test` tiene las mismas filas por tabla que `foodstore` y 0 productos y 0 detalles inválidos |

## Requisitos del respaldo

1. Formato custom (`-Fc`), para poder restaurar con `pg_restore`.
2. El nombre del archivo lleva fecha y hora: `foodstore_AAAAMMDD_HHMMSS.dump`.
3. Cada ejecución agrega una línea en `logs/backup_foodstore.log` con fecha, archivo, tamaño y resultado (`OK` / `ERROR`).
4. Si `pg_dump` falla, el script registra `ERROR`, borra el archivo incompleto y termina con código distinto de 0.

## Reglas de seguridad

- **Sin contraseñas** en scripts ni en el repo: la clave va en `%APPDATA%\postgresql\pgpass.conf` o en la variable `PGPASSWORD` de la sesión. `.env` y `*.dump` no se versionan.
- **`foodstore` nunca se elimina ni se reemplaza.** Los comandos destructivos (`dropdb`, `pg_restore`) solo apuntan a `foodstore_restore_test`. Antes de ejecutar, se confirma con `SELECT current_database();`.
- **No se usa `VACUUM FULL`** como mantenimiento periódico porque bloquea la tabla. Un `VACUUM`/`ANALYZE` manual solo se ejecuta si `maintenance.sql` muestra tuplas muertas o estadísticas desactualizadas.
- Antes del respaldo se guarda el conteo de filas por tabla. Ese conteo es la referencia para validar la restauración.

## Objetivos de recuperación (laboratorio)

- **RPO previsto:** 24 h (un respaldo diario; como máximo se pierde un día de cambios).
- **RTO previsto:** 15 min (crear la base, restaurar y validar).
- Se mide el RTO observado con cronómetro: empieza antes de `createdb foodstore_restore_test` y termina cuando pasan las validaciones. El RPO observado es la antigüedad del respaldo usado al momento del simulacro.

## Uso de OpenCode

OpenCode puede generar la primera versión de los scripts a partir de este SPEC y de `AGENTS.md`. Cada comando se lee, se entiende y se prueba a mano antes de aceptarlo. Las correcciones se anotan en el informe.
