# DUIA — Declaración de Uso de IA, TP5

Bitácora de uso de IA de la Unidad 3, con los cuatro campos que pide el punto 6 de la consigna:
herramienta y propósito, el spec o prompt tal como se entregó, qué propuso la IA, y qué se aceptó,
modificó o descartó con su justificación técnica.

Consolida lo registrado por cada integrante. El detalle de cada medición está en
`informe_mediciones.md`; las especificaciones completas, en `specs/`.

## Los dos casos que la consigna exige

El punto 6 pide como mínimo dos registros. Están en las secciones A.3 y B.3 de este documento:

| Requisito | Dónde está |
|---|---|
| Un índice descartado por sobreindexación (Parte A) | A.3 — candidato C3, redundante |
| La verificación de equivalencia de al menos una vista (Parte B) | B.3 — las cinco vistas, con `EXCEPT` |

---

# Parte A — Plan de indexado

**Base de medición:** `bd2_tp3`, restaurada del dump `bd2_tp3_actualizada_20260919.dump`, con 5 categorías,
20.005 clientes, 50.011 productos, 200.005 pedidos y 499.263 detalles, y `VACUUM ANALYZE` corrido. Se
midió en una instancia temporal de PostgreSQL 17.11 con configuración por defecto.

**Método:** cada índice candidato se probó dentro de `BEGIN … ROLLBACK`, con `EXPLAIN (ANALYZE, BUFFERS,
VERBOSE)` (mediana de 5 corridas, más `pgbench` en las consultas de décimas de milisegundo). El costo de
escritura se midió con 500 `INSERT` por tabla y 500 `UPDATE` de `stock`, en 15 rondas, con tiempo y bytes
de WAL. El método completo está en `informe_mediciones.md`.

**Esta versión reemplaza a la anterior de la Parte A** (commit `e711e99`), medida sobre `practica_bd2`
(50.010 productos y 500.151 detalles) con otros parámetros (categoría 10, cliente 10, producto 64074) y que
descartaba los tres índices. Esos parámetros no devuelven filas en el dump, así que se volvió a los de
`queries.sql` (categoría 5, cliente 20155, producto 49112), que son también los del informe del TP3. La
conclusión distinta (acá se acepta la variante con `INCLUDE` de C1) no contradice a la anterior: aquella no
probó esa variante.

El registro completo de esta parte, con las 19 filas de uso y el detalle de cada verificación, está en
`docs/duia/duia_parte5.md`.

## A.1 Herramientas, specs y prompts

| Campo | Contenido |
|---|---|
| Herramienta y propósito | **Kiro:** redactó las tres specs de C1, C2 y C3 (commit `e5e7907`) y revisó las tres de P4-A, P4-B y S4-A. **OpenCode:** propuesta de índice para las tres consultas con `Seq Scan` (P4-A, P4-B y S4-A), en cuatro sesiones del 21/09/2026, modo Plan. **Claude Code (Claude Sonnet 5):** restaurar el dump, ejecutar las mediciones, proponer la variante de C1 y escribir `indices.sql`, `medicion_planes.sql`, `medicion_escritura.sql` y el informe |
| Spec entregado | `specs/spec_indice_productos_categoria_precio.md` (C1), `specs/spec_indice_pedidos_cliente_fecha.md` (C2), `specs/spec_indice_detalle_producto_pedido.md` (C3), `specs/spec_indice_facturacion_categoria.md` (P4-A), `specs/spec_indice_productos_nunca_vendidos.md` (P4-B) y `specs/spec_indice_facturacion_categoria_mes.md` (S4-A). Cada una fija la consulta, la frecuencia, las columnas de filtro, join y orden, la hipótesis para el generador y el criterio de aceptación con su salida de descarte |
| Qué se aceptó, modificó o descartó | Un índice aceptado y cinco descartados, todos con medición. Detalle en A.2 |

**Apartamiento declarado.** Para C1, C2 y C3 la propuesta de índice la hizo Claude Code y no OpenCode, que es
la herramienta que nombra la consigna. Fue una decisión del autor, por rendimiento y facilidad de uso. Para
las tres consultas con `Seq Scan` sí se siguió el flujo Kiro → OpenCode → medición. C1, C2 y C3 fueron
**reescritos y modificados por Claude Code**: rehízo la Parte A sobre el dump, restauró los parámetros
originales de las tres specs, propuso la variante con `INCLUDE` de C1 (que no estaba en la spec de Kiro) y
propuso el descarte de C2 y C3. El autor confirmó cada decisión el 21/09/2026.

**Prompts tal como se entregaron.** A Claude Code se le dio el dump, la consigna y el repositorio con las
specs, y este pedido:

> "necesito rehacer la parte A de este trabajo, basado en el dump o copia de base de dato ficticia. para que
> coincida los informes con el repo vinculado"

A Kiro, una sesión por cada spec nueva, con la spec abierta:

```text
Revisá esta spec según .kiro/steering/reglas_trabajo.md. Verificá que tenga la
estructura fija, que el SQL de la consulta sea exactamente el de
food-store/queries.sql y que el criterio de aceptación tenga salida de
descarte. Marcá lo que falte, lo que sobre o lo que sea ambiguo. No ejecutes
SQL y no modifiques la consulta. Proponé los cambios como una lista; no
reescribas la spec entera.
```

A OpenCode, una sesión limpia por spec, con la spec adjunta (`<archivo de la spec>` es la de P4-A, P4-B o
S4-A):

```text
Contexto: PostgreSQL 17, esquema en @food-store/schema.sql, consultas en @food-store/queries.sql.
Te paso una spec. Proponé el índice adecuado: tipo, columnas, orden,
INCLUDE y condición parcial si corresponde. Para cada propuesta indicá:
qué nodo del plan elimina, cuánto pesa el índice frente a la tabla y si es
redundante con un índice existente. Si creés que ningún índice lo justifica,
decilo y explicá por qué. No ejecutes nada; solo proponé el SQL.
Spec: @food-store/specs/<archivo de la spec>
```

En las sesiones 2, 3 y 4 se agregó antes de la línea `Spec:` la instrucción «Leé únicamente los archivos que
te indico en este mensaje; no abras ningún otro archivo del repositorio». En las sesiones 3 y 4 se ocultaron
además `indices.sql`, el informe y los planes, para que la propuesta no dependiera de las mediciones previas.

## A.2 Qué propuso la IA y qué se decidió

| Candidato | Consulta | Quién lo propuso | Qué pasó en la medición | Decisión |
|---|---|---|---|---|
| `(id_categoria, precio DESC) WHERE activo`, sin `INCLUDE` | C1 | Kiro (hipótesis de la spec) | El planificador no lo usa: sigue con el índice del TP1 y `Sort`. Tiempo idéntico al base (10,5 ms). Cuesta +27 % de WAL por `INSERT` en `producto` | Descartado |
| **`(id_categoria, precio DESC) INCLUDE (id_producto, nombre, stock) WHERE activo`** | C1 | Claude Code, al ver que la hipótesis no se usaba | `Index Only Scan` sin `Sort`, `Heap Fetches: 0`. De 10,5 a 3,1 ms y de 527 a 86 buffers. Resultado idéntico fila a fila | **Aceptado** |
| `(id_cliente, fecha DESC)` | C2 | Kiro (spec) | La consulta devuelve 24 filas y el `Sort` es insignificante. El plan no cambia (0,152 contra 0,151 ms). Cuesta +26 % de WAL por `INSERT` en `pedido` | Descartado |
| `(id_producto, id_pedido)` | C3 | Kiro (spec) | Ver A.3 | Descartado |
| `(id_producto) INCLUDE (id_detalle, cantidad, precio_unitario)` | P4-A | OpenCode propuso ninguno; se midió este cubriente | El planificador lo ignora y sigue con `Seq Scan` (743 contra 735 ms). Pesa 24 MB frente a 33 MB de tabla. Cuesta +21 % de WAL por `INSERT` en `detalle_pedido` | Descartado |
| Ninguno (el índice existente alcanza) | P4-B | OpenCode | `idx_detalle_pedido_id_producto` ya sirve. Con `random_page_cost = 1.1` el planificador lo usa solo y baja de 258 a 110 ms | Descartado: no falta un índice |
| `(id_producto) INCLUDE (id_pedido, cantidad, precio_unitario)` | S4-A | OpenCode propuso ninguno; se midió este cubriente | Plan y tiempo no cambian (2.219 contra 2.246 ms). El costo está en el `Hash Join`, la agregación y un ordenamiento de 23 MB a disco | Descartado: la mejora es la vista materializada de la Parte C |

## A.3 Candidato descartado por sobreindexación

Este es el caso que la consigna exige documentar.

| Campo | Contenido |
|---|---|
| Índice propuesto | `(id_producto, id_pedido)` sobre `detalle_pedido`, la hipótesis de la spec de C3 |
| Qué argumentó | Que `id_pedido` ayudaría al `JOIN` con `pedido` |
| Decisión | **Descartado por redundancia** (propuesto por Claude Code, confirmado por el autor) |
| Justificación técnica | Es un superconjunto de `idx_detalle_pedido_id_producto`: su primera columna es la del índice existente, así que todo lo que sirve el nuevo lo sirve el viejo. No aporta lo que promete: el `JOIN` con `pedido` va por `pedido_pkey`, y `cantidad` y `precio_unitario` se leen igual del heap. Además `id_pedido` ya está cubierto por `UNIQUE (id_pedido, id_producto)` |
| Evidencia | Se probó antes de descartarlo. El planificador lo usa, pero el plan, el costo estimado y los 27 bloques de heap son los mismos. `pgbench`: 0,68–0,86 ms sin el índice contra 0,73–0,78 ms con él, rangos que se superponen |
| Costo que se evitó | +17 % de WAL en cada `INSERT` de `detalle_pedido`, la tabla que más se escribe, más espacio y mantenimiento en cada `UPDATE` y `DELETE` |

Como en el resto de la parte, la redundancia se argumentó desde el esquema y la decisión se tomó con la
medición delante. El razonamiento completo está en la sección 7 del informe.

## A.4 El índice aceptado y su costo

Se acepta `idx_producto_categoria_precio` (C1), que está en `indices.sql`. Se descartó primero la hipótesis de
la spec y se aceptó la variante que propuso Claude Code, con `INCLUDE (id_producto, nombre, stock)`, después de
verificar que devuelve exactamente las mismas filas que la consulta sin el índice (`EXCEPT` en las dos
direcciones, 0 filas, sobre 10.047 filas, con el orden por `precio` descendente comprobado).

Se aceptó con el costo a la vista: +45 % de WAL y +32 % de tiempo por `INSERT` en `producto`, y +32 % de WAL
y +50 % de tiempo por `UPDATE` de `stock`, con el índice de 3,3 MB frente a los 360 kB del del TP1. Los
riesgos que el autor debe poder defender están en la sección 8 del informe: si en la Semana 6 los procedimientos
descuentan stock en cada venta, el costo de `INCLUDE (stock)` pasa a ser por línea de venta y la decisión hay
que revisarla; y el `Index Only Scan` depende de que el autovacuum mantenga el mapa de visibilidad.

## A.5 OpenCode y las consultas con `Seq Scan`

Las respuestas de OpenCode se trataron como hipótesis y se contrastaron con el motor.

| Sesión | Consulta | Modelo | Propuesta | Independiente de las mediciones |
|---|---|---|---|---|
| 1 | P4-A | `ling-3.0-flash-fin-free` | Ningún índice | No: abrió `indices.sql`, que traía la medición del mismo índice, y la citó |
| 2 | P4-A (con la línea «leé únicamente los archivos que te indico») | `ling-3.0-flash-fin-free` | Ningún índice | No: ignoró la instrucción y abrió `indices.sql` de nuevo |
| 3 | P4-B | `gemini-3.5-flash-lite` | Ningún índice nuevo | Sí: solo abrió los tres archivos permitidos |
| 4 | S4-A | `gemini-3.5-flash-lite` | Ningún índice | Sí: solo abrió los tres archivos permitidos |

Las cuatro coinciden con la medición, pero tuvieron errores que se detectaron al contrastarlas:

* **Cifras incorrectas:** «~20K productos activos» (son 50.010), «5 categorías activas» (son 4), «+24-27 % de
  WAL» para el índice de P4-A (cifra sin sustento: el 26 y el 27 % del repositorio son de otros índices),
  «+17 % de WAL» tomado del índice de C3 y no del analizado, y una «query C del TP4» que no existe.
* **Generalización falsa** (sesiones 1, 2 y 4): «un `Seq Scan` siempre supera a cualquier índice cuando se lee
  toda la tabla». P4-B la contradice: un `Index Only Scan` sobre un índice de 4,5 MB deja la consulta en menos
  de la mitad del tiempo.
* **Imprecisión** (sesión 3): dice que `UNIQUE (id_pedido, id_producto)` cubre `id_producto`. Empieza por
  `id_pedido`, así que solo `idx_detalle_pedido_id_producto` sirve para buscar por producto.

La conclusión que sí se sostiene con mediciones: un `Seq Scan` que lee la mayor parte de la tabla es la
elección correcta y no un síntoma. Ningún índice nuevo mejora estas tres consultas.

## A.6 Errores de la IA detectados y corregidos

Los errores de Claude Code también quedaron registrados:

* **Prueba exploratoria de P4-A sin `id_detalle`:** el índice de esa prueba no podía dar un `Index Only Scan`,
  porque la consulta hace `COUNT(dp.id_detalle)`. Lo advirtió el razonamiento de OpenCode. Se rehízo con el
  índice correcto y la conclusión se mantuvo.
* **`INCLUDE (nombre, stock)` en C1:** faltaba `id_producto`, que la consulta también devuelve, y el plan era
  un `Index Scan` con visita al heap. Se corrigió a `INCLUDE (id_producto, nombre, stock)`.
* **Sesgo de posición en la medición de escritura:** la primera versión daba ~60 % de diferencia entre dos
  mediciones del mismo estado. Se corrigió con calentamiento y `VACUUM` tras cada `ROLLBACK`, y se agregaron los
  bytes de WAL como métrica determinista.
* **Cifras de tiempo de escritura en `indices.sql`:** la primera redacción decía +31 % y +43 %. Recalculadas
  desde las medianas son +32 % y +50 %.

## A.7 Resultado

Se agrega **una** sentencia a `indices.sql`: `idx_producto_categoria_precio`. Los otros cinco candidatos
(C1 sin `INCLUDE`, C2, C3, P4-A y S4-A) y la ausencia de índice en P4-B quedan documentados en el mismo archivo
con su motivo.

La consigna advierte contra la intuición de que «un índice siempre ayuda»: de siete propuestas o hipótesis, seis
se rechazaron con mediciones y no con opinión, y la que se aceptó solo funciona con una variante que la
hipótesis original no traía.

**Pendiente declarado.** Los exports de las cuatro sesiones de OpenCode están fuera del repositorio, y falta
repetir `medicion_escritura.sql` sobre `bd2_trabajo`. Ambos puntos están detallados en la sección «Pendiente del
autor» de `docs/duia/duia_parte5.md`.

---

# Parte B — Vistas

## B.1 Especificación y generación

| Campo | Contenido |
|---|---|
| Herramienta y propósito | Kiro para especificar, OpenCode para generar el SQL |
| Spec entregado | `specs/spec_vistas.md` y `specs/spec_usuario.md` |
| Qué propuso la IA | Las cinco vistas de `views.sql` a partir de las specs |
| Qué se aceptó | Las cinco, después de verificar la equivalencia de resultados una por una |

Las specs fijan las columnas a exponer, el filtro de vigencia de cada tabla y el criterio de
aceptación con las consultas `EXCEPT` ya escritas. La vista no se da por válida hasta que esas
consultas devuelven cero filas.

## B.2 La columna que no existía

La consigna pide una vista que exponga el usuario sin la columna `contrasena`, de modo que se pueda dar
`SELECT` sobre la vista sin dar acceso a la tabla base. **El esquema del proyecto no tenía esa columna:**
`cliente` guarda datos de contacto, no credenciales, porque el modelo nunca contempló autenticación.

Se consultó a la cátedra. Por indicación de Sergio Neira se agregó una tabla `usuario` separada de
`cliente`, con la contraseña hasheada y `rol` como ENUM, y sobre ella la vista
`vista_usuario_reportes`, que excluye explícitamente la contraseña y expone solo usuarios vigentes.

Las cuatro vistas que ya existían sobre las tablas de negocio se mantienen sin cambios: la tabla
`usuario` se agregó al costado, no reemplaza a `cliente` ni altera lo que había.

Esto se aparta del punto general de no modificar el modelo de datos, y se documenta acá por eso: la
excepción es por indicación expresa del docente para cumplir el criterio de seguridad del punto 4, no
una decisión del equipo.

**Punto 1 de la devolución del profesor — GRANT sobre `vista_usuario_reportes`.** Para que la vista
pueda usarse en reportes sin dar acceso a la tabla base `usuario`, se implementó el `GRANT SELECT` sobre
`vista_usuario_reportes` a un rol de prueba (`rol_reportes`, sin permisos por defecto) y se probó
manualmente en el motor con `psql`. En este caso puntual el SQL lo guió Claude Code y la verificación fue
manual; no hubo generación de SQL por Kiro ni por OpenCode, y se declara como apartamiento igual que los
otros de esta bitácora. La verificación fue la misma que se documentó en `informe_mediciones.md`: el rol
accede a la vista (devuelve las 2 filas vigentes) pero no puede leer la tabla `usuario` directamente
(`ERROR: permiso denegado`).

## B.3 Verificación de equivalencia

El caso que la consigna exige. Por cada vista se ejecutó el `EXCEPT` en las dos direcciones contra la
consulta manual equivalente. Las dos direcciones tienen que dar cero filas: una sola no alcanza, porque
detecta filas de más pero no filas de menos.

| Vista | Filas | `vista EXCEPT consulta` | `consulta EXCEPT vista` | Equivalente |
|---|---:|---:|---:|---|
| `vista_cliente_completo` | 20.005 | 0 | 0 | Sí |
| `vista_pedidos_cliente` | 200.005 | 0 | 0 | Sí |
| `vista_productos_vigentes` | 39.963 | 0 | 0 | Sí |
| `vista_detalle_pedido_producto` | 499.263 | 0 | 0 | Sí |
| `vista_usuario_reportes` | 2 | 0 | 0 | Sí |

La vista de seguridad tiene una comprobación más: con 3 usuarios de prueba (1 ADMIN, 1 USUARIO vigente y 1 con `eliminado = TRUE`), devuelve solo los 2 vigentes, y `information_schema.columns` confirma que `contrasena` no aparece entre sus columnas. Los hashes de prueba son placeholders, nunca texto plano.

Un detalle que la verificación deja a la vista: `vista_productos_vigentes` devuelve 39.963 filas sobre
50.010 productos. La diferencia es el filtro de vigencia, que descarta productos inactivos y también los
de categorías dadas de baja. `vista_detalle_pedido_producto`, en cambio, no filtra por vigencia a
propósito: reconstruye ventas pasadas, y excluir líneas cuyo producto se dio de baja después haría que
algunos pedidos aparecieran incompletos.

---

# Parte C — Vista materializada

**Base de medición:** `practica_bd2`, 200.005 pedidos y 500.151 detalles, con `ANALYZE` corrido.
Reporte materializado: facturación por categoría y mes (Consulta A de la Semana 4). Implementación:
`materializadas.sql`; mediciones completas en `informe_mediciones.md`, Parte C.

## C.1 Especificación y generación

| Campo | Contenido |
|---|---|
| Herramienta y propósito | Kiro para especificar antes de generar; OpenCode para producir el SQL y explicar el plan |
| Spec entregado | `specs/spec_vista_materializada_parteC.md` |
| Qué propuso la IA | `CREATE MATERIALIZED VIEW mv_facturacion_cat_mes` con `WITH DATA` (default) y el índice único `uq_mv_facturacion_cat_mes` sobre `(id_categoria, mes)` para habilitar `REFRESH MATERIALIZED VIEW CONCURRENTLY` |
| Qué se aceptó, modificó o descartó | Se aceptó la propuesta tal cual, pero sólo después de verificar contra el motor cada uno de los puntos del criterio de aceptación (tiempos, `COUNT`, exactitud y refresco) |

## C.2 Verificación con el motor

| Prueba | Resultado |
|---|---|
| Consulta sin materializar | 870,172 ms — `Parallel Hash Join` (2 workers) + `Sort` `external merge` (8.000 kB), 399.184 filas intermedias |
| Vista materializada | 0,070 ms — `Seq Scan` de 100 filas |
| `COUNT(*)` de la vista | 100, coincide con el `rows=100` del plan de la consulta original |
| `REFRESH MATERIALIZED VIEW CONCURRENTLY` | Corre sin error en 0,927 s → el índice único cumple la condición para refrescar sin bloquear lecturas |
| Equivalencia `EXCEPT` | Dirección `vista EXCEPT consulta`: 0 filas. Dirección `consulta EXCEPT vista`: 0 filas |

El detalle de la lectura crítica del plan está en `specs/spec_vista_materializada_parteC.md`: el
`Sort external merge` a disco y la dispersión entre ~500.000 líneas de origen y 100 filas de salida son
los argumentos medidos de por qué materializar. Ningún `CREATE` se ejecutó sin haberlo leído línea por
línea y probado antes en una transacción con `ROLLBACK`.
