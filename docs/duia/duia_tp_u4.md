# DUIA TP U4 — Uso de IA en el Trabajo Práctico U4

**Proyecto**: Base de Datos II - TP U4: Desnormalización controlada  
**Período**: Octubre 2026  
**Grupo**: Belén, Hernán, Elías, Bruno

---

## Regla del flujo

Este TP sigue el flujo definido en el steering:

1. **Kiro** → escribe y revisa specs en `food-store/specs/`
2. **OpenCode** → propone y genera el SQL a partir de una spec (empieza en modo Plan)
3. **Medición** → se ejecuta con `EXPLAIN (ANALYZE, BUFFERS)`
4. **El autor** → lee cada línea, ejecuta contra `bd2_tp4u4` y decide

Toda propuesta de la IA es una **hipótesis**. Cada uso, aceptado o descartado y con su motivo, se registra en este documento.

---

## Alerta recurrente

> **Precio unitario en detalle_pedido**: Es un dato histórico (R4). **No se debe proponer eliminarlo** por "duplicar" `producto.precio`. Si aparece esta propuesta, se descarta y se documenta como error clásico de la IA.

---

## Registro de uso por integrante

### Belén — Spec 1: FNBC Control de Lote

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 18/10/2026 | Kiro | Escribir la spec 1 | Pedido de spec con la regla de negocio, sin el texto de la consigna | Spec con esquema e instancia reconstruidos: columnas `id` y `cantidad`, PK simple, sin FK a `usuario`, otra instancia | Modificado | La consigna nunca llegó a Kiro; se corrigen §2.1, §2.2 y §3 con el texto de la consigna |
| 18/10/2026 | OpenCode (modo Plan) | Proponer el SQL de la Parte 1 a–d | Spec 1 + steering (primer prompt, abajo) | Script sobre el esquema de la spec; detectó que su instancia violaba la DF y ofreció corregirla | Descartado | El problema estaba en la spec, no en la instancia de la consigna, que cumple la DF; no se cambia la instancia |
| 18/10/2026 | OpenCode (modo Plan) | Rehacer la propuesta con la consigna | Consigna 4.1 y 4.2 pegada textualmente | Script con esquema e instancia exactos, análisis a–c en comentarios y 3 anomalías con SAVEPOINT | Aceptado con 4 cambios | d.3 pasa a mover una sola fila de 801 (muestra la redundancia); se quita `ON CONFLICT` de `lote`/`deposito`; se agrega pre-flight de `usuario`; se corrige el aviso de la cabecera |
| 18/10/2026 | Claude Code | Revisar spec y propuestas contra la consigna | Consigna, spec 1, propuestas de OpenCode | Detectó las diferencias de esquema e instancia y el error de d.3 | Aceptado | Verificado a mano: claves candidatas `{lote, depósito}` y `{lote, responsable}`; 3FN sí, FNBC no |
| 18/10/2026 | Kiro | Corregir las specs 1 y 2 | Mensaje de corrección con el esquema, la instancia y la descomposición de la consigna | Reescribió ambos archivos enteros y les quitó las tildes; luego perdió sus herramientas de edición | Descartado | Reescritura completa y pérdida de tildes; se restauraron los archivos con git checkout |
| 18/10/2026 | OpenCode (modo Build) | Aplicar la corrección de las specs 1 y 2 | Mismo mensaje, como ediciones puntuales | Cambios puntuales (30 inserciones y 39 borrados entre las dos specs) con tildes intactas; ajustó también las tablas de §4 y §6.1 para evitar contradicciones | Aceptado | Revisado el git diff línea por línea; los cambios extra eran necesarios por coherencia |
| 18/10/2026 | Claude Code | Retoques finales a la spec 1 y registro en el DUIA | Lista de cuatro ediciones puntuales | Unión de una línea partida y alineación de ON CONFLICT con el script | Aceptado | Cambios mínimos para que la spec coincida con el script verificado |

**Prompt tal como se entregó a OpenCode (primera propuesta):**

```text
Leé food-store/specs/spec_fnbc_control_lote.md, .kiro/steering/database.md y .kiro/steering/reglas_trabajo.md. Proponé el script SQL de la sección 6.1, para el archivo food-store/tp_fnbc_control_lote.sql, solo la primera mitad (Parte 1, puntos a a d de la consigna). Tiene que ser idempotente (DROP … IF EXISTS), correr en BEGIN; … ROLLBACK; y no tocar bd2_proyecto ni bd2_tp3. La base de trabajo es bd2_tp4u4. Por ahora no escribas ningún archivo: mostrame primero el plan y el SQL propuesto, y explicá cada sentencia.
```

### Hernán — Spec 2: FNBC Descomposición

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 20/10/2026 | OpenCode (modo Plan) | Proponer la segunda mitad de `food-store/tp_fnbc_control_lote.sql` (puntos e–f) | `spec_fnbc_descomposicion.md`, primera mitad de `tp_fnbc_control_lote.sql` y steering | DDL de `responsable_deposito` (R1) y `control_lote` (R2), migración desde `control_lote_almacen`, vista `v_control_lote_almacen` con `NATURAL JOIN` y verificación de equivalencia en ambas direcciones con `EXCEPT`, manteniendo `BEGIN; … ROLLBACK;` e idempotencia | Aceptado | Ejecutado contra `bd2_tp4u4`: `responsable_deposito` = 2 filas, `control_lote` = 3 filas, `v_control_lote_almacen` = 3 filas y ambos `EXCEPT` devuelven 0 filas |
| 20/10/2026 | OpenCode | Redactar la sección de Parte 1 (puntos e–f) en `docs/informe_tp_u4.md` y el resultado en `spec_fnbc_descomposicion.md` | Salida real de `psql` sobre `bd2_tp4u4` y criterios de la spec 2 | Sección `Parte 1 — Descomposición sin pérdida (puntos e–f)` en el informe y sección 8 de la spec 2 | Aceptado | Coincide con la salida verificada en el motor y documenta la unión sin pérdida y la no preservación de F1 |

### Elías — Spec 3: Carga de pedidos de hoy

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 19/10/2026 | Claude Code | Leer la consigna, el contexto del grupo y el repo; ubicar qué tareas son de Elías y en qué orden | Consigna (PDF), `contexto_tp_u4_para_ias.md`, specs y `docs/informe_tp_u4.md` de `origin/main` | Cadena de specs 3→4→5→6 con responsables, y detección de que la consulta del PDF no corre tal cual (`subtotal` y `eliminado` no existen; `fecha` es `TIMESTAMPTZ`) | Aceptado | Verificado contra `schema.sql`; la adaptación (monto = `cantidad * precio_unitario`, rango de fechas) coincide con la que fija la spec 4 |
| 19/10/2026 | Claude Code | Proponer alternativas para la carga de pedidos | Spec 3 y `carga_masiva.sql` | Cinco alternativas: A) `generate_series` con tabla temporal de productos vendibles; B) `LATERAL` + `ORDER BY random()`; C) clonar pedidos históricos a hoy; D) `registrar_pedido`; E) variante escalable `carga_masiva_bloque3_B.sql` | Aceptado la A | Elías eligió la A: es la más fácil de explicar y no depende del histórico; la B ordena ~50k productos por cada pedido; la D la descarta la spec |
| 19/10/2026 | Claude Code | Escribir `food-store/carga_pedidos_hoy.sql` (10.000 pedidos de hoy, 1 a 3 líneas por pedido) | Plan aprobado por Elías y spec 3 | Script con `DELETE` idempotente del día, inserción de pedidos, tabla temporal `tmp_vendibles` (activos con stock ≥ 3), `ON CONFLICT DO NOTHING` por el `UNIQUE (id_pedido, id_producto)`, verificaciones y `ROLLBACK` final | Aceptado con 1 cambio | Corrida de prueba con `ROLLBACK` en `bd2_tp4u4`: 10.000 pedidos, 20.054 detalles, 16.474 productos distintos, reparto de `forma_pago` parejo, consulta del 5.1 con 5 filas. Único cambio del autor: `ROLLBACK;` por `COMMIT;` (línea 140) para la corrida real, seguida de `VACUUM ANALYZE` |

**Nota de la carga:** se inserta directo en `detalle_pedido` (sin `registrar_pedido`), por lo que el stock no se descuenta; no afecta a la consulta medida. La base tiene solo 5 categorías (4 activas) y el script no filtra por `categoria.activo`, así que las ventas incluyen la categoría inactiva; se mantiene para que la consulta devuelva 5 filas, como exige la spec.

### Elías — Spec 4: Top Categorías (antes)

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 19/10/2026 | Claude Code | Escribir `food-store/medicion_top_categorias_antes.sql` (6 corridas de `EXPLAIN (ANALYZE, BUFFERS)`) | Spec 4 | Script de solo lectura dentro de `BEGIN … ROLLBACK`, con la 1.ª corrida como warm-up | Aceptado | Ejecutado por Elías en `bd2_tp4u4` tras el `VACUUM ANALYZE`; Execution Time: 69,256 / 71,525 / 68,483 / 72,302 / 70,405 / 71,044 ms |
| 19/10/2026 | Claude Code | Calcular la mediana, identificar el nodo dominante y redactar las secciones 2a y 2b del informe | Salida de las seis corridas y plan completo de la corrida 3 | Mediana de 71,044 ms (corridas 2 a 6); nodo dominante `Parallel Seq Scan on detalle_pedido`, sin índices sobre `pedido.fecha`; patrón tabla resumen con trigger, con respuestas a las 5 preguntas del profesor | Aceptado, pendiente de revisión del autor | Elías decidió el patrón (tabla resumen con trigger) y el volumen (10.000 pedidos); las respuestas 2 y 3 son supuestos marcados como tales en el informe y deben confirmarse |

### Bruno — Spec 5: Top Categorías Desnormalización

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 19/10/2026 | Claude Code | Revisar la spec 5 contra la consigna y el esquema antes de pasarla a OpenCode | Consigna 5.2, spec 5, `schema.sql`, steering | Cinco observaciones: filas que quedan en 0, índice sobre la columna que cambia en cada venta, UPDATE que cambia de categoría o de día, casos que el trigger no ve, contención sobre las filas de cada categoría | Aceptado | Las cinco se pueden comprobar en el esquema; se pasan a la spec como ediciones puntuales |
| 19/10/2026 | Claude Code | Comprobar qué ve el trigger cuando se borra un pedido en cascada | Base descartable con `pedido` y `detalle_pedido` reducidos | Los triggers `BEFORE` y `AFTER` de `detalle_pedido` ven NULL al buscar el pedido | Aceptado | Se agrega a la spec un trigger `BEFORE DELETE` sobre `pedido` que llama a la misma función. Se probó un prototipo: la auditoría dio 0 filas en todos los casos |
| 19/10/2026 | Claude Code | Corregir la spec 5 | Las observaciones anteriores | PK `(fecha, id_categoria)` sin índice extra, columna `cantidad_lineas`, reglas del trigger, casos fuera de alcance y criterios de aceptación | Aceptado | Revisado contra el `git diff` |
| 20/10/2026 | Claude Code | Actualizar en la spec 5 el patrón elegido, a pedido de Belén | Decisión de Elías (punto 2b) | Una línea en la sección 3 | Aceptado | La línea seguía diciendo que el patrón se iba a definir en la spec 4 |

### Bruno — Spec 6: Top Categorías Auditoría

| Fecha | Herramienta | Propósito | Input | Output | Decisión | Motivo |
|-------|-------------|-----------|-------|--------|----------|--------|
| 19/10/2026 | Claude Code | Corregir la spec 6 en línea con la spec 5 | Spec 6 y los cambios de la spec 5 | Auditoría del Patrón 1 con `cantidad_lineas`, recálculo escrito una sola vez y columna `lado`; aviso de que la del Patrón 2 se corre después del refresco; tres pruebas de detección | Aceptado | La consulta se ejecutó en la base descartable: 0 filas sincronizada, 2 filas con una escritura a mano en el resumen |

---

## Apartamientos del flujo

Si alguien se aparta del flujo (por ejemplo, usa Claude Code en lugar de OpenCode para proponer SQL), se declara aquí:

| Fecha | Integrante | Apartamiento | Justificación |
|-------|------------|--------------|---------------|
| 18/10/2026 | Belén | Las correcciones a las specs 1 y 2 las aplicó OpenCode en lugar de Kiro | Kiro quedó sin herramientas de edición y su reescritura degradó los archivos (sin tildes) |
| 19/10/2026 | Elías | El SQL de las specs 3 y 4 (`carga_pedidos_hoy.sql` y `medicion_top_categorias_antes.sql`) y la redacción de 2a y 2b las propuso Claude Code en lugar de OpenCode | Se trabajó en una sola sesión de Claude Code; se mantuvo el principio de delegar la escritura y no la decisión: Elías eligió alternativa, volumen y patrón, ejecutó todo en `bd2_tp4u4` con `BEGIN … ROLLBACK` primero y verificó la salida |
| 19/10/2026 | Bruno | Las correcciones a las specs 5 y 6 las hizo Claude Code en lugar de Kiro | Las correcciones salieron de una prueba ejecutada en el motor (el borrado en cascada), y Kiro no ejecuta SQL. Se aplicaron como ediciones puntuales, para evitar la reescritura completa que ya había pasado con Kiro en las specs 1 y 2. El SQL final lo propone OpenCode |

---

## Notas

- La sección 8 de cada spec ("Resultado de la medición") se completa después de medir.
- Las filas de uso se van completando a medida que cada integrante trabaja con las herramientas.
- Este documento consolida el registro de TODAS las propuestas de IA del TP U4.