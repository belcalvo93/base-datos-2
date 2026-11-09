# Informe post-incidente — Simulacro de desastre (TPI Parcial II, objetivo 8)

**Responsable:** Elías Tello · **Fecha:** 08/11/2026 · **Formato:** sin culpables (se analizan el proceso y los controles, no a las personas)
**Especificación:** `mantenimiento/SPEC_simulacro_desastre.md` · **Guion:** `mantenimiento/simulacro_desastre.sh`
**Evidencias:** `evidencias/simulacro_desastre_20261108_235631.txt` (ensayo), `evidencias/simulacro_desastre_20261108_235715.txt` (real), `evidencias/restore_test_20261108_235721.txt` (restauración) · **Log:** `logs/simulacro_desastre.log`
**Motor:** PostgreSQL 17.11 sobre Windows 11 · **Resultado:** **PASS** (6 de 6 criterios de aceptación)

## 1. Resumen

En la copia descartable `foodstore_desastre`, que hizo de producción, se ejecutó `DELETE FROM detalle_pedido;` sin `WHERE` y se perdieron las 499.269 líneas de pedido. El incidente se detectó en 1 s, se restauró el último respaldo de la tarea programada en `foodstore_restore_test` y las validaciones pasaron **6,16 s después de la detección**. Se perdieron **3 pedidos y 6 líneas**, registrados después del respaldo. La base `foodstore` no se tocó: su huella fue igual antes y después.

## 2. Respaldo utilizado

`foodstore_20261108_234846.dump` (9.428.157 bytes), generado el **08/11/2026 a las 23:48:46** por la tarea `FoodStore_Backup_Diario` (`PASS`, `origen=programada`, SHA256 verificado antes de usarlo). Respaldo disparado con `schtasks /run`; la tarea queda programada para las 21:00 diarias.

## 3. Línea de tiempo

| Hora | Hecho |
|---|---|
| 23:48:46 | Respaldo de la tarea programada |
| 23:56:31 | Ensayo (`MODO=ensayo`): actividad y desastre dentro de `BEGIN … ROLLBACK`. ENSAYO OK, sin cambios |
| 23:57:15 | Inicio de la corrida real. `foodstore_desastre` se crea desde el respaldo (huella 11/11) |
| 23:57:20 | Se registran 3 pedidos con `registrar_pedido` (6 líneas): son posteriores al respaldo |
| 23:57:20 | **Desastre:** `DELETE FROM detalle_pedido;` |
| 23:57:21 | **Detección:** 0 líneas de detalle y 200.008 pedidos sin líneas. **Arranca el reloj** |
| 23:57:21 | Se restaura el respaldo en `foodstore_restore_test` con `restore_test.sh` |
| 23:57:27 | **Validado:** huella 11/11 y 8 indicadores de integridad en 0. **Para el reloj** |
| 23:58:33 | El autovacuum limpia las tuplas muertas de `detalle_pedido` en la base dañada |

## 4. Impacto

Todos los pedidos (200.008) quedaron sin líneas: el detalle de compra, los subtotales y el total facturado ($629.621.805,75) no se podían consultar. Las demás tablas no se afectaron. El `ON DELETE CASCADE` va de `pedido` hacia `detalle_pedido`, así que borrar los detalles no borró pedidos.

## 5. RTO y RPO: metas y valores observados

| Medida | Meta (`SPEC_U6.md`) | Observado | ¿Cumple? |
|---|---|---|---|
| **RTO**: detección → validaciones OK | ≤ 15 min | **6,16 s** | Sí |
| RTO de `restore_test.sh`: `createdb` → validaciones OK | — | 3,63 s (restauración 3,06 s) | — |
| **RPO**: respaldo → desastre | ≤ 24 h | **514 s (~8 min)** | Sí |

- **RTO y RPO no miden lo mismo.** El RTO es cuánto tarda en volver a funcionar; el RPO es cuántos datos se pierden. El RTO del simulacro incluye la decisión de restaurar y el borrado de la base de prueba anterior; el de `restore_test.sh` arranca recién en `createdb`.
- **El RPO observado dio bajo porque el respaldo tenía 8 minutos.** Con un respaldo diario a las 21:00, un desastre a las 20:59 perdería casi 24 horas de pedidos: ese es el RPO real del plan.

## 6. Validaciones

- **Huella** (`conteo_referencia.sql`): las 11 claves iguales al `.conteo` del respaldo: filas de las 6 tablas, total facturado, tablas, vistas, restricciones e índices.
- **Integridad:** los 8 indicadores en 0 (precios, stock y cantidades válidos; ningún detalle, pedido ni producto huérfano).
- **Producción intacta:** la huella de `foodstore` fue igual antes y después del simulacro.

## 7. Datos perdidos y por qué

Se perdieron los **3 pedidos (6 líneas)** registrados entre el respaldo y el desastre, que es exactamente la actividad posterior al respaldo (criterio 5). No están en ningún respaldo: un respaldo lógico con `pg_dump` es una foto de un momento, y todo lo que se escribe después solo existe en la base dañada. Los 200.005 pedidos anteriores se recuperaron completos. Restaurar no revirtió el `DELETE` sobre la base dañada: los datos volvieron en otra base, desde la foto del respaldo.

## 8. Causa raíz

Una sentencia destructiva sin `WHERE` se ejecutó directo sobre producción, fuera de una transacción y con una cuenta con privilegios totales (`postgres`). Ningún rol de aplicación podría haberlo hecho: `rol_app_escritura` solo tiene `SELECT` sobre `detalle_pedido` (`sql/roles.sql`, línea 90). El riesgo está en el trabajo manual con cuentas administrativas, que no tiene ningún freno.

## 9. Qué funcionó y qué no

**Funcionó:**
- La tarea programada y el SHA256: el simulacro rechaza un respaldo que no sea de la tarea o que esté alterado.
- `restore_test.sh` se reusó sin cambios y validó la recuperación con la huella y los indicadores.
- El modo ensayo detectó que la actividad y el desastre hacían lo esperado (3 pedidos, 499.269 líneas) antes de correrlo en serio.
- Las guardas `current_database()` y la autorización escrita antes de cada borrado.

**No funcionó o se encontró en el camino** (problemas reales):
- **En la PC de este integrante no había respaldo de la tarea:** la tarea estaba registrada solo en la PC de Belén. Se registró con `programar_respaldo.ps1` y se disparó con `schtasks /run`.
- **Un error del guion, encontrado al releerlo antes de ejecutarlo:** un `SELECT` mal armado en el ensayo, que habría hecho fallar la prueba.
- **Una afirmación falsa de la IA:** al escribir el guion, Claude Code reemplazó `psql -1` por `BEGIN … COMMIT` explícitos, diciendo que `-1` no aplica a SQL leído de la entrada estándar. Se probó en el motor y es falso: con entrada estándar, `-1` también abre una sola transacción. Se conservó `BEGIN … COMMIT` porque deja la transacción visible en el guion, y se corrigió el comentario. La misma prueba mostró que, sin `ON_ERROR_STOP`, `psql` termina con código 0 aunque haya errores; el guion lo usa en todas las consultas.
- **La detección no existe en el monitoreo real:** el simulacro detecta el problema porque lo busca. `health_check.sql` no controla pedidos sin líneas, y las tuplas muertas que dejó el `DELETE` desaparecieron con el autovacuum a los 73 s. Pasado ese minuto, la única señal en `health_check.sql` es `n_live_tup = 0`, que nadie revisa con una alarma.
- Detalle a tener en cuenta: los pedidos nuevos tomaron los id 245008 a 245010 aunque el último del respaldo era 245005. La identidad no reutiliza valores (huecos de la carga masiva y del `ROLLBACK` del ensayo). El guion cuenta por "id mayor que el último del respaldo", así que no afecta la medición.

## 10. Acciones correctivas

| # | Acción | Reduce | Responsable |
|---|---|---|---|
| 1 | Agregar a `health_check.sql` un control de negocio: pedidos sin líneas y tablas principales con `n_live_tup = 0`, que marque ALERTA | Tiempo de detección (RTO real) | Elías |
| 2 | Para trabajo manual en producción, usar un rol sin `DELETE` masivo y siempre `BEGIN` → revisar filas afectadas → `COMMIT` | Probabilidad del incidente | Equipo (regla en `AGENTS.md`) |
| 3 | **Mejora propuesta:** archivado continuo de WAL (`archive_mode`) más el respaldo diario, para recuperar a un punto en el tiempo (PITR) justo antes del `DELETE` | RPO: de hasta 24 h a minutos | Fuera del alcance del TP; queda documentada |
| 4 | Repetir el simulacro con un respaldo disparado por el horario de las 21:00, como corrida extra con un RPO más realista | Validez de la medición | Elías |

## 11. Uso de IA

La spec, el guion y este informe los redactó **Claude Code** a pedido del autor, como apartamiento del flujo Kiro → OpenCode, declarado en la DUIA. Cómo se verificó antes de aceptarlo: el autor revisó la spec antes de que se escribiera el código; el guion se releyó línea por línea y la afirmación sobre `psql -1` se probó en el motor (sección 9: un error corregido y una afirmación falsa descartada); primero se corrió en `MODO=ensayo` dentro de `BEGIN … ROLLBACK`, y los valores de este informe salen de las evidencias `.txt`, no de lo que dijo la IA. La afirmación sobre el autovacuum se comprobó consultando `pg_stat_user_tables` en `foodstore_desastre` después del simulacro.
