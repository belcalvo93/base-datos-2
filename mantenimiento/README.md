# TP Unidad 6 — Mantenimiento, respaldo y recuperación de Food Store

Plan de mantenimiento en [`SPEC_U6.md`](SPEC_U6.md). Informe: [`informe_u6.pdf`](informe_u6.pdf).
Motor: PostgreSQL 17.11 (cumple 16+) sobre Windows 11 con Git Bash.

## Archivos

| Archivo | Qué hace |
|---|---|
| `SPEC_U6.md` | Especificación del plan: tareas, requisitos, reglas de seguridad, RPO/RTO previstos |
| `backup_foodstore.sh` | Respaldo `pg_dump -Fc` de `foodstore`. Genera `.dump`, `.conteo` (huella) y `.sha256`; verifica con `pg_restore -l`; registra PASS/FAIL con tamaño y SHA256 en `logs/backup_foodstore.log` |
| `conteo_referencia.sql` | Huella de la base: filas de las 6 tablas, total facturado (`sum(cantidad * precio_unitario)`) y estructura (tablas, vistas, restricciones, índices). La usan el respaldo y el simulacro |
| `restore_test.sh` | Simulacro: verifica el SHA256, pide autorización escrita, restaura en `foodstore_restore_test`, compara la huella y corre 8 indicadores de integridad. Mide RTO y RPO observados |
| `health_check.sql` | Chequeo de salud: tamaño, conexiones, estado de tablas y consultas activas |
| `maintenance.sql` | Diagnóstico de estadísticas y tuplas muertas contra los umbrales de autovacuum; `ANALYZE`/`VACUUM` solo si se justifica, nunca `VACUUM FULL` |
| `revision_opencode.md`, `revision_opencode_v2.md` | Revisiones de OpenCode contra el SPEC |
| `decisiones_revision.md` | Qué se aceptó, rechazó o pospuso de cada revisión y cómo se verificó |
| `logs/` | Logs de respaldo y simulacro (versionados: son evidencia) |
| `evidencias/` | Salidas de cada ejecución (ver abajo) |
| `backups/` | Respaldos locales. **No se versionan** (`.dump`, `.conteo`, `.sha256`) |

## Cómo reproducirlo (desde la raíz del repo, en Git Bash)

```bash
# 0. Contraseña fuera del repo (una sola vez; no se ve al tipear)
mkdir -p "$APPDATA/postgresql"
read -s -p "Contraseña de postgres: " PW; echo
echo "localhost:5432:*:postgres:$PW" > "$APPDATA/postgresql/pgpass.conf"; unset PW

# 1. Base principal foodstore (copia de bd2_tp3; cerrar pgAdmin/DBeaver antes)
createdb -U postgres -T bd2_tp3 foodstore

# 2. Respaldo (y prueba del caso de error: debe dar FAIL y código 1)
./mantenimiento/backup_foodstore.sh
DB_NAME=base_inexistente ./mantenimiento/backup_foodstore.sh; echo "Código de salida: $?"

# 3. Simulacro de restauración: pide escribir foodstore_restore_test para autorizar el borrado
./mantenimiento/restore_test.sh

# 4. Salud y mantenimiento (sobre la base restaurada y sobre la principal)
psql -U postgres -d foodstore -X -f mantenimiento/health_check.sql
psql -U postgres -d foodstore_restore_test -X -f mantenimiento/maintenance.sql
psql -U postgres -d foodstore -X -f mantenimiento/maintenance.sql
```

## Evidencias

| Archivo | Qué muestra |
|---|---|
| `evidencias/restore_test_20261107_231154.txt` | **Simulacro final:** huella de 11 claves idéntica, 8 indicadores en 0, RTO 4,21 s, RPO 19 s, PASS |
| `evidencias/restore_test_20261107_223233.txt` | Simulacro **no autorizado**: frena antes de tocar la base (FAIL esperado) |
| `evidencias/maintenance_v4_restore_test.txt` | Base restaurada: `ANALYZE` solo de `categoria` y `usuario` (sin estadísticas); `VACUUM` no necesario |
| `evidencias/maintenance_v4_foodstore.txt` | Base principal: estadísticas al día, sin acción |
| `logs/backup_foodstore.log` | Respaldos PASS con tamaño, SHA256 y objetos del TOC; FAIL controlado con `base_inexistente` |
| `logs/restore_test.log` | Autorizaciones (`usuario`, `origen=interactivo`) y resultados PASS/FAIL |
| `evidencias/restore_test_intento1_crlf.txt` | Problema real del 28/10: salida rota por los fines de línea de Windows |
| `evidencias/hernan/`, `elias/`, `bruno/` | Simulacros de cada integrante (28 al 30/10, versión anterior de los scripts) |
| `evidencias/*_salida.txt`, `maintenance_v2_*`, `maintenance_v3_*` | Corridas anteriores, se conservan como historial |

## Reglas

- `foodstore` nunca se borra ni se restaura: los destructivos solo apuntan a `foodstore_restore_test`.
- La restauración no recupera roles ni permisos (`--no-owner --no-privileges`).
- No se suben `.dump` ni contraseñas. No se usa `VACUUM FULL`.
