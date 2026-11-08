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

---

# Segunda revisión (corrección del TP6, 07/11/2026)

Decisión y verificación: Belén Calvo. Herramientas: Kiro (SPEC), OpenCode (revisión e implementación), Claude (primera versión de los scripts nuevos).

## SPEC actualizado con Kiro

Kiro reescribió `SPEC_U6.md` con los requisitos nuevos (SHA256, PASS/FAIL, huella, 8 indicadores, autorización escrita, alcance sin roles).
**Corrección humana:** Kiro indicó que el `.sha256` tiene el formato `nombre.dump sha256`; `sha256sum` escribe primero el hash y después el nombre. Se corrigió a mano (commit `2f8ea9c`).
**Verificación:** el "diff" que mostró Kiro lo armó él mismo; se confirmó con `git diff --stat` que solo había tocado el SPEC.

## Revisión v2 de OpenCode (`revision_opencode_v2.md`)

| Hallazgo | Decisión | Motivo | Verificación |
|---|---|---|---|
| 4.2.1 La huella no contaba `usuario` | **Aceptado** | Una restauración que perdiera sus 3 filas pasaba la validación | Huella de 11 claves; `usuario restaurada=3 respaldo=3 OK` |
| 3.2.1 `ANALYZE` de las 6 tablas con 2 pendientes | **Aceptado** | La acción debe limitarse a lo que el diagnóstico justifica | `maintenance_v4_restore_test.txt`: analiza solo `categoria` y `usuario` |
| 3.2.3 `maintenance.sql` sin `ON_ERROR_STOP` | **Aceptado** | Un fallo terminaba con código 0 y evidencia aparentemente válida | `\set ON_ERROR_STOP on` en el script |
| 2.2.1 `current_database()` no quedaba en la evidencia | **Aceptado** | Es un requisito del SPEC y tiene que poder verse | `Destino confirmado por el motor: current_database() = foodstore_restore_test` |
| 2.2.6 La autorización no registraba su origen | **Aceptado** | Distingue la autorización tipeada de la automatizada | Log: `AUTORIZADO / usuario=beluu / origen=interactivo` |
| 2.2.2 El RPO incluía la espera de autorización | **Aceptado** | La antigüedad se mide al momento del simulacro | RPO 19 s, medido antes de `createdb` |
| 2.2.7 Orden no determinista de los indicadores | **Aceptado** | La evidencia debe coincidir con el código | Los 8 salen en el orden del SQL |
| 3.2.2 Regla "SIN ESTADISTICAS" fuera del umbral | **Rechazado** | Sin estadísticas el planificador estima a ciegas; autoanalyze nunca las genera en tablas de menos de ~50 filas. Se documenta en el informe | `categoria` (5 filas) y `usuario` (3 filas) sin `last_analyze` ni `last_autoanalyze` tras la restauración |
| Resto [Bajo] | **Pospuestos** | Encoding del detalle de error, rotación de respaldos, triggers en la huella, `\quit` con código 0 | Mejoras para la próxima iteración |

**Verificación humana antes de ejecutar:** se pidió la salida literal de `git --no-pager diff` y se revisó línea por línea; solo cambiaron los 3 archivos permitidos. Después se corrieron respaldo, simulacro y mantenimiento en Windows 11 + PostgreSQL 17.11: todo PASS.
