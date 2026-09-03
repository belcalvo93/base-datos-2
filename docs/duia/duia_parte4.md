# Declaración de Uso de IA (DUIA) — Parte 4

**Ejercicio:** TP3 (Unidad 2) — Carga masiva de datos, laboratorio de
índices, lectura crítica de planes y consultas bajo especificación.
La Parte 1 adapta el Genera_registros.sql de la cátedra al esquema del
proyecto y genera volumen (50.000/20.000/200.000 en producción, prueba
mediana 10.000/4.000/10.000) para demostrar diferencias de rendimiento
entre estrategias de indexación. Las Partes 2, 3 y 4 continúan con el
análisis de esos índices, la lectura crítica de un plan y las consultas
resumen/subconsulta.

**Fecha:** 01 - 02/09/2026

---

## Herramienta

Se usaron tres herramientas, cada una en un rol distinto:

- **OpenCode** — generación y revisión de `db/carga_masiva.sql` (bloques 3 y
  4), análisis de planes (InitPlan/SubPlan) y la variante B del bloque 3.
- **Claude (chat)** — lectura e interpretación del plan `EXPLAIN` del bloque
  1 (producto).
- **Kiro** — una sola propuesta de distribución de pedidos entre clientes,
  descartada (Uso 1).

---

## Spec o prompt utilizado

No hubo una spec única: el trabajo fue dialogado por bloque, con el objetivo
de adaptar el `Genera_registros.sql` de la cátedra al esquema del proyecto.
Para cada pieza se pidió la justificación del plan antes de autorizar la
escritura, y cada resultado se contrastó en el motor (protocolo de seguridad:
transacción con ROLLBACK antes de COMMIT).

---

## Usos de la IA

La consigna pide cuatro columnas; se agrega una columna `#` para referencia:

| # | Herramienta | Para qué se usó | Prompt / spec resumido | ¿Se aceptó o descartó? ¿Por qué? |
|---|---|---|---|---|
| 1 | Kiro | Repartir pedidos entre clientes | Propuso `id_cliente (usuario_id en el mensaje original) = 1 + mod((n-1)*(n-1), 20000)`, afirmando que daba una distribución despareja | **Descartado**: `mod(n², 20000)` no genera todos los restos; ~3/4 de los clientes quedaban sin pedidos |
| 2 | OpenCode | Generar los detalles de pedido | Propuso un CROSS JOIN pedido × producto con ROW_NUMBER encima: 200.000 × 50.000 = 10.000 millones de filas intermedias, justificando que el filtro «actúa antes de materializar» | **Descartado**: es falso; una función de ventana necesita ordenar toda la partición antes de numerar, independientemente de los filtros posteriores |
| 3 | OpenCode | Líneas por pedido | Escribió `LIMIT 1` en el lateral pero calculó `n_lineas` sin usarlo; afirmó que las llamadas independientes garantizaban productos distintos | **Corregido** con `LIMIT 4` + `row_number()`: con `LIMIT 1` se generaba 1 línea por pedido en vez de 1–4. Además, el razonamiento sobre llamadas independientes está al revés: por ser independientes, cada llamada puede devolver el mismo producto — no garantizan nada. Lo que garantiza productos distintos dentro de un pedido es que los cuatro salgan de un mismo ordenamiento (un solo `ORDER BY random()` con `LIMIT 4`). Es lo que fundamenta la decisión D6 de la spec |
| 4 | OpenCode | Cantidad por línea | Usó `n_lineas` como valor de `cantidad` | **Corregido**: confunde cuántos productos distintos tiene un pedido con cuántas unidades se piden de cada uno |
| 5 | OpenCode | Array de formas de pago | Omitió el casteo `::forma_pago_enum[]` sobre el array | **Corregido**: error en ejecución — «la columna forma_pago es de tipo forma_pago_enum pero la expresión es de tipo text» |
| 6 | Claude (chat) | Lectura del plan del bloque 1 | Interpretó «InitPlan 1 … loops=1» como prueba de que el subquery se congelaba y todos los productos quedaban en una categoría; después se retractó al ver `count(DISTINCT id_categoria) = 5` | **Aceptado** el diagnóstico inicial, tras verificación empírica correcta. La retractación fue el error: ese conteo no distinguía nada (hay 5 categorías en total y los 11 productos preexistentes ya las cubrían). Se resolvió con una consulta que aísla las filas recién insertadas (`ORDER BY id_producto DESC LIMIT 10000`), que devolvió 1 |
| 7 | OpenCode | Causa del InitPlan | Explicó por qué un subquery no correlacionado se convierte en InitPlan, la distinción InitPlan (loops=1) vs SubPlan (por fila) y por qué `random()` no lo evita (la decisión se toma por correlación, no por volatilidad) | **Aceptado**: coincide con la evidencia empírica. Reservas: citó código fuente de PostgreSQL (make_subplan(), subselect.c) que no se pudo verificar; dijo «4 categorías activas» cuando son 5; y clasificó el nodo Materialize como «un subplan», cuando es un nodo de caché del lado interno de un Nested Loop |
| 8 | OpenCode | Detectar el bug de su propia variante B | Al pedirle justificar la variante B antes de aplicarla, encontró que su primera redacción (`JOIN ON c.rn = 1 + floor(random() * c.total)`) caía en el problema del bloque 4: la condición referencia solo la relación interna, no es hasheable, queda Nested Loop con Materialize y un solo sorteo para todos los pedidos | **Aceptado**: se corrigió moviendo el `random()` a un lateral correlacionado |
| 9 | OpenCode | Variante B del bloque 3 | Prometió pasar de O(pedidos × sort de clientes) a O(clientes) de build + O(1) por pedido | **Descartado**: medición a 10.000 pedidos — B = 6.778 ms vs A = 9.676 ms → solo 1,4x, no la mejora estructural. El plan mostró por qué: el Hash Join quedó dentro del Nested Loop y el CTE se escanea una vez por pedido (CTE Scan on dominio_clientes: rows=4005 loops=10000). La ganancia no justifica apartarse del estilo de la cátedra; se conserva en db/carga_masiva_bloque3_B.sql |
| 10 | OpenCode | Corregir la verificación del bloque 1 | Cuando se le pidió un plan de corrección, señaló que `count(DISTINCT id_categoria)` no sirve como verificación: da 5 esté roto o arreglado, porque hay solo 5 categorías en total. Diseñó la consulta correcta: contar productos por categoría restringido a las filas recién insertadas (`ORDER BY id_producto DESC LIMIT 10000`), más un control de suma. También notó que el bloque 1 no filtra por `activo`, así que sortea sobre las 5 categorías, incluida la dada de baja | **Aceptado**: es la verificación que se usó |
| 11 | OpenCode | Proponer índices a partir de los planes reales (Parte 2) | Se le pasaron los tres planes de EXPLAIN ANALYZE medidos sin índices y propuso tres índices compuestos, con la justificación de que la segunda columna cubriría el ORDER BY o el join y eliminaría el nodo Sort | **Aceptado como hipótesis y descartado tras medir**: los tres se crearon y midieron a igual volumen contra los del TP1. Empataron en tiempo de consulta (8,413 vs 8,450 / 0,159 vs 0,198 / 0,311 vs 0,285 ms) y cuestan 1,8x construirlos. La predicción sobre el Sort no se cumplió en ninguno de los tres |
| 12 | OpenCode | Error de premisa sobre índices existentes (Parte 2) | Al analizar los planes afirmó que `idx_producto_categoria_activo` e `idx_pedido_id_cliente` "existen en el esquema" y explicó que el plan no los usaba porque el planificador no los elegía por selectividad. Los había leído de schema.sql | **Detectado**: en realidad se habían borrado con `DROP INDEX` antes de medir; el plan no los usaba porque no estaban. Es una causa construida para un fenómeno que tenía otra explicación |
| 13 | OpenCode | Imprecisiones menores en el mismo análisis (Parte 2) | Dijo "4 categorías activas" cuando son 5; afirmó que el índice parcial excluye "las ~39.964 filas activas" confundiendo las filas descartadas por el filtro de categoría con las inactivas (que son 3 en toda la tabla); y reconstruyó mal las consultas a partir de los planes, agregando columnas que no estaban | **Detectado** |
| 14 | OpenCode | Explicación del plan de C2 (Parte 3) | Se le pidió que explicara nodo por nodo el plan de C2 con índice aplicado, sin más contexto que el texto del plan. Se conserva sin editar en `docs/explicacion_ia_plan_c2.md` y es el insumo del análisis de la Parte 3. Se auditaron nueve afirmaciones: cinco incorrectas y cuatro correctas. Las incorrectas: atribuye el Recheck Cond a cambios concurrentes cuando responde a bitmaps lossy; inventa un tiempo de Sort de 0,002 ms restando mal los actual time; afirma "random I/O dirigido" sobre un plan que no reporta I/O; invierte el orden de los hijos del Nested Loop; y descarta sin fundamento una subestimación de filas de 2,4x | **Analizado** — el detalle completo está en `docs/informe_parte3_lectura_critica.md` |
| 15 | OpenCode | Coincidencia no trivial en esa misma explicación (Parte 3) | Propuso, como optimización hipotética, el índice compuesto `(id_cliente, fecha DESC)` y él mismo concluyó que con 24 filas el Sort es tan barato que no vale la pena | **Aceptado**: es la misma conclusión a la que se llegó midiendo en la Parte 2, y la alcanzó sin tener acceso a esas mediciones |
| 16 | OpenCode | Generación de SQL a partir de specs (Parte 4) | Se le pasaron las dos specs en sesiones limpias, sin mostrarle ninguna solución previa. Generó la consulta de facturación por categoría (LEFT JOIN con GROUP BY) y la de productos nunca vendidos (NOT EXISTS) | **Aceptadas**: ambas cumplen la spec y su equivalencia con las versiones alternativas se verificó con EXCEPT en ambas direcciones, con 0 filas en las cuatro pruebas. Observación menor sobre la segunda: la subconsulta compara `id_producto` sin alias, lo que funciona pero es frágil |
| 17 | OpenCode | Detección de una inconsistencia en los datos que se le dieron (Parte 2) | Al armar el informe de índices notó que los Execution Time del enunciado no coincidían con los de los archivos de planes referenciados, y preguntó cuál usar en lugar de elegir por su cuenta. Eran dos corridas distintas (una en frío y otra con caché) y el enunciado las mezclaba sin aclararlo | **Aceptado**: la observación era correcta y llevó a documentar explícitamente las dos corridas |
| 18 | OpenCode | Racionalización de un error ajeno (Parte 2) | Ante la misma inconsistencia, su primera explicación fue que los ~40 segundos de diferencia entre el total declarado de la carga (1:00:48) y la suma de los bloques (1:00:08) eran "sobrecarga entre sentencias" | **Detectado y corregido** en el documento: no lo eran; el total declarado era una suma mal hecha y no existía ninguna medición del transcurrido total de la transacción |
| 19 | OpenCode | Autocorrección al releer (Parte 4) | Después de escribir el informe de consultas, releyó el archivo y detectó que había transcrito 99.686 líneas de venta donde los datos decían 98.686 | **Aceptado**: lo corrigió sin que se lo pidieran |

---

## Qué se aceptó

Se aceptaron, tras verificación empírica en el motor:
- El diagnóstico del bloque 1 (subquery no correlacionado → InitPlan → una
  sola categoría), una vez aisladas las filas recién insertadas (Usos 6 y 10).
- La explicación mecánica del InitPlan y por qué `random()` no lo evita
  (Uso 7), con las reservas anotadas en la tabla.
- El mecanismo de correlación por suma de cero (`+ i * 0`) para forzar la
  evaluación por fila, aplicado como fix a los bloques 1 y 3 y ya vigente en
  el bloque 4.
- La consulta de verificación de distribución por categoría diseñada con
  OpenCode (Uso 10), con su control de cobertura.
- La coincidencia de la Parte 3 (Uso 15): OpenCode llegó a la misma
  conclusión que la medición de la Parte 2 sobre el índice compuesto
  (`id_cliente, fecha DESC`) sin tener acceso a esa medición.
- Las dos consultas generadas a partir de las specs de la Parte 4 (Uso 16):
  facturación por categoría y productos nunca vendidos. Su equivalencia con
  las versiones alternativas se verificó con EXCEPT en ambas direcciones.
- La detección de la inconsistencia entre corridas (Uso 17): al señalar que
  los Execution Time del enunciado no coincidían con los planes, obligó a
  documentar explícitamente las dos corridas (en frío y con caché).
- La autocorrección del Uso 19, que detectó y corrigió un error propio de
  transcripción al releer el informe.

## Qué se modificó o descartó, y por qué

Se descartó la propuesta de Kiro (mod cuadrático) por no cubrir el dominio de
clientes, y la variante B de OpenCode por no alcanzar la mejora estructural
prometida (1,4x a igual volumen). Se corrigieron antes de su uso final: el
CROSS JOIN masivo (10.000 millones de filas intermedias), el `LIMIT 1` en las
líneas por pedido (reemplazado por `LIMIT 4` + `row_number()`, decisión D6),
la confusión entre líneas y cantidad, y el cast faltante del array de formas
de pago. Las correcciones quedaron en `db/carga_masiva.sql`; la variante B
descartada se conserva como evidencia en `db/carga_masiva_bloque3_B.sql`.

En la Parte 2 se descartaron tras medir los tres índices compuestos
propuestos (Uso 11): empataron en tiempo de consulta contra los del TP1 y
cuestan 1,8x construirlos; la predicción sobre el nodo Sort no se cumplió en
ninguno de los tres. Se corrigió en el documento la explicación del tiempo de
carga (Uso 18): la diferencia de ~40 segundos no era "sobrecarga entre
sentencias" sino una suma mal hecha del total declarado, y no existía
medición del transcurrido total de la transacción.

---

## Verificación realizada

Cada afirmación de la IA se contrastó con el motor (PostgreSQL 17), dentro de
transacción con ROLLBACK:
- **Bloque 1 (Usos 6, 7 y 10):** `EXPLAIN ANALYZE` mostró el subquery de
  `id_categoria` como InitPlan con loops=1; la consulta que aísla las filas
  recién insertadas (`ORDER BY id_producto DESC LIMIT 10000`) devolvió 1 sola
  categoría. Tras el fix de correlación, el plan pasó a evaluar el subquery
  por fila y la distribución quedó repartida entre las 5 categorías.
- **Bloque 3 (Uso 9):** medición A vs B a igual volumen (10.000 pedidos /
  4.000 clientes): B = 6.778 ms, A = 9.676 ms. El plan de B explicó la brecha:
  `CTE Scan on dominio_clientes (rows=4005, loops=10000)` dentro del Nested
  Loop → el barrido por fila no se eliminó, solo se abarató.
- **Parte 2 (Usos 11, 17 y 18):** los tres índices compuestos se crearon y
  midieron contra los del TP1 a igual volumen; el descarte se apoya en esa
  medición. La inconsistencia de tiempos motivó el registro de las dos
  corridas, y la diferencia de ~40 segundos se re-verificó contra los
  valores reales (no existía medición del transcurrido total).
- **Parte 3 (Usos 14 y 15):** las nueve afirmaciones sobre el plan de C2 se
  contrastaron contra el texto real del plan; la coincidencia del índice
  compuesto se verificó contra la medición de la Parte 2.
- **Parte 4 (Uso 16):** cada consulta se verificó con `EXCEPT` en ambas
  direcciones contra su versión alternativa; las cuatro pruebas devolvieron
  0 filas.

---

## Limitaciones detectadas al revisar lo generado

- La referencia a código fuente de PostgreSQL del Uso 7 (subselect.c) no se
  pudo verificar contra la instalación local; se tomó como válida solo por
  coincidir con el comportamiento medido.
- El conteo `count(DISTINCT id_categoria)` (Usos 6 y 10) es un ejemplo de
  verificación que no verifica: con solo 5 categorías en total, el indicador
  es insensible al bug. Quedó registrado para no repetir el patrón.
- Patrón recurrente en los Usos 12 y 18: ante una discrepancia, la primera
  reacción de la IA fue construir una causa plausible en lugar de señalar que
  faltaba información. En los dos casos la causa propuesta era falsa y la real
  era más simple (los índices no estaban porque se habían borrado; el total
  declarado era una suma mal hecha). Vale como advertencia: una explicación
  coherente no garantiza que sea la correcta.
- Limitación menor de la Parte 4 (Uso 16): la subconsulta de la consulta de
  productos nunca vendidos compara `id_producto` sin alias. Funciona porque
  cada lado se resuelve contra su tabla, pero es frágil: si la tabla interna
  perdiera esa columna, PostgreSQL la buscaría en la consulta externa y
  compararía la columna consigo misma, dando siempre verdadero y devolviendo
  cero filas sin error.