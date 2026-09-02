# Declaración de Uso de IA (DUIA) — Parte 4

**Ejercicio:** TP3 (Unidad 2) — Carga masiva de datos: adaptación del
Genera_registros.sql de la cátedra al esquema del proyecto. Genera volumen
(50.000/20.000/200.000 en producción, prueba mediana 10.000/4.000/10.000)
para demostrar diferencias de rendimiento entre estrategias de indexación.

**Fecha:** 01/09/2026

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

## Qué se modificó o descartó, y por qué

Se descartó la propuesta de Kiro (mod cuadrático) por no cubrir el dominio de
clientes, y la variante B de OpenCode por no alcanzar la mejora estructural
prometida (1,4x a igual volumen). Se corrigieron antes de su uso final: el
CROSS JOIN masivo (10.000 millones de filas intermedias), el `LIMIT 1` en las
líneas por pedido (reemplazado por `LIMIT 4` + `row_number()`, decisión D6),
la confusión entre líneas y cantidad, y el cast faltante del array de formas
de pago. Las correcciones quedaron en `db/carga_masiva.sql`; la variante B
descartada se conserva como evidencia en `db/carga_masiva_bloque3_B.sql`.

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

---

## Limitaciones detectadas al revisar lo generado

- La referencia a código fuente de PostgreSQL del Uso 7 (subselect.c) no se
  pudo verificar contra la instalación local; se tomó como válida solo por
  coincidir con el comportamiento medido.
- El conteo `count(DISTINCT id_categoria)` (Usos 6 y 10) es un ejemplo de
  verificación que no verifica: con solo 5 categorías en total, el indicador
  es insensible al bug. Quedó registrado para no repetir el patrón.