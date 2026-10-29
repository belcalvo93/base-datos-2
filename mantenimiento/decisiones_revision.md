# Decisiones sobre la revisión de OpenCode (TP Unidad 6)

OpenCode revisó los scripts contra `SPEC_U6.md` (ver `revision_opencode.md`). Cada hallazgo se
contrastó con la evidencia real antes de decidir. Decisión y verificación: Belén Calvo, 28/10/2026.

| Hallazgo | Decisión | Motivo | Verificación |
|---|---|---|---|
| 3.2.1 `ANALYZE` no incluía `usuario` | **Aceptado** | La evidencia lo confirmaba: `usuario` seguía con `reltuples = -1` y sin `last_analyze` | `maintenance_v2_corrida1.txt`: decide ANALYZE por 1 de 6 tablas |
| 3.2.2 `ANALYZE` incondicional (contra SPEC y consigna) | **Aceptado** | La consigna exige justificar la acción con la observación previa | Corrida 1: `ANALYZE justificado`; corrida 2: `sin accion, estadisticas al dia` |
| 4.2.1 El simulacro comparaba contra la `foodstore` viva | **Aceptado** | Una escritura posterior al respaldo daba un falso FALLA | `backup_foodstore.sh` genera `.conteo` junto al `.dump`; `restore_test_v2_salida.txt`: OK contra `respaldo=` |
| 2.2.1 `health_check` muestra `n_live_tup = 0` | **Rechazado** | Ese 0 es la señal que detectó los contadores vacíos tras `createdb -T` y justificó el mantenimiento | `health_check_salida.txt` vs `maintenance_salida.txt` |
| Resto de hallazgos [Bajo] | **Pospuestos** | Rotación de respaldos, `ON_ERROR_STOP`, `current_database()` del destino, `--exit-on-error`: mejoras para la próxima iteración | — |

## Correcciones humanas a la propuesta de OpenCode

1. **Plan:** el `\echo` de la decisión ponía las variables `:dec_pendientes` y `:dec_total` dentro de comillas simples; psql no interpola ahí y habría impreso el texto literal. Se corrigió antes de aplicar.
2. **Diff reportado:** el diff que mostró OpenCode tenía `rto_ms=$RTO` en `restore_test.sh`, mientras que afirmaba que la línea seguía como `rto_s`. Se verificó en el archivo real con `grep -n "rto_"`: quedó `rto_s`. El diff mostrado no era la salida literal de `git diff`.
3. Antes de ejecutar: `bash -n` en los dos `.sh` (sintaxis OK) y `git diff --stat` (solo los 4 archivos acordados).
