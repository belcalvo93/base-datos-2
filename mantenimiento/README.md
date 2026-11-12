# TP Unidad 6 — Mantenimiento, respaldo y recuperación de Food Store

Plan de mantenimiento en [`SPEC_U6.md`](SPEC_U6.md). Informe: [`informe_u6.pdf`](informe_u6.pdf).
Este README cubre el objetivo 7 del TPI Parcial II (respaldo programado) y el objetivo 8 (simulacro de desastre contra reloj, sección [Simulacro de desastre](#simulacro-de-desastre-objetivo-8)), cuyo informe es [`informe_post_incidente.md`](informe_post_incidente.md).
Motor: PostgreSQL 17.11 (cumple 16+) sobre Windows 11 con Git Bash.

## Archivos

| Archivo | Qué hace |
|---|---|
| `SPEC_U6.md` | Especificación del plan: tareas, requisitos, reglas de seguridad, RPO/RTO previstos |
| `backup_foodstore.sh` | Respaldo `pg_dump -Fc` de `foodstore`. Genera `.dump`, `.conteo` (huella), `.sha256` y `_globals.sql` (roles del cluster con `pg_dumpall --globals-only --no-role-passwords`); verifica con `pg_restore -l`; aplica retención de 7 días (mínimo 3 juegos, solo tras un PASS); registra PASS/FAIL con tamaño, SHA256, `origen=` y `globals=` en `logs/backup_foodstore.log`. Variables pisables: `BACKUP_DIR`, `RETENCION_DIAS` (7), `RETENCION_MIN_JUEGOS` (3), `ORIGEN` (`manual` por defecto) |
| `programar_respaldo.ps1` | Crea la tarea `FoodStore_Backup_Diario`: diaria a las 21:00, `StartWhenAvailable`, usuario actual sin contraseña guardada, `ORIGEN=programada` |
| `quitar_respaldo.ps1` | Borra la tarea `FoodStore_Backup_Diario` |
| `conteo_referencia.sql` | Huella de la base: filas de las 6 tablas, total facturado (`sum(cantidad * precio_unitario)`) y estructura (tablas, vistas, restricciones, índices). La usan el respaldo y el simulacro |
| `restore_test.sh` | Simulacro: verifica el SHA256, pide autorización escrita, restaura en `foodstore_restore_test`, compara la huella y corre 8 indicadores de integridad. Mide RTO y RPO observados |
| `SPEC_simulacro_desastre.md` | Especificación del simulacro de desastre (objetivo 8): escenario, reglas de seguridad, metas RTO ≤ 15 min y RPO ≤ 24 h, criterios de aceptación |
| `simulacro_desastre.sh` | Simulacro de desastre: crea `foodstore_desastre` desde el último respaldo de la tarea, registra 3 pedidos, ejecuta `DELETE FROM detalle_pedido;`, lo detecta, restaura con `restore_test.sh` y mide RTO, RPO y datos perdidos. `MODO=ensayo` (por defecto) lo hace en `BEGIN … ROLLBACK` sin restaurar |
| `informe_post_incidente.md` | Informe sin culpables del simulacro: línea de tiempo, impacto, RTO/RPO vs metas, datos perdidos, causa raíz y acciones correctivas |
| `health_check.sql` | Chequeo de salud: tamaño, conexiones, estado de tablas y consultas activas |
| `maintenance.sql` | Diagnóstico de estadísticas y tuplas muertas contra los umbrales de autovacuum; `ANALYZE`/`VACUUM` solo si se justifica, nunca `VACUUM FULL`; sale con código 3 si la base no es `foodstore` ni `foodstore_restore_test` |
| `revision_opencode.md`, `revision_opencode_v2.md` | Revisiones de OpenCode contra el SPEC |
| `decisiones_revision.md` | Qué se aceptó, rechazó o pospuso de cada revisión y cómo se verificó |
| `logs/` | Logs de respaldo y simulacro (versionados: son evidencia) |
| `evidencias/` | Salidas de cada ejecución (ver abajo) |
| `backups/` | Respaldos locales. **No se versionan** (`.dump`, `.conteo`, `.sha256`, `_globals.sql`) |

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

# 2b. Respaldo programado (tarea de Windows; ver "Limitaciones declaradas")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File mantenimiento/programar_respaldo.ps1
MSYS_NO_PATHCONV=1 schtasks /query /tn FoodStore_Backup_Diario /v /fo list
MSYS_NO_PATHCONV=1 schtasks /run /tn FoodStore_Backup_Diario
# esperar unos segundos a que termine el respaldo antes del paso 3
# Para borrar la tarea (opcional, no correr junto con los anteriores):
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File mantenimiento/quitar_respaldo.ps1
# MSYS_NO_PATHCONV=1 evita que Git Bash convierta "/query" y "/run" en rutas de Windows.

# 3. Simulacro de restauración: pide escribir foodstore_restore_test para autorizar el borrado
./mantenimiento/restore_test.sh

# 4. Salud y mantenimiento (sobre la base restaurada y sobre la principal)
psql -U postgres -d foodstore -X -f mantenimiento/health_check.sql
psql -U postgres -d foodstore_restore_test -X -f mantenimiento/maintenance.sql
psql -U postgres -d foodstore -X -f mantenimiento/maintenance.sql

# 5. Guarda de base de maintenance.sql (sobre una base no permitida; debe dar 3)
psql -h localhost -U postgres -w -d postgres -X -f mantenimiento/maintenance.sql; echo "salida: $?"
```

Prueba de retención (carpeta temporal; no toca `backups/`). Fechas relativas, así se reproduce cualquier día. Resultado esperado: se eliminan 3 juegos y quedan 3. Los resultados de la corrida real están en `evidencias/retencion_pruebas.txt`.

```bash
T="$(mktemp -d)"
for n in 12 10 9 8 4; do
  s=$(date -d "-$n days" +%Y%m%d_%H%M%S)
  echo x > "$T/foodstore_$s.dump"; echo x > "$T/foodstore_$s.conteo"
  ( cd "$T" && sha256sum "foodstore_$s.dump" > "foodstore_$s.sha256" )
  echo "-- globals" > "$T/foodstore_${s}_globals.sql"
done
BACKUP_DIR="$T" ORIGEN=prueba ./mantenimiento/backup_foodstore.sh   # la línea RETENCION del log: antes=6 despues=3
ls "$T"
RETENCION_DIAS=abc BACKUP_DIR="$T" ./mantenimiento/backup_foodstore.sh; echo "salida: $?"   # configuración inválida: 2
```

## Simulacro de desastre (objetivo 8)

Requiere un respaldo de la tarea programada (paso 2b) y que `foodstore` exista. Solo borra y recrea `foodstore_desastre` y `foodstore_restore_test`; `foodstore` solo se lee para comprobar que no cambió. Pide escribir el nombre de cada base antes de borrarla.

```bash
# 1. Ensayo: actividad y desastre dentro de BEGIN … ROLLBACK, sin restaurar. Debe dar ENSAYO OK
MODO=ensayo ./mantenimiento/simulacro_desastre.sh

# 2. Simulacro real. Debe dar PASS con los 6 criterios de la spec en OK
MODO=real ./mantenimiento/simulacro_desastre.sh

# 3. Al terminar, borrar la base dañada (queda a propósito para el análisis)
dropdb -U postgres foodstore_desastre
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
| `evidencias/tarea_programada.txt` | Registro de la tarea: diaria, 21:00, estado Listo |
| `evidencias/tarea_programada_prueba_humo.txt` | Disparo con `schtasks /run`: PASS con `origen=programada`, `LastTaskResult` 0 |
| `evidencias/retencion_pruebas.txt` | La retención borra juegos de más de 7 días y no baja de 3; configuración inválida sale con 2; base inexistente da FAIL y no borra nada |
| `evidencias/retencion_minimo_3.txt` | Con 4 juegos de más de 7 días, la retención borra solo 2 y deja 3: el mínimo se respeta |
| `evidencias/globals_pruebas.txt` | Respaldo de roles (9 roles, 0 hashes de contraseña) y las 4 guardas de falla del `_globals.sql` |
| `evidencias/maintenance_v5_guarda.txt` | La guarda sale con código 3 en una base no permitida y el script corre normal en `foodstore_restore_test` |
| `evidencias/restore_test_20261108_034017.txt` | Simulacro sobre el respaldo nuevo: huella 11/11, 8 indicadores en 0, RTO 4,22 s, RPO 135 s, PASS |
| `evidencias/simulacro_desastre_20261108_235631.txt` | Simulacro de desastre en **ensayo**: 3 pedidos y `DELETE` de 499.269 líneas dentro de `BEGIN … ROLLBACK`; la base vuelve a la huella del respaldo |
| `evidencias/simulacro_desastre_20261108_235715.txt` | **Simulacro de desastre real:** RTO 6,16 s, RPO 514 s, 3 pedidos y 6 líneas perdidos, `foodstore` sin cambios, PASS (6/6 criterios) |
| `evidencias/restore_test_20261108_235721.txt` | Restauración disparada por el simulacro de desastre: huella 11/11, 8 indicadores en 0, PASS |
| `logs/simulacro_desastre.log` | Autorizaciones y resultados (ENSAYO_OK / PASS / FAIL) del simulacro de desastre |

## Reglas

- `foodstore` nunca se borra ni se restaura: los destructivos solo apuntan a `foodstore_restore_test` y, en el simulacro de desastre, a `foodstore_desastre`.
- Los roles se respaldan aparte en el `_globals.sql` (SQL plano, se aplica con `psql` conectado a la base `postgres`, nunca con `pg_restore`; sin contraseñas, que se asignan a mano). Los permisos sobre las tablas NO se recuperan en el simulacro porque `restore_test.sh` restaura con `--no-owner --no-privileges`.
- No se suben `.dump` ni contraseñas. No se usa `VACUUM FULL`.

## Limitaciones declaradas

- La tarea solo corre con la sesión de Windows iniciada: no guarda ninguna contraseña.
- Si la PC está apagada a las 21:00, corre al encender (`StartWhenAvailable`), pero varios días apagada se juntan en una sola corrida.
- Los respaldos viven en el mismo disco que la base: si el disco falla, se pierden los dos.
- No hay aviso por correo: se detecta con `tail` del log o con el "Último resultado" del Programador.
- El `_globals.sql` es del cluster completo, no solo de Food Store.
- La retención ignora los juegos incompletos y nunca los borra: por eso `20261028_200259` y `20261028_211058` aparecen siempre como `ignorados` en el log. Se limpian a mano. La retención de 7 días rige para los juegos completos.
- `programar_respaldo.ps1` agrega al PATH de la tarea `C:\Program Files\PostgreSQL\17\bin` (línea 53). Con otra versión de PostgreSQL hay que editar esa ruta antes de registrar la tarea.
