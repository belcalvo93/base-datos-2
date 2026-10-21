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

**Datos de la medición.** Base `bd2_tp4u4` (copia de `bd2_tp3`) con 200.005 + 10.000 pedidos, 499.263 + 20.012 detalles y 50.011 productos; los 10.000 pedidos y ~20.000 detalles de hoy se cargaron con `food-store/carga_pedidos_hoy.sql`, seguido de `VACUUM ANALYZE`. La base tiene solo 5 categorías, por lo que el top 5 las devuelve todas.

**Consulta medida.** La del punto 5.1, adaptada al esquema real: el monto es `cantidad * precio_unitario` (el subtotal no se almacena), el filtro de hoy es un rango sobre `pedido.fecha` (es `TIMESTAMPTZ`, no `DATE`) y no hay columnas `eliminado`.

```sql
SET timezone = 'America/Argentina/Mendoza'; -- zona horaria a confirmar con el profesor
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

## Parte 2 b — Patrón de desnormalización elegido

**Elección: tabla resumen `resumen_ventas_categoria_dia(id_categoria, fecha, total_vendido)` mantenida por un trigger sobre `detalle_pedido`.** La medición del punto 2a muestra una mediana de 71,0 ms con tres recorridos secuenciales (`detalle_pedido`, `pedido` y `producto`) que leen cientos de miles de filas para devolver 5, y ese trabajo crece con el histórico aunque lo vendido hoy sea poco; para un panel que consulta "muchas veces por minuto" es un costo repetido sin necesidad. El dato redundante se mantiene sincronizado con un único mecanismo, un trigger `AFTER INSERT/UPDATE/DELETE` sobre `detalle_pedido` que suma o resta `cantidad * precio_unitario` en la fila de su categoría y día (el día se deriva siempre de `pedido.fecha` con la zona `America/Argentina/Mendoza` (a confirmar con el profesor), nunca de `CURRENT_DATE`), y un script de auditoría que recalcula desde las tablas fuente con `INNER JOIN` y compara con `EXCEPT` en ambos sentidos, cuyo resultado debe ser vacío. Es reversible sin pérdida: bastan `DROP TRIGGER`, `DROP FUNCTION` y `DROP TABLE`, porque la fuente de verdad (`detalle_pedido`, con su `precio_unitario` histórico congelado) no se modifica y el resumen siempre puede reconstruirse. Se prefiere el trigger a la vista materializada porque el panel requiere tiempo real: la vista queda desactualizada entre refrescos, mientras que el trigger da consistencia inmediata a cambio de un costo en cada escritura, que se mide en la Parte 2 c–e.

**Respuestas a las 5 preguntas del profesor** (los puntos marcados como *supuesto* hay que confirmarlos con el dominio):

1. *Frecuencia de la consulta:* "muchas veces por minuto" (consigna).
2. *Escrituras por minuto en `detalle_pedido`:* *supuesto*: muy inferiores a las lecturas, ya que un panel consulta con más frecuencia de la que se registran pedidos. Se medirá el costo de escritura con 500 INSERT antes y después.
3. *¿Tolera desfase?:* no; el panel exige tiempo real, por eso se descarta la vista materializada.
4. *Cantidad de categorías y cambios del top:* la base tiene 5 categorías (4 activas), por lo que el top 5 equivale a todas y el orden puede cambiar con cada venta; la tabla resumen es chica (a lo sumo 5 filas por día).
5. *Crecimiento del volumen:* el histórico crece con el tiempo (200.005 pedidos en dos años), y con él el costo de la consulta original, mientras que la lectura del resumen depende solo de la cantidad de categorías.

**Zona horaria (a confirmar con el profesor):** el "día" de negocio se define con `America/Argentina/Mendoza`, escrita de forma explícita en la medición, en el trigger, en la consulta nueva y en la auditoría; si el profesor indica otra zona, se cambia en esos cuatro lugares.

**Limitaciones declaradas (fuera de alcance del trigger):** el cambio posterior de `pedido.fecha` o de `producto.id_categoria` sobre líneas ya registradas no se propaga al resumen; la auditoría lo detectaría como diferencia. La carga de pedidos de hoy se hizo con `INSERT` directo, por lo que el stock de los productos no se descontó; no afecta a esta consulta.

## Parte 2 c–e — Implementación, antes/después y auditoría

*Pendiente: Bruno.*

## Uso de IA

*Pendiente. El registro completo está en `docs/duia/duia_tp_u4.md`.*
