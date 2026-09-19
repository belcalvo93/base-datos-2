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

**Base de medición:** `practica_bd2`, con 5 categorías, 20.005 clientes, 50.010 productos,
200.005 pedidos y 500.151 detalles, después de la carga masiva y con `ANALYZE` corrido.

**Método:** cada candidato se leyó línea por línea antes de aplicarlo y se probó dentro de una
transacción que termina en `ROLLBACK`, verificando que no quedara instalado. Las mediciones son con
`EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.

## A.1 Especificación de los tres candidatos

| Campo | Contenido |
|---|---|
| Herramienta y propósito | Kiro, para especificar antes de generar |
| Spec entregado | `specs/spec_indice_productos_categoria_precio.md`, `specs/spec_indice_pedidos_cliente_fecha.md`, `specs/spec_indice_detalle_producto_pedido.md` |
| Qué propuso la IA | Un índice candidato por consulta: `(id_categoria, precio DESC) WHERE activo = TRUE`, `(id_cliente, fecha DESC)` y `(id_producto, id_pedido)` |
| Decisión | Los tres se probaron. Los tres se descartaron. Detalle en A.2 y A.3 |

Cada spec fija el objetivo, la consulta exacta, las columnas candidatas con su selectividad y el
criterio de aceptación. Es lo que separa delegar la escritura de delegar la decisión: a la IA se le da
el criterio con el que se va a aceptar o rechazar su propuesta, no se le pregunta qué conviene.

## A.2 Candidatos descartados por falta de mejora

| Candidato | Qué esperaba la IA | Qué pasó | Decisión |
|---|---|---|---|
| C1 — `(id_categoria, precio DESC) WHERE activo = TRUE` | Eliminar el `Sort` y bajar el tiempo | Mantuvo el `Sort` y empeoró: de 8,742 ms a 10,415 ms | Descartado |
| C2 — `(id_cliente, fecha DESC)` | Aprovechar el orden del índice y evitar el `Sort` | El planificador siguió eligiendo `idx_pedido_id_cliente` con `Sort`, mismos buffers | Descartado |

El caso de C2 tiene un dato que por sí solo justifica el descarte: el lote de escritura pasó de
**28,729 ms a 46,699 ms**, un 62,5 % más lento. Una mejora de lectura que no se materializó, contra un
costo de escritura que sí.

## A.3 Candidato descartado por sobreindexación

Este es el caso que la consigna exige documentar.

| Campo | Contenido |
|---|---|
| Índice propuesto por la IA | `(id_producto, id_pedido)` sobre `detalle_pedido` |
| Qué argumentó | Que cubriría el filtro por producto y el orden por pedido en una sola estructura |
| Decisión | **Descartado por redundancia** |
| Justificación técnica | El índice `idx_detalle_pedido_id_producto` ya resuelve el filtro por `id_producto`, y la restricción `UNIQUE (id_pedido, id_producto)` ya genera un índice que cubre el resto. El candidato no aporta un camino de acceso nuevo: duplica estructuras que el motor ya tiene, con el costo de mantenimiento correspondiente en cada escritura |
| Evidencia | Se probó igual: el plan mantuvo el `Sort` y el tiempo pasó de 0,382 ms a 0,455 ms |

Vale marcar que se probó antes de descartarlo. La redundancia se argumentó desde el esquema, pero la
decisión se tomó con la medición delante.

## A.4 Resultado

No se agregó ninguna sentencia a `indices.sql`. Los índices heredados cubren las consultas evaluadas.

Que la respuesta correcta haya sido "ninguno" no es un resultado menor: la consigna advierte contra la
intuición de que "un índice siempre ayuda", y acá las tres propuestas de la IA se rechazaron con
mediciones, no con opinión.

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
