# Informe TP U4 — FNBC y desnormalización controlada en Food Store

## Datos del trabajo

Trabajo práctico de la Unidad 4 de Base de Datos II (Tecnicatura Universitaria en Programación, UTN), sobre el proyecto Food Store, con el profesor Sergio Neira.

| Dato | Detalle |
| --- | --- |
| Grupo | Belén Calvo, Hernán González, Elías Tello y Bruno Fiouchetta |
| Repositorio | [belcalvo93/base-datos-2](https://github.com/belcalvo93/base-datos-2) |
| Base de trabajo | `bd2_tp4u4`, copia de `bd2_tp3` (PostgreSQL 17) |
| Scripts entregados | `food-store/tp_fnbc_control_lote.sql` y `food-store/tp_desnormalizacion_top_categorias.sql` |
| Herramientas | Kiro (specs), OpenCode (SQL), Claude Code (revisión y mediciones), PostgreSQL y Git Bash |

## Parte 1 — FNBC de `control_lote_almacen` (puntos a–d)

`control_lote_almacen` está en 3FN pero **no en FNBC**: la dependencia ResponsableControlID → DepositoID tiene un determinante que no es superclave. Todo lo que sigue se demuestra con `food-store/tp_fnbc_control_lote.sql`, ejecutado sobre `bd2_tp4u4`, que termina en `ROLLBACK`.

Esquema: R(LoteID, DepositoID, ResponsableControlID). Instancia de la consigna: (501, 30, 801), (502, 30, 801), (503, 31, 802).

### a) Dependencias funcionales

- **F1:** {LoteID, DepositoID} → ResponsableControlID. Primera regla de negocio: para un lote y un depósito dados, el responsable queda determinado. La garantiza la clave primaria.
- **F2:** ResponsableControlID → DepositoID. Segunda regla: cada responsable pertenece a un único depósito.

*Artefacto (bloque a del script):* `pg_get_constraintdef` muestra la PK `(lote_id, deposito_id)` y las tres FK. F2 no está declarada como restricción, por eso el motor no la hace cumplir. La consulta de verificación (`GROUP BY responsable_control_id HAVING COUNT(DISTINCT deposito_id) > 1`) devuelve **0 filas**: no hay contraejemplo en la instancia. Los datos pueden refutar una DF, pero no demostrarla para toda extensión posible.

### b) Clausuras y claves candidatas

| Conjunto X | Clausura X⁺ | ¿Superclave? |
| --- | --- | --- |
| {LoteID, DepositoID} | {LoteID, DepositoID, ResponsableControlID}, por F1 | Sí, clave candidata |
| {LoteID, ResponsableControlID} | {LoteID, ResponsableControlID, DepositoID}, por F2 | Sí, clave candidata |
| {ResponsableControlID} | {ResponsableControlID, DepositoID}, por F2 | No |
| {LoteID} | {LoteID} | No |
| {DepositoID} | {DepositoID} | No |
| {DepositoID, ResponsableControlID} | {DepositoID, ResponsableControlID}; F1 necesita LoteID | No |

Claves candidatas: {LoteID, DepositoID} y {LoteID, ResponsableControlID}. Atributos primos: los tres. No primos: ninguno.

### c) Determinación de FNBC

Definición: R está en FNBC si, para toda dependencia no trivial X → A, X es superclave de R.

- **F1:** el determinante {LoteID, DepositoID} es clave candidata. Cumple.
- **F2:** el determinante ResponsableControlID tiene clausura {ResponsableControlID, DepositoID}, distinta de R. **No es superclave: F2 viola la FNBC.**

La relación sí cumple 3FN, porque DepositoID es atributo primo. Por eso la 3FN no lo detecta y la FNBC sí.

### d) Anomalías

Hay redundancia: el hecho "801 pertenece al depósito 30" se guarda dos veces, en los lotes 501 y 502. Cada anomalía se probó en el script con `SAVEPOINT` y se deshizo.

| Anomalía | Escenario | Qué pasa | Evidencia en el script |
| --- | --- | --- | --- |
| Inserción | Registrar (501, 31, 801) | La PK está libre y las FK son válidas: el motor lo acepta y 801 queda en dos depósitos (30 y 31), contra la regla. Nada en la tabla lo impide. | Bloque d.1: la consulta de verificación pasa de 0 filas a 1 (responsable 801) |
| Borrado | Eliminar (503, 31, 802), el único control de 802 | Se pierde que 802 pertenece al depósito 31: no está en ninguna otra fila. | Bloque d.2: la tabla pasa de 3 filas a 2 y 802 desaparece |
| Actualización | Mover a 801 al depósito 31 cambiando solo (501, 30, 801) | 801 queda en los depósitos 30 y 31 a la vez. Para moverlo hay que actualizar todas sus filas. | Bloque d.3: la consulta de verificación devuelve 801 |

La descomposición que corrige esto se desarrolla en los puntos e y f, en la sección siguiente.

## Parte 1 — Descomposición sin pérdida (puntos e–f)

### e) Descomposición en FNBC

A partir de la dependencia que violaba FNBC (**F2:** ResponsableControlID → DepositoID), se descompone `control_lote_almacen` en dos relaciones:

| Relación | Tabla SQL | Esquema y restricciones | ¿Cumple FNBC? |
| --- | --- | --- | --- |
| **R₁** | `responsable_deposito` | `(responsable_control_id PK, deposito_id)` con FK a `usuario(id)` y `deposito(id)` | **Sí:** la única DF no trivial es F2 y su determinante (`responsable_control_id`) es la clave primaria (superclave de R₁). |
| **R₂** | `control_lote` | `(lote_id, responsable_control_id)` con PK compuesta y FK a `lote(id)` y `responsable_deposito(responsable_control_id)` | **Sí:** no tiene DFs no triviales propias; su única clave candidata es la tupla completa `{lote_id, responsable_control_id}`. |

- **Unión sin pérdida (Teorema de Heath):** el atributo común entre ambas relaciones es $R_1 \cap R_2 = \{\text{responsable\_control\_id}\}$. Como en $R_1$ se cumple $\text{responsable\_control\_id} \rightarrow \text{deposito\_id}$, el atributo común es **superclave de $R_1$**, lo que garantiza que $R_1 \bowtie R_2$ reconstruye exactamente la relación original sin generar tuplas espurias ni perder información.
- **Preservación de dependencias funcionales:** **F2** queda impuesta estructuralmente por la PK de `responsable_deposito` (lo que elimina las tres anomalías del punto d). En cambio, **F1** ($\{\text{LoteID}, \text{DepositoID}\} \rightarrow \text{ResponsableControlID}$) **no se preserva** en una sola tabla, porque `lote_id` quedó en `control_lote` y `deposito_id` en `responsable_deposito`. Este es el *trade-off* clásico al pasar de 3FN a FNBC: validar F1 requeriría un *join* entre ambas tablas.

### f) Migración, vista de compatibilidad y verificación con `EXCEPT`

En la segunda mitad de `food-store/tp_fnbc_control_lote.sql` se migran los datos desde `control_lote_almacen` y se crea la vista de compatibilidad mediante `NATURAL JOIN` (cuya única columna homónima es `responsable_control_id`):

- **`responsable_deposito` (R₁):** recibe `SELECT DISTINCT responsable_control_id, deposito_id FROM control_lote_almacen` → **2 filas** (`(801, 30)` y `(802, 31)`), eliminando la repetición del depósito 30 para el responsable 801.
- **`control_lote` (R₂):** recibe `SELECT lote_id, responsable_control_id FROM control_lote_almacen` → **3 filas** (`(501, 801)`, `(502, 801)` y `(503, 802)`).
- **Vista `v_control_lote_almacen`:** `SELECT lote_id, deposito_id, responsable_control_id FROM control_lote NATURAL JOIN responsable_deposito` → reconstruye las **3 filas** originales (`(501, 30, 801)`, `(502, 30, 801)`, `(503, 31, 802)`).
- **Verificación de equivalencia de conjuntos ($R = V \iff R \setminus V = \emptyset \land V \setminus R = \emptyset$):**
  1. `SELECT ... FROM control_lote_almacen EXCEPT SELECT ... FROM v_control_lote_almacen` → **0 filas** (no se perdieron tuplas).
  2. `SELECT ... FROM v_control_lote_almacen EXCEPT SELECT ... FROM control_lote_almacen` → **0 filas** (no aparecieron tuplas espurias).

## Parte 2 a — Consulta y medición antes

**Datos de la medición.** Base `bd2_tp4u4` (copia de `bd2_tp3`) con 200.005 + 10.000 pedidos, 499.263 + 20.012 detalles y 50.011 productos; los 10.000 pedidos y ~20.000 detalles de "hoy" (19/10/2026) se cargaron con `food-store/carga_pedidos_hoy.sql`, seguido de `VACUUM ANALYZE`. La base tiene solo 5 categorías, por lo que el top 5 las devuelve todas. La base que se usa en 2d parte de esta misma y suma otra carga del 21/10/2026, por eso los tiempos de 2a y de 2d no son directamente comparables (se explica en 2d).

**Consulta medida.** La del punto 5.1, adaptada al esquema real: el monto es `cantidad * precio_unitario` (el subtotal no se almacena), el filtro de hoy es un rango sobre `pedido.fecha` (es `TIMESTAMPTZ`, no `DATE`) y no hay columnas `eliminado`.

```sql
SET timezone = 'America/Argentina/Mendoza';
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;
```

**Resultado.** Script: `food-store/medicion_top_categorias_antes.sql`; salida completa en `food-store/medicion_antes_salida.txt`. Seis corridas con `EXPLAIN (ANALYZE, BUFFERS)`; la primera es warm-up y se descarta.

| Corrida | Execution Time (ms) |
|---|---|
| 1 (warm-up, descartada) | 69,256 |
| 2 | 71,525 |
| 3 | 68,483 |
| 4 | 72,302 |
| 5 | 70,405 |
| 6 | 71,044 |
| **Mediana (corridas 2–6)** | **71,044** |

**Nodo dominante.** El plan no usa ningún índice: hay tres `Seq Scan` encadenados por `Hash Join`. El nodo hoja más costoso es el `Parallel Seq Scan on detalle_pedido` (costo 6658 de 14480): recorre las ~519.000 filas de la tabla para quedarse con las ~20.000 del día. Le sigue el `Parallel Seq Scan on pedido`, que lee 210.005 filas y descarta 200.005 por no existir un índice sobre `pedido.fecha`, y el `Seq Scan on producto`, que se vuelve a leer y a hashear (50.011 filas) en cada uno de los 3 procesos del plan paralelo. El costo crece con el histórico de la base, no con el volumen del día.

Plan "antes" (corrida 3, resumido; el plan completo está en `food-store/medicion_antes_salida.txt`):

```text
Limit (actual time=63.898..68.237 rows=5 loops=1)
  Buffers: shared hit=6173 read=1537
  ->  Sort  Sort Key: (sum(dp.cantidad * dp.precio_unitario)) DESC
        ->  Finalize GroupAggregate  Group Key: c.nombre
              ->  Gather Merge  (Workers Planned: 2, Workers Launched: 2)
                    ->  Sort  Sort Key: c.nombre
                          ->  Partial HashAggregate  Group Key: c.nombre
                                ->  Hash Join  Hash Cond: (pr.id_categoria = c.id_categoria)
                                      ->  Hash Join  Hash Cond: (dp.id_producto = pr.id_producto)
                                            ->  Parallel Hash Join  Hash Cond: (dp.id_pedido = ped.id_pedido)
                                                  ->  Parallel Seq Scan on detalle_pedido dp  (rows=173092 loops=3)
                                                  ->  Parallel Hash
                                                        ->  Parallel Seq Scan on pedido ped  (rows=10000)
                                                              Filter: (fecha >= CURRENT_DATE) AND (fecha < CURRENT_DATE + 1)
                                                              Rows Removed by Filter: 200005
                                            ->  Hash  ->  Seq Scan on producto pr  (rows=50011 loops=3)
                                      ->  Hash  ->  Seq Scan on categoria c  (rows=5)
Execution Time: 68.483 ms
```

## Parte 2 b — Patrón de desnormalización elegido

**Elección: tabla resumen `resumen_ventas_categoria_dia(id_categoria, fecha, total_vendido)` mantenida por un trigger sobre `detalle_pedido`.** La medición del punto 2a muestra una mediana de 71,0 ms con tres recorridos secuenciales (`detalle_pedido`, `pedido` y `producto`) que leen cientos de miles de filas para devolver 5, y ese trabajo crece con el histórico aunque lo vendido hoy sea poco; para un panel que consulta "muchas veces por minuto" es un costo repetido sin necesidad. El dato redundante se mantiene sincronizado con un único mecanismo, un trigger `AFTER INSERT/UPDATE/DELETE` sobre `detalle_pedido` que suma o resta `cantidad * precio_unitario` en la fila de su categoría y día (el día se deriva siempre de `pedido.fecha` con la zona `America/Argentina/Mendoza`, nunca de `CURRENT_DATE`), y un script de auditoría que recalcula desde las tablas fuente con `INNER JOIN` y compara con `EXCEPT` en ambos sentidos, cuyo resultado debe ser vacío. Es reversible sin pérdida: bastan `DROP TRIGGER`, `DROP FUNCTION` y `DROP TABLE`, porque la fuente de verdad (`detalle_pedido`, con su `precio_unitario` histórico congelado) no se modifica y el resumen siempre puede reconstruirse. Se prefiere el trigger a la vista materializada porque el panel requiere tiempo real: la vista queda desactualizada entre refrescos, mientras que el trigger da consistencia inmediata a cambio de un costo en cada escritura, que se mide en la Parte 2 c–e. La implementación final agrega a lo descrito acá la columna `cantidad_lineas` y un segundo trigger `BEFORE DELETE` sobre `pedido`; el detalle está en 2c.

**Respuestas a las 5 preguntas del profesor** (los puntos marcados como *supuesto* hay que confirmarlos con el dominio):

1. *Frecuencia de la consulta:* "muchas veces por minuto" (consigna).
2. *Escrituras por minuto en `detalle_pedido`:* *supuesto*: muy inferiores a las lecturas, ya que un panel consulta con más frecuencia de la que se registran pedidos. Se medirá el costo de escritura con 500 INSERT antes y después.
3. *¿Tolera desfase?:* no; el panel exige tiempo real, por eso se descarta la vista materializada.
4. *Cantidad de categorías y cambios del top:* la base tiene 5 categorías (4 activas), por lo que el top 5 equivale a todas y el orden puede cambiar con cada venta; la tabla resumen es chica (a lo sumo 5 filas por día).
5. *Crecimiento del volumen:* el histórico crece con el tiempo (200.005 pedidos en dos años), y con él el costo de la consulta original, mientras que la lectura del resumen depende solo de la cantidad de categorías.

**Zona horaria:** el "día" de negocio se define con la zona horaria de Argentina, `America/Argentina/Mendoza`, escrita de forma explícita en la medición, en el trigger, en la consulta nueva y en la auditoría.

**Limitaciones declaradas (fuera de alcance del trigger):** el cambio posterior de `pedido.fecha` o de `producto.id_categoria` sobre líneas ya registradas no se propaga al resumen; la auditoría lo detectaría como diferencia. La carga de pedidos de hoy se hizo con `INSERT` directo, por lo que el stock de los productos no se descontó; no afecta a esta consulta.

## Parte 2 c–e — Implementación, antes/después y auditoría

Script: `food-store/tp_desnormalizacion_top_categorias.sql`, ejecutado sobre `bd2_tp4u4` primero con `ROLLBACK` y después con `COMMIT`. Las salidas están en `food-store/tp_desnormalizacion_salida_rollback.txt` y `food-store/tp_desnormalizacion_salida_commit.txt`. En el repositorio el script termina en `ROLLBACK`, para que quien lo corra por primera vez no aplique cambios sin querer: para aplicarlo hay que cambiar ese `ROLLBACK` final por `COMMIT`. Lo mismo vale para `tp_desnormalizacion_reversion.sql`. Specs: `spec_top_categorias_desnormalizacion.md` (spec 5) y `spec_top_categorias_auditoria.md` (spec 6).

### c) Implementación del patrón

**Tabla resumen.** `resumen_ventas_categoria_dia(fecha, id_categoria, total_vendido, cantidad_lineas)`, con PK `(fecha, id_categoria)` y FK a `categoria`. Respecto de lo descrito en 2b se agregaron dos cosas que aparecieron al revisar la spec:

- `cantidad_lineas` cuenta cuántas líneas respaldan cada fila. Cuando una categoría se queda sin líneas en un día, la fila se borra. No alcanza con mirar si el total llegó a 0, porque `precio_unitario` admite 0 (`CHECK (precio_unitario >= 0)`) y puede haber ventas reales que sumen 0.
- La PK empieza por `fecha` porque la consulta del panel filtra por un día. Con eso no hace falta otro índice. No se indexó `total_vendido`: cambia en cada venta y el índice solo ahorraría ordenar 5 filas.

**Sincronización: un único dueño.** La única función que escribe en el resumen es `fn_resumen_ventas_aplicar_linea`, que recibe una línea y un signo (+1 suma, −1 resta) y deriva el día de `pedido.fecha` con `AT TIME ZONE 'America/Argentina/Mendoza'`. La llaman dos triggers:

- `trg_resumen_ventas_detalle`, `AFTER INSERT OR UPDATE OR DELETE` sobre `detalle_pedido`. En un `UPDATE` resta la línea vieja y suma la nueva, porque la línea puede haber cambiado de producto (otra categoría) o de pedido (otro día).
- `trg_resumen_ventas_pedido_borrado`, `BEFORE DELETE` sobre `pedido`. Hace falta por el `ON DELETE CASCADE` de `detalle_pedido`: cuando se borra un pedido, el trigger de las líneas se dispara pero ya no encuentra el pedido y no sabe de qué día restar. Lo comprobamos en una base aparte antes de escribir la spec. Por eso las líneas se restan antes de que el pedido desaparezca, y la función ignora las líneas cuyo pedido ya no existe para no restarlas dos veces.

Los dos triggers son puntos de entrada a la misma función, así que la regla del único dueño se mantiene: nadie más escribe el resumen.

**Carga inicial.** Cubre todos los días, no solo hoy: 3.665 filas (733 días × 5 categorías). Va en la misma transacción que los triggers, y los triggers se crean primero: `CREATE TRIGGER` bloquea las escrituras sobre la tabla hasta el final de la transacción, así que ninguna venta queda entre la carga y el momento en que el trigger empieza a funcionar.

**Fuera de alcance.** Cambiar `pedido.fecha` o `producto.id_categoria` de líneas ya registradas no se propaga al resumen. No se cubrió porque cambiar la categoría de un producto movería todas sus ventas históricas, y esa es una decisión de negocio que no forma parte del TP. La auditoría lo detecta (prueba 3 del punto e).

### d) Consulta sobre la estructura desnormalizada y comparación

```sql
SELECT c.nombre AS categoria, r.total_vendido
FROM resumen_ventas_categoria_dia r
JOIN categoria c ON c.id_categoria = r.id_categoria
WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY r.total_vendido DESC LIMIT 5;
```

Devuelve lo mismo que la consulta original: el script compara las dos con `EXCEPT` en ambos sentidos y da 0 filas.

**Medición.** El antes y el después se midieron el mismo día (21/10/2026) y sobre la misma base, con el mismo formato que en 2a: seis corridas de `EXPLAIN (ANALYZE, BUFFERS)`, la primera descartada. Por eso el "antes" no es el 71,044 ms de 2a: esta base es la de Elías más los pedidos cargados hoy, con 220.005 pedidos y 539.286 detalles. Scripts: `medicion_top_categorias_antes.sql` y `medicion_top_categorias_despues.sql`; salidas en `medicion_antes_salida_bruno.txt` y `medicion_despues_salida_bruno.txt`.

| Corrida | Antes (ms) | Después (ms) |
|---|---|---|
| 1 (warm-up, descartada) | 76,892 | 0,112 |
| 2 | 77,002 | 0,044 |
| 3 | 78,077 | 0,037 |
| 4 | 146,603 | 0,034 |
| 5 | 141,057 | 0,033 |
| 6 | 77,422 | 0,038 |
| **Mediana (corridas 2–6)** | **78,077** | **0,037** |

Las corridas 4 y 5 del "antes" tardaron casi el doble con el mismo plan; lo atribuimos a carga de la máquina en ese momento, y la mediana lo absorbe.

| | Antes | Después |
|---|---|---|
| Tiempo de ejecución (mediana) | 78,077 ms | 0,037 ms |
| Nodo dominante | `Parallel Seq Scan on detalle_pedido`: recorre 539.286 líneas para quedarse con las ~20.000 de hoy | `Bitmap Index Scan` sobre `resumen_ventas_categoria_dia_pkey`: trae solo las 5 filas de hoy |
| Buffers leídos | 7.770 (6.672 en memoria + 1.098 de disco) | 8 |

La consulta pasa a ser unas 2.100 veces más rápida y, sobre todo, deja de depender del tamaño del histórico: lee 5 filas por más pedidos que se acumulen.

Plan después (corrida 6):

```text
Limit (actual time=0.025..0.026 rows=5 loops=1)
  Buffers: shared hit=8
  ->  Sort  Sort Key: r.total_vendido DESC
        ->  Hash Join  Hash Cond: (r.id_categoria = c.id_categoria)
              ->  Bitmap Heap Scan on resumen_ventas_categoria_dia r (rows=5)
                    ->  Bitmap Index Scan on resumen_ventas_categoria_dia_pkey
                          Index Cond: (fecha = ((now() AT TIME ZONE 'America/Argentina/Mendoza'))::date)
              ->  Hash  ->  Seq Scan on categoria c (rows=5)
Execution Time: 0.038 ms
```

**Costo de escritura.** La mejora en la lectura se paga en cada venta. Se midieron 500 `INSERT` individuales en `detalle_pedido`, con el trigger apagado y encendido, cinco rondas de cada caso dentro de `BEGIN … ROLLBACK` (`medicion_escritura_top_categorias.sql`, salida en `medicion_escritura_salida_bruno.txt`):

| 500 INSERT (mediana de 5) | Sin trigger | Con trigger | Diferencia |
|---|---|---|---|
| Tiempo | 22,653 ms | 46,591 ms | +106 % (0,048 ms más por línea) |
| WAL generado | 182.576 bytes | 254.056 bytes | +39 % |

Cada venta cuesta el doble, pero en valores absolutos es menos de una décima de milisegundo por línea. Cada consulta del panel ahorra unos 78 ms, así que una sola consulta compensa el costo extra de unas 1.600 líneas vendidas. Con un panel que consulta muchas veces por minuto, el balance es claramente favorable. El costo que no se ve en esta medición es la concurrencia: todas las ventas de un día actualizan las mismas 5 filas, así que dos ventas simultáneas de la misma categoría se esperan una a la otra hasta que la primera confirma.

### e) Auditoría de desincronización

La auditoría recalcula el resumen desde las tablas fuente, con `INNER JOIN` y para todos los días, y lo compara con lo guardado mediante `EXCEPT` en ambos sentidos. Compara también `cantidad_lineas`. Una columna `lado` indica de qué lado sobra cada fila, así una desincronización aparece como dos filas, una con el valor del resumen y otra con el de la fuente.

**Sobre la base ya migrada: 0 filas.** Se corrió aparte, después del `COMMIT`, con `food-store/auditoria_top_categorias.sql` (salida en `food-store/auditoria_salida_bruno.txt`): 3.665 filas del resumen, 733 días, y ninguna diferencia con la fuente.

Para mostrar que la auditoría efectivamente detecta errores (una auditoría que siempre da 0 no prueba nada), el script incluye pruebas que se deshacen con `ROLLBACK TO SAVEPOINT`:

| Prueba | Qué se hace | Resultado de la auditoría |
|---|---|---|
| Mecanismo funcionando | Insertar una línea, cambiar una cantidad, mover una línea a un producto de otra categoría, borrar una línea y borrar un pedido entero | 0 filas |
| 1. Mecanismo apagado | Se apaga solo `trg_resumen_ventas_detalle` y se inserta una venta | 2 filas |
| 2. Escritura a mano | `UPDATE` directo sobre el resumen (rompe la regla del único dueño) | 2 filas |
| 3. Caso fuera de alcance | Cambiar la categoría de un producto con ventas | 52 filas: en los 13 días en que se vendió ese producto, cambian las dos categorías involucradas |

Si la auditoría da filas, no se corrige el valor a mano: se revisa el mecanismo.

**Reversión.** `food-store/tp_desnormalizacion_reversion.sql` borra los dos triggers, las tres funciones y la tabla resumen. Las tablas fuente no se tocan, porque son la fuente de verdad y el resumen siempre se puede reconstruir desde ellas. El script principal incluye una prueba: después de revertir dentro de un `SAVEPOINT`, la tabla resumen ya no existe y `pedido` y `detalle_pedido` tienen la misma cantidad de filas que antes.

**Sobre cómo se escribió el SQL.** Por la regla del grupo, el SQL lo propone OpenCode. En esta parte OpenCode no devolvió propuesta (los modelos Gemini estaban saturados o cortaban con un error), así que el SQL lo escribió Claude Code siguiendo las specs 5 y 6, y lo revisamos y ejecutamos nosotros. Está declarado como apartamiento del flujo en `docs/duia/duia_tp_u4.md`.

## Uso de IA

*Pendiente. El registro completo está en `docs/duia/duia_tp_u4.md`.*
