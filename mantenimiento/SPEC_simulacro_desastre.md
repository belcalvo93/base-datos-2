# SPEC — Simulacro de desastre contra reloj (TPI Parcial II, objetivo 8)

**Responsable:** Elías Tello · **Motor:** PostgreSQL 17.11 (cumple 16+) sobre Windows 11 · **Terminal:** Git Bash
**Base del simulacro:** `foodstore_desastre` (descartable) · **Base de recuperación:** `foodstore_restore_test` (descartable)
**Respaldo usado:** el último generado por la tarea programada `FoodStore_Backup_Diario` (`backup_foodstore.sh`, `origen=programada`).

## Objetivo

Comprobar que, ante la pérdida de una tabla completa por un error humano, el procedimiento de respaldo y restauración del plan de mantenimiento (`SPEC_U6.md`) recupera Food Store dentro de las metas de RTO y RPO, y medir cuántos datos se pierden en la práctica.

## Escenario

A las HH:MM de la corrida, un operador ejecuta en «producción» un `DELETE FROM detalle_pedido;` sin `WHERE` (el error del que advierte `AGENTS.md`). Se pierden todas las líneas de todos los pedidos. Los pedidos quedan, pero sin detalle: la aplicación muestra pedidos vacíos y el total facturado da 0.

Entre el último respaldo y el desastre la base siguió recibiendo pedidos. Esos pedidos **no están en el respaldo**: son la pérdida de datos que mide el RPO.

## Bases y reglas de seguridad

- **`foodstore` nunca se toca**: ni se borra, ni se restaura, ni se modifica. El script aborta si alguna de sus bases destino se llama `foodstore`.
- «Producción» en el simulacro es `foodstore_desastre`, creada desde el último respaldo de la tarea. El desastre se provoca solo ahí.
- La recuperación se hace en `foodstore_restore_test` con `restore_test.sh`, el mismo procedimiento probado en el objetivo 7.
- Antes de cada sentencia que modifica datos, el script confirma contra el motor que `current_database()` es `foodstore_desastre` (guarda `DO $$ … RAISE EXCEPTION`).
- **Autorización escrita** antes de borrar una base descartable que ya existe, igual que `restore_test.sh`: se tipea su nombre o se pasa en `CONFIRMAR_DESASTRE`, y queda en el log.
- **Primero en ensayo**: con `MODO=ensayo`, la actividad y el desastre corren dentro de `BEGIN … ROLLBACK`, y no se restaura nada. Recién después se corre con `MODO=real`.
- Sin contraseñas: la clave sale de `%APPDATA%\postgresql\pgpass.conf` y todas las conexiones usan `-w`.
- `foodstore_desastre` queda dañada al terminar, para poder comparar qué se perdió. Se borra a mano con el comando que indica el README.

## Secuencia y cronómetro

| Fase | Qué hace | Hora que se registra |
|---|---|---|
| 0. Preparación | Toma el último `.dump` de `backups/`, verifica su SHA256 y lo restaura en `foodstore_desastre` | — |
| 1. Actividad posterior al respaldo | Registra 3 pedidos con `CALL registrar_pedido(...)` (clientes y productos activos con stock, elegidos por el script) | `T_actividad` |
| 2. Desastre | `DELETE FROM detalle_pedido;` en `foodstore_desastre` | `T_desastre` |
| 3. Detección | Un control de salud encuentra pedidos sin ninguna línea de detalle | `T_deteccion` → **arranca el reloj** |
| 4. Recuperación | Corre `restore_test.sh` sobre el mismo respaldo, en `foodstore_restore_test` | — |
| 5. Validación | Huella 11/11 igual al `.conteo` del respaldo y 8 indicadores de integridad en 0 (los hace `restore_test.sh`) | `T_validado` → **para el reloj** |
| 6. Pérdida de datos | Compara `foodstore_desastre` con la base recuperada: pedidos y líneas que existían antes del desastre y no están en el respaldo | — |

## Medición

- **RTO observado** = `T_validado − T_deteccion`. Incluye la decisión de restaurar, `createdb`, `pg_restore` y las validaciones.
- **RPO observado** = `T_desastre − hora del respaldo` (sale del sello `AAAAMMDD_HHMMSS` del nombre del `.dump`). Además se informan **en filas** los pedidos y líneas perdidos (los de la fase 1).
- `restore_test.sh` informa su propio RTO (desde `createdb`) y la antigüedad del respaldo; se registran los dos para no confundirlos.

## Metas (las del plan de mantenimiento)

- **RTO ≤ 15 min.**
- **RPO ≤ 24 h** (un respaldo diario).

## Criterios de aceptación (medibles)

1. Antes del desastre, `foodstore_desastre` tiene la misma huella que el `.conteo` del respaldo más los 3 pedidos de la fase 1.
2. Después del desastre, `count(*)` de `detalle_pedido` en `foodstore_desastre` es 0 y la detección lo registra.
3. `restore_test.sh` termina en **PASS**: huella 11/11 igual al respaldo y los 8 indicadores en 0.
4. El RTO observado es ≤ 15 min y el RPO observado es ≤ 24 h.
5. La pérdida informada coincide con la actividad de la fase 1: 3 pedidos y sus líneas, ni uno más ni uno menos.
6. `foodstore` tiene la misma huella antes y después del simulacro (se comprueba con `conteo_referencia.sql`, solo lectura).
7. Todo queda en `evidencias/simulacro_desastre_AAAAMMDD_HHMMSS.txt`, con la línea de tiempo y las horas de cada fase, y una línea `PASS`/`FAIL` en `logs/simulacro_desastre.log`.

Si no se cumple alguno, el simulacro es **FAIL** y se documenta el motivo en el informe post-incidente.

## Entregables

| Archivo | Contenido |
|---|---|
| `mantenimiento/SPEC_simulacro_desastre.md` | Esta especificación |
| `mantenimiento/simulacro_desastre.sh` | Guion del simulacro |
| `mantenimiento/evidencias/simulacro_desastre_*.txt` | Salida de cada corrida (ensayo y real) |
| `mantenimiento/informe_post_incidente.md` | Informe sin culpables: línea de tiempo, impacto, detección, RTO/RPO vs metas, datos perdidos y por qué, causa raíz, qué funcionó y qué no, acciones correctivas con responsable |

## Fuera de alcance

- Recuperación a un punto en el tiempo (PITR con archivado de WAL): es la mejora que bajaría el RPO casi a 0, y se propone en el informe.
- Restaurar sobre la base dañada: en un incidente real se restaura aparte y después se decide el reemplazo. Se deja `foodstore_desastre` para el análisis.
- Roles y permisos: `restore_test.sh` restaura con `--no-owner --no-privileges` (limitación ya declarada en `SPEC_U6.md`).

## Respaldo usado y desvío declarado

El respaldo se generó con la tarea programada, disparada con `schtasks /run` el 08/11/2026 a las 23:48; la tarea queda programada para las 21:00 diarias. La distinción entre corrida manual y por horario corresponde al objetivo 7.

## Uso de IA

La spec y el guion los escribió Claude Code por pedido del autor, como **apartamiento** del flujo Kiro → OpenCode, declarado en la DUIA. El autor revisa cada línea y prueba primero en `MODO=ensayo`.
