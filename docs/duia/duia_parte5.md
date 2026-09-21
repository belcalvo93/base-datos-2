# Declaración de Uso de IA (DUIA) — Parte 5

**Ejercicio:** TP5 (Unidad 3, Semana 5), Partes A y B.

## Parte A — plan de indexado asistido por IA

Se rehízo la Parte A sobre el dump `bd2_tp3_actualizada_20260919.dump` para que
el informe, los índices y las specs del repositorio coincidan con los datos de
esa base (50.011 productos / 20.005 clientes / 200.005 pedidos / 499.263
detalles).

**Esta versión reemplaza a la anterior de la Parte A** (commit `e711e99`),
medida sobre `practica_bd2` (50.010 productos / 500.151 detalles) con otros
parámetros (categoría 10, cliente 10, producto 64074) y que descartaba los tres
índices. Esos parámetros no sirven en el dump (la categoría 10 y el cliente 10 no
devuelven filas), por lo que se volvió a los de `queries.sql` original
(categoría 5, cliente 20155, producto 49112), que son también los del informe
del TP3. La diferencia de conclusión (acá se acepta la variante con `INCLUDE`
de C1) no contradice la anterior: aquella no probó esa variante.

**Fecha:** 21/09/2026

---

## Herramienta

- **Kiro** — redacción de las tres specs de índices de C1, C2 y C3 (commit
  `e5e7907`), anteriores a esta rehecha, y revisión de las tres specs nuevas de
  P4-A, P4-B y S4-A (21/09/2026).
- **Claude Code (Claude Sonnet 5)** — restaurar el dump, ejecutar las
  mediciones, proponer una variante de índice, escribir
  `food-store/medicion_planes.sql`, `food-store/medicion_escritura.sql`,
  `food-store/indices.sql` y `food-store/informe_mediciones.md`.
- **OpenCode** — propuesta de índice para las tres consultas con `Seq Scan`
  (P4-A, P4-B y S4-A), en cuatro sesiones del 21/09/2026, modo Plan. Modelos
  usados: `ling-3.0-flash-fin-free` (sesiones 1 y 2, P4-A) y
  `gemini-3.5-flash-lite` (sesiones 3 y 4, P4-B y S4-A). No se usó para C1, C2
  y C3: en esas tres la propuesta de índice la hizo Claude Code.

**Por qué Claude Code en C1, C2 y C3.** El autor eligió Claude Code por
rendimiento y facilidad de uso. Es una decisión propia y se declara como un
apartamiento de la herramienta que nombra la consigna para esas tres consultas;
para las tres consultas con `Seq Scan` sí se siguió el flujo Kiro → OpenCode.

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

**Prompt entregado a Kiro** para revisar cada una de las tres specs nuevas
(una sesión por spec, con la spec abierta), tal como se le dio:

```text
Revisá esta spec según .kiro/steering/reglas_trabajo.md. Verificá que tenga la
estructura fija, que el SQL de la consulta sea exactamente el de
food-store/queries.sql y que el criterio de aceptación tenga salida de
descarte. Marcá lo que falte, lo que sobre o lo que sea ambiguo. No ejecutes
SQL y no modifiques la consulta. Proponé los cambios como una lista; no
reescribas la spec entera.
```

**Prompt entregado a OpenCode** (una sesión limpia por spec, con `@` para
adjuntar los archivos), tal como se le dio. Solo cambia la spec adjunta
(`spec_indice_facturacion_categoria.md`, `spec_indice_productos_nunca_vendidos.md`
o `spec_indice_facturacion_categoria_mes.md`):

```text
Contexto: PostgreSQL 17, esquema en @food-store/schema.sql, consultas en @food-store/queries.sql.
Te paso una spec. Proponé el índice adecuado: tipo, columnas, orden,
INCLUDE y condición parcial si corresponde. Para cada propuesta indicá:
qué nodo del plan elimina, cuánto pesa el índice frente a la tabla y si es
redundante con un índice existente. Si creés que ningún índice lo justifica,
decilo y explicá por qué. No ejecutes nada; solo proponé el SQL.
Spec: @food-store/specs/<archivo de la spec>
```

En las sesiones 2, 3 y 4 se agregó, antes de la línea `Spec:`, esta instrucción
(la sesión 1 no la llevaba):

```text
Leé únicamente los archivos que te indico en este mensaje; no abras ningún otro archivo del repositorio.
```

En las sesiones 3 y 4 se ocultaron además `food-store/indices.sql`,
`food-store/informe_mediciones.md` y `food-store/planes_tp5_parteA.txt` mientras
duró la sesión, para que la propuesta no dependiera de las mediciones previas.
Los exports de las cuatro sesiones (JSON) están fuera del repositorio y se
identifican por su id de sesión (ver la tabla).

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
| 7 | Claude Code | Probar un índice cubriente en `detalle_pedido` para las consultas analíticas con `Seq Scan` | `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` (24 MB) | **Descartado**: el planificador lo ignora y el tiempo no cambia (727 → 727 ms). Las consultas leen toda la tabla. Prueba exploratoria **sin spec previa de Kiro**, documentada como tal. Luego se rehízo con el flujo completo (filas 13 a 19). **Error propio detectado después:** ese índice no incluía `id_detalle`, que P4-A necesita, así que para P4-A la prueba no era concluyente; se corrigió en la fila 19 y la conclusión se mantuvo |
| 8 | Claude Code | Diseñar la medición del costo de escritura | Script con 500 `INSERT` por tabla y 500 `UPDATE` de `stock`, cada estado en transacción con `ROLLBACK`, 15 rondas | **Aceptado con correcciones** (filas 10 y 11) |
| 9 | Claude Code | Primer intento de la variante `INCLUDE` de C1 | `INCLUDE (nombre, stock)` | **Error propio, detectado en la medición:** faltaba `id_producto`, que la consulta también devuelve, así que el plan era `Index Scan` con visita al heap (y solo si se desactivaba el bitmap) en vez de `Index Only Scan`. Se corrigió a `INCLUDE (id_producto, nombre, stock)` |
| 10 | Claude Code | Sesgo de posición en su propia medición de escritura | La primera versión medía el estado base al inicio y al final | **Error de método, detectado por el propio control:** `base_a` y `base_b` (mismo estado) diferían ~60 %. Causas: la primera transacción compila los planes de los triggers y las transacciones revertidas dejan tuplas muertas. Se corrigió con calentamiento por carga y `VACUUM` tras cada `ROLLBACK`, y se agregó una métrica determinista (bytes de WAL). Con el método corregido `base_a` y `base_b` difieren <10 % en tiempo y <1 % en WAL |
| 11 | Claude Code | Cifras de tiempo de escritura en los comentarios de `indices.sql` | Resumir el costo del índice aceptado | **Corregido al recalcular:** la primera redacción decía +31 % (`INSERT` de `producto`) y +43 % (`UPDATE` de `stock`); recalculadas desde las medianas son +32 % y +50 %. También se corrigió "0,79 vs 0,74 ms" de C3 por el rango real, que se superpone |
| 12 | Claude Code | Explicar por qué el planificador ignora el parcial de C1 | Afirmó que el costo estimado del `Index Scan` supera al del bitmap | **Verificado con el índice exacto antes de dejarlo escrito**: la primera evidencia era de una variante parecida. Con el parcial real y bitmap desactivado, el plan es `Seq Scan + Sort` (cost 1825), o sea que el índice ni siquiera compite |
| 13 | Claude Code | Redactar el borrador de las tres specs de las consultas con `Seq Scan` (P4-A, P4-B, S4-A) | Mismo formato que las specs de C1–C3: objetivo, consulta, frecuencia, columnas, estado medido, hipótesis para OpenCode y criterio de aceptación con umbral del 30 % | **Aceptado como borrador, sujeto a la revisión de Kiro** (fila siguiente). Las frecuencias quedaron marcadas «a confirmar» porque son supuestos del dominio, y el umbral del 30 % lo eligió la IA, no la cátedra |
| 14 | Kiro | Revisar las tres specs nuevas contra `.kiro/steering/reglas_trabajo.md` | El prompt textual de la sección «Spec o prompt utilizado». Según el análisis entregado por el autor, Kiro propuso 7 cambios: (1) agregar la sección 8 «Resultado de la medición» en las tres; (2) integrar «Antecedente» en «Estado actual medido» o en «Hipótesis», por no ser parte de la estructura fija; (3) y (4) corregir «TP3 Parte 4» a «TP4 Parte 4» en P4-A y P4-B; (5) y (6) ampliar la salida de descarte de P4-B y S4-A al caso general; (7) decidir si el SQL de S4-A debe reproducir el formato exacto de `queries.sql`. Confirmó además que el SQL de P4-A y P4-B era idéntico al de `queries.sql` | **Aceptado, con una modificación.** (1), (2), (5), (6) y (7) se aplicaron tal cual; (7) se resolvió alineando el SQL textualmente. **(3) y (4) se modificaron:** el repo rotula esa parte de forma contradictoria (`queries.sql` dice «TP4 — Parte 4»; la DUIA y el README la ubican en el TP3), así que en lugar de elegir un número se referenció por archivo (`docs/informe_parte4_consultas.md`). La observación (7) era correcta: el SQL de S4-A difería en las líneas `ON`, algo que la verificación previa no había detectado por ignorar espacios. Tras los cambios se verificó por script: SQL idéntico carácter por carácter, 8 de 8 secciones y salida de descarte general en las tres |
| 15 | OpenCode | Proponer el índice de P4-A (facturación por categoría). Sesión 1, `ling-3.0-flash-fin-free`, id `ses_f3ba1344effeu4jD1iAFLXAQe8` | El prompt de OpenCode de la sección «Spec o prompt utilizado», sin la línea de «leer únicamente los archivos indicados», con `spec_indice_facturacion_categoria.md` | **Propuesta: ningún índice.** La consulta lee el 100 % de `detalle_pedido`, el `Seq Scan` es óptimo y la mejora es una vista materializada. Abrió, además de los tres archivos adjuntos, `food-store/indices.sql`, que traía la medición del mismo índice descartado, y la cita como prueba: **la conclusión no es independiente**. Errores verificados: «~20K productos activos» (son 50.010), «5 categorías activas» (son 4) y «+24-27 % de WAL» para ese índice, cifra sin sustento (nunca se midió; 26 y 27 % son de otros índices). **Aceptada como hipótesis**; se contrastó con el motor (fila 19) |
| 16 | OpenCode | Repetir P4-A con la instrucción de leer solo los archivos indicados. Sesión 2, mismo modelo, id `ses_f3b902e9dffeTg1nvcq7G3Owj3` | El prompt de la fila 15 más la línea «Leé únicamente los archivos que te indico en este mensaje; no abras ningún otro archivo del repositorio» | **Propuesta: ningún índice**, otra vez con una vista materializada o una tabla resumen como alternativa. **Ignoró la instrucción:** volvió a abrir `indices.sql` y usó de ahí el «+17 % de WAL», que es de otro índice (`(id_producto, id_pedido)`). Además afirma que «un `Seq Scan` siempre supera a cualquier índice cuando se lee toda la tabla», falso en general (P4-B lo contradice) y menciona una «query C del TP4» que no existe. **Aceptada como hipótesis**, con las mismas reservas de independencia. No se hizo una tercera corrida independiente: las dos dicen lo mismo y quedan documentadas con su límite |
| 17 | OpenCode | Proponer el índice de P4-B (productos nunca vendidos). Sesión 3, `gemini-3.5-flash-lite`, id `ses_f3b843aa5ffeMPM5NZ7f6xzFD4` | El prompt de la fila 16, con `spec_indice_productos_nunca_vendidos.md`. Con `indices.sql`, el informe y los planes ocultos | **Propuesta: ningún índice nuevo.** `idx_detalle_pedido_id_producto` ya existe y el `Seq Scan` responde a una decisión de costos del planificador, no a un índice que falta. Abrió solo los tres archivos permitidos (**sesión independiente**). **Aceptada**, con verificación en el motor: con `random_page_cost = 1.1` el planificador usa solo el índice existente y baja de 258 a 110 ms. Imprecisión: dice que `UNIQUE (id_pedido, id_producto)` cubre `id_producto`; empieza por `id_pedido`, así que no. El razonamiento se apoyó en un dato que ya traía la spec (`enable_seqscan = off`), no en un hallazgo propio |
| 18 | OpenCode | Proponer el índice de S4-A (facturación por categoría y mes). Sesión 4, `gemini-3.5-flash-lite`, id `ses_f3b76771dffezC4MdvUUBUWksx` | El prompt de la fila 16, con `spec_indice_facturacion_categoria_mes.md`. Con `indices.sql`, el informe y los planes ocultos | **Propuesta: ningún índice**; la mejora es una vista materializada, como prevé la Parte C. Abrió solo los tres archivos permitidos (**sesión independiente**). **Aceptada.** Reservas: repite la generalización falsa sobre el `Seq Scan` (aquí acierta porque el índice pesaría casi lo mismo que la tabla) y no respondió a lo pedido sobre peso y redundancia del índice, porque no propuso ninguno |
| 19 | Claude Code | Contrastar con el motor cada respuesta de OpenCode y medir los índices discutidos | Método de la Parte A: `EXPLAIN` antes/después con mediana de 5, tamaño del índice, 500 `INSERT` en `detalle_pedido` con tiempo y WAL, 15 rondas | **Aceptado como verificación; las decisiones son las del autor.** P4-A con el índice cubriente correcto (`INCLUDE (id_detalle, …)`): 743 → 735 ms, 24 MB, +21,4 % de WAL por `INSERT`; P4-B: 258 ms por defecto, 112 con `enable_seqscan = off`, 110 con `random_page_cost = 1.1`; S4-A: 2.219 → 2.246 ms. El autor confirmó el descarte de las tres. Además descubrió el error de la fila 7 al leer el razonamiento de OpenCode (fila 15), que mencionaba que hacía falta `id_detalle` |

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
  OpenCode a partir de la spec de Kiro. Para las tres consultas con `Seq Scan`
  (P4-A, P4-B y S4-A) se hizo así; para C1, C2 y C3 lo propuso Claude Code por
  la razón declarada arriba. Los demás integrantes del equipo pueden editar
  esta sección si la cátedra pide otra cosa. No se debe declarar un uso que no
  ocurrió.
- **Evidencia de OpenCode.** Los exports JSON de las cuatro sesiones están fuera
  del repositorio (identificados por su id de sesión en la tabla). Decidir si se
  suman al repo como evidencia.
- **Reproducir en la base propia.** Las mediciones se hicieron en una instancia
  temporal con configuración por defecto. El 21/09/2026 el autor corrió
  `medicion_planes.sql` sobre su `bd2_trabajo` (restaurada del dump): 75 nodos
  de plan en cada archivo, con los mismos nodos y orden; la única diferencia fue
  `Heap Fetches: 63` en la salida de referencia contra `0` en la propia, y los
  milisegundos variaron como se esperaba. Falta repetir
  `medicion_escritura.sql` sobre `bd2_trabajo` (sección 9 del informe).
- **Confirmar las decisiones.** Aceptar o descartar cada índice es decisión del
  autor («se delega la escritura, nunca la decisión»). El 21/09/2026 el autor
  confirmó el descarte de las consultas P4-A, P4-B y S4-A. **Siguen pendientes
  de confirmación explícita** las decisiones de C1 (aceptar
  `idx_producto_categoria_precio`), C2 y C3 (descartar), que propuso la IA a
  partir de las mediciones: el autor debe revisarlas, hacerlas suyas o
  cambiarlas antes de entregar.
- **Defensa oral.** Poder explicar sin apoyo de IA por qué `INCLUDE` habilita el
  `Index Only Scan`, por qué el parcial sin `INCLUDE` no se usa, y por qué
  (id_producto, id_pedido) es un índice redundante.

---

## Parte B — tabla `usuario` y vista de reportes

La consigna del TP5 pide una vista que oculte la columna `contrasena` de una
tabla de login. El esquema original no tenía ese caso de uso; `cliente` no
maneja autenticación. Según la indicación documentada de la cátedra, se agregó
una tabla `usuario` separada de `cliente`, con `contrasena` hasheada y `rol`
como tipo ENUM.

Se agregó `vista_usuario_reportes`, que excluye explícitamente `contrasena` y
expone solamente usuarios vigentes. Las cuatro vistas existentes sobre las
tablas de negocio se mantienen sin cambios. La spec específica está en
`food-store/specs/spec_usuario.md`.

La decisión se aparta del punto general de no modificar el modelo únicamente
por la indicación explícita de la cátedra para este criterio de seguridad.
