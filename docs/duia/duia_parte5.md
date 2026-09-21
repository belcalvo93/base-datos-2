# Declaración de Uso de IA (DUIA) — Parte 5

**Ejercicio:** TP5 (Unidad 3, Semana 5), Parte A — plan de indexado asistido
por IA. Se rehízo la parte sobre el dump `bd2_tp3_actualizada_20260919.dump`
para que el informe, los índices y las specs del repositorio coincidan con los
datos de esa base (50.011 productos / 20.005 clientes / 200.005 pedidos /
499.263 detalles).

**Fecha:** 21/09/2026

---

## Herramienta

- **Kiro** — redacción de las tres specs de índices (commit `e5e7907`),
  anteriores a esta rehecha.
- **Claude Code (Claude Sonnet 5)** — restaurar el dump, ejecutar las
  mediciones, proponer una variante de índice, escribir
  `food-store/medicion_planes.sql`, `food-store/medicion_escritura.sql`,
  `food-store/indices.sql` y `food-store/informe_mediciones.md`.
- **OpenCode** — no se usó en esta sesión. La consigna lo nombra como agente
  generador; ver "Pendiente del autor" al final.

---

## Spec o prompt utilizado

Las specs de Kiro están en `food-store/specs/spec_indice_*.md` (cada una fija
consulta, frecuencia, columnas relevantes, hipótesis y criterio de
aceptación). A Claude Code se le entregaron el dump, el PDF de la consigna, el
repositorio con esas specs y este pedido:

> "necesito rehacer la parte A de este trabajo, basado en el dump o copia de
> base de dato ficticia. para que coincida los informes con el repo vinculado"

Todo lo que se ejecutó se corrió dentro de `BEGIN; … ROLLBACK;` sobre una
instancia PostgreSQL temporal (puerto 5433), separada de `bd2_proyecto` y
`bd2_trabajo`.

---

## Usos de la IA

| # | Herramienta | Para qué se usó | Prompt / spec resumido | ¿Se aceptó o descartó? ¿Por qué? |
|---|---|---|---|---|
| 1 | Kiro | Especificar los índices de C1, C2 y C3 | Cada spec fija consulta, frecuencia, columnas de filtro/join/orden, hipótesis para el generador y criterio de aceptación con la salida "se descarta si no mejora" | **Aceptadas como hipótesis** y contrastadas con el motor. Resultado en cada spec (sección "Resultado de la medición"): C1 rechazada tal cual pero rescatada con `INCLUDE`; C2 y C3 descartadas |
| 2 | Claude Code | Identificar qué consultas de `queries.sql` hacen `Seq Scan` hoy | Ejecutar las siete consultas sobre la base restaurada y clasificar el plan | **Aceptado, cambia el planteo**: C1, C2 y C3 ya no hacen `Seq Scan` (los índices del TP1 se lo sacaron); los `Seq Scan` que subsisten están en P4-A, P4-B y S4-A. Se dejó documentado en el informe (sección 3) en lugar de forzar el enunciado |
| 3 | Claude Code | Evaluar la hipótesis de la spec de C1: `(id_categoria, precio DESC) WHERE activo` | Crear el índice en transacción, medir 5 corridas + `pgbench` | **Descartado**: el planificador no lo usa (sigue con el índice del TP1 + `Sort`) y el tiempo es idéntico (10,5 ms). Aun sin bitmap scan prefiere `Seq Scan + Sort`. Es un índice muerto que cuesta +27 % de WAL en cada `INSERT` de `producto` |
| 4 | Claude Code | Proponer una variante de C1 al ver que el índice de la spec no se usaba | Agregar `INCLUDE` con las columnas que la consulta devuelve para habilitar `Index Only Scan` | **Aceptado tras medir**: `Index Only Scan` sin `Sort`, `Heap Fetches: 0`, 10,5 → 3,1 ms, 527 → 86 buffers; resultado idéntico fila a fila (`EXCEPT` en ambas direcciones = 0). Quedó en `indices.sql`. Costo asumido: +45 % de WAL por `INSERT` y +32 % por `UPDATE` de `stock` en `producto` |
| 5 | Claude Code | Evaluar `(id_cliente, fecha DESC)` para C2 | Igual método | **Descartado**: 24 filas, `Sort` insignificante, el planificador mantiene el índice del TP1; 0,152 → 0,151 ms. Prefijo redundante, +26 % de WAL por `INSERT` en `pedido` |
| 6 | Claude Code | **Caso de sobreindexación descartado (consigna 6):** `(id_producto, id_pedido)` para C3 | Evaluar si el índice compuesto aporta algo al join frente a `idx_detalle_pedido_id_producto` y a `UNIQUE (id_pedido, id_producto)` | **Descartado**: superconjunto del índice existente; el planificador lo usa pero el plan, el costo estimado y los 27 bloques de heap son los mismos; tiempos indistinguibles (`pgbench` 0,68–0,86 vs 0,73–0,78 ms). Cuesta +17 % de WAL en cada `INSERT` de `detalle_pedido`, la tabla más escrita. Detalle en el informe, sección 7 |
| 7 | Claude Code | Probar un índice cubriente en `detalle_pedido` para las consultas analíticas con `Seq Scan` | `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` (24 MB) | **Descartado**: el planificador lo ignora y el tiempo no cambia (727 → 727 ms). Las consultas leen toda la tabla. Prueba exploratoria **sin spec previa de Kiro**, documentada como tal |
| 8 | Claude Code | Diseñar la medición del costo de escritura | Script con 500 `INSERT` por tabla y 500 `UPDATE` de `stock`, cada estado en transacción con `ROLLBACK`, 15 rondas | **Aceptado con correcciones** (filas 10 y 11) |
| 9 | Claude Code | Primer intento de la variante `INCLUDE` de C1 | `INCLUDE (nombre, stock)` | **Error propio, detectado en la medición:** faltaba `id_producto`, que la consulta también devuelve, así que el plan era `Index Scan` con visita al heap (y solo si se desactivaba el bitmap) en vez de `Index Only Scan`. Se corrigió a `INCLUDE (id_producto, nombre, stock)` |
| 10 | Claude Code | Sesgo de posición en su propia medición de escritura | La primera versión medía el estado base al inicio y al final | **Error de método, detectado por el propio control:** `base_a` y `base_b` (mismo estado) diferían ~60 %. Causas: la primera transacción compila los planes de los triggers y las transacciones revertidas dejan tuplas muertas. Se corrigió con calentamiento por carga y `VACUUM` tras cada `ROLLBACK`, y se agregó una métrica determinista (bytes de WAL). Con el método corregido `base_a` y `base_b` difieren <10 % en tiempo y <1 % en WAL |
| 11 | Claude Code | Cifras de tiempo de escritura en los comentarios de `indices.sql` | Resumir el costo del índice aceptado | **Corregido al recalcular:** la primera redacción decía +31 % (`INSERT` de `producto`) y +43 % (`UPDATE` de `stock`); recalculadas desde las medianas son +32 % y +50 %. También se corrigió "0,79 vs 0,74 ms" de C3 por el rango real, que se superpone |
| 12 | Claude Code | Explicar por qué el planificador ignora el parcial de C1 | Afirmó que el costo estimado del `Index Scan` supera al del bitmap | **Verificado con el índice exacto antes de dejarlo escrito**: la primera evidencia era de una variante parecida. Con el parcial real y bitmap desactivado, el plan es `Seq Scan + Sort` (cost 1825), o sea que el índice ni siquiera compite |

---

## Verificación de lo que reportó la IA

Según `protocolo_seguridad.md` ("lo que el agente dice que hizo no es
evidencia"), se comprobó en el motor:

- Conteos de filas tras restaurar el dump, y `VACUUM ANALYZE` (`pg_restore` no
  trae estadísticas).
- `indices.sql` se ejecutó dos veces seguidas en una transacción (idempotente)
  y tras el `ROLLBACK` el índice no persiste.
- Equivalencia de resultados de C1 con y sin el índice: `EXCEPT` en ambas
  direcciones, 0 filas de diferencia (10.047 filas), orden por `precio`
  descendente verificado.
- Las cifras del informe se recalcularon desde los archivos de salida en una
  restauración limpia del dump, no desde la memoria de la sesión.

---

## Pendiente del autor

- **Herramienta generadora.** La consigna pide que el índice lo proponga
  OpenCode a partir de la spec de Kiro. En esta rehecha esa propuesta la hizo
  Claude Code. Si se corre además una sesión con OpenCode sobre las mismas
  specs, agregar su fila a la tabla; no se debe declarar un uso que no ocurrió.
- **Reproducir en la base propia.** Las mediciones se hicieron en una instancia
  temporal con configuración por defecto. Antes de la defensa, repetir
  `medicion_planes.sql` y `medicion_escritura.sql` sobre `bd2_trabajo` (pasos
  en la sección 9 del informe): los milisegundos van a variar, los planes y las
  proporciones no deberían.
- **Defensa oral.** Poder explicar sin apoyo de IA por qué `INCLUDE` habilita el
  `Index Only Scan`, por qué el parcial sin `INCLUDE` no se usa, y por qué
  (id_producto, id_pedido) es un índice redundante.
