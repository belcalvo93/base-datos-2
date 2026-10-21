# Spec: Top Categorías - Desnormalización

**Responsable**: Bruno  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-20 — Patrón elegido actualizado en la sección 3. Antes (2026-10-19), corrección 3: PK `(fecha, id_categoria)` sin índice extra, columna `cantidad_lineas`, UPDATE como resta + suma, borrado en cascada de `pedido`, casos fuera de alcance

---

## 1. Objetivo

Implementar el patrón elegido (trigger o vista materializada) con un único dueño del dato, para acelerar la consulta del punto 5.1.

---

## 2. Consulta

### 2.1. Estructura propuesta (Patrón 1: tabla resumen con trigger)

```sql
-- Tabla resumen por día y categoría
CREATE TABLE IF NOT EXISTS resumen_ventas_categoria_dia (
    fecha           DATE          NOT NULL,
    id_categoria    BIGINT        NOT NULL REFERENCES categoria (id_categoria) ON DELETE RESTRICT,
    total_vendido   NUMERIC(12,2) NOT NULL,
    cantidad_lineas INTEGER       NOT NULL CHECK (cantidad_lineas > 0),
    PRIMARY KEY (fecha, id_categoria)
);
```

Decisiones de esta estructura:

- **La PK empieza por `fecha`.** La consulta nueva filtra por un día, y con la PK en ese orden el filtro se resuelve con el índice de la PK. No hace falta otro índice: por día hay tantas filas como categorías (hoy 5), y ordenarlas por `total_vendido` no cuesta nada.
- **No hay índice sobre `total_vendido`.** El trigger modifica esa columna en cada venta. Si estuviera indexada, cada actualización tendría que escribir también en el índice y PostgreSQL no podría hacer actualizaciones HOT. Sería un costo en cada venta para ahorrar un ordenamiento de 5 filas.
- **`cantidad_lineas` decide cuándo se borra una fila.** Cuando una categoría se queda sin líneas en un día, la fila tiene que desaparecer, porque el recálculo de la auditoría no la genera. No alcanza con mirar si `total_vendido` llegó a 0: `precio_unitario` admite 0 (`CHECK (precio_unitario >= 0)`), así que puede haber un día con ventas reales que suman 0. La fila se borra cuando `cantidad_lineas` llega a 0.
- **Sin `DEFAULT 0`.** Una fila solo existe si tiene al menos una línea que la respalde.

### 2.2. Estructura propuesta (Patrón 2: vista materializada)

```sql
-- Vista materializada
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_resumen_ventas_categoria_dia AS
SELECT c.id_categoria, c.nombre AS categoria, 
       (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha,
       SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM categoria c
INNER JOIN producto pr ON pr.id_categoria = c.id_categoria
INNER JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
INNER JOIN pedido ped ON ped.id_pedido = dp.id_pedido
GROUP BY c.id_categoria, c.nombre, (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_resumen_categoria_dia 
    ON mv_resumen_ventas_categoria_dia (id_categoria, fecha);
```

---

## 3. Frecuencia y carga

- **Frecuencia de lectura**: "muchas veces por minuto" (según spec 4).
- **Frecuencia de escritura**: depende del volumen de pedidos nuevos por minuto.
- **Patrón elegido**: Patrón 1, tabla resumen mantenida por trigger. Lo eligió Elías con la medición basal de la spec 4 (mediana 71,0 ms); la justificación está en el punto 2b del informe.
- **Costo del Patrón 1 en concurrencia**: todas las ventas de un día actualizan las mismas filas, una por categoría. Dos transacciones que venden en la misma categoría se esperan una a la otra hasta que la primera confirma. Con el volumen del TP no se nota, pero es el precio del patrón y se menciona en la justificación.
- **Costo del Patrón 2**: `REFRESH MATERIALIZED VIEW CONCURRENTLY` recalcula todos los días, no solo el de hoy. Si el panel necesita el dato "en tiempo real", habría que refrescar muchas veces por minuto, y cada refresco cuesta más que la consulta original. Este dato sirve para la justificación de Elías (punto 5.2b).

---

## 4. Columnas relevantes

| Tabla resumen | Columnas |
|---------------|----------|
| resumen_ventas_categoria_dia | fecha (PK), id_categoria (PK, FK), total_vendido, cantidad_lineas |
| mv_resumen_ventas_categoria_dia | id_categoria, categoria, fecha, total_vendido |

---

## 5. Estado actual medido

No aplica (depende de spec 4).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Estructura desnormalizada** según el patrón elegido en spec 4.

2. **Mecanismo de sincronización**:
   
   **Si es Patrón 1 (trigger)**:
   - Una sola función, la única que escribe en `resumen_ventas_categoria_dia`, aplica el aporte de una línea con signo `+1` o `-1`. Para sumar hace `INSERT … ON CONFLICT (fecha, id_categoria) DO UPDATE`, que suma `cantidad * precio_unitario` a `total_vendido` y 1 a `cantidad_lineas`. Para restar, si es la última línea de ese día y categoría (`cantidad_lineas = 1`), borra la fila; si no, hace un `UPDATE` que resta. No se puede actualizar a 0 y borrar después, porque la tabla tiene `CHECK (cantidad_lineas > 0)` y el paso intermedio lo violaría.
   - Trigger `AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido FOR EACH ROW`:
     - INSERT: suma el aporte de `NEW`.
     - DELETE: resta el aporte de `OLD`.
     - UPDATE: resta el aporte de `OLD` y suma el de `NEW`. No alcanza con sumar la diferencia, porque si la línea cambia de `id_producto` o de `id_pedido` puede pasar a otra categoría o a otro día.
   - **Borrado de un pedido.** `detalle_pedido.id_pedido` es `ON DELETE CASCADE`. Cuando se borra un pedido, el trigger de `detalle_pedido` se dispara por cada línea, pero **ya no encuentra el pedido**: la consulta a `pedido` devuelve NULL y no hay forma de saber de qué día restar. Se comprobó en una base descartable (PostgreSQL 17) con un trigger `BEFORE` y otro `AFTER` en `detalle_pedido`, y los dos ven NULL. Se pide:
     - Trigger `BEFORE DELETE ON pedido FOR EACH ROW`, que llama a la misma función con `-1` por cada línea del pedido. En ese momento las líneas y el pedido todavía existen.
     - En la función: si no encuentra el pedido, no hace nada, porque esa línea ya la restó el trigger de `pedido`. Así no se resta dos veces.
     - Esto no rompe la regla del único dueño: los dos triggers son puntos de entrada a la misma función, y es la única que escribe en el resumen.
   - El día de cada línea se deriva siempre de `pedido.fecha`, nunca de `CURRENT_DATE`: `(fecha AT TIME ZONE 'America/Argentina/Mendoza')::date`. El trigger, la consulta nueva y la auditoría usan la misma expresión.
   - **Fuera de alcance** (se documenta en el informe y la auditoría lo detecta; ver spec 6):
     - Cambiar `pedido.fecha` de un pedido ya cargado.
     - Cambiar `producto.id_categoria`. Movería todas las ventas históricas del producto a otra categoría, y la decisión de negocio sobre si eso corresponde no es parte de este TP.
   
   **Si es Patrón 2 (vista materializada)**:
   - Función de refresco con `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

3. **Carga inicial**: poblar la estructura desnormalizada con todos los días existentes en `pedido` y `detalle_pedido` (carga completa, una sola vez, para que el resumen coincida con lo recalculado por la auditoría). En el Patrón 1 se calcula también `cantidad_lineas` (`COUNT(*)` de líneas por día y categoría). La carga y la creación de los triggers van en la misma transacción, para que ninguna venta quede entre la carga y el momento en que el trigger empieza a funcionar.

4. **Reversión**: script que borre los dos triggers, la función y la tabla (o la vista materializada) sin afectar los datos fuente. Para probarlo, se cuentan las filas de `pedido` y `detalle_pedido` antes y después de revertir y tienen que coincidir.

5. **Nueva consulta** (punto 5.2d):
   ```sql
   -- Para Patrón 1
   SELECT c.nombre AS categoria, r.total_vendido
   FROM resumen_ventas_categoria_dia r
   JOIN categoria c ON c.id_categoria = r.id_categoria
   WHERE r.fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
   ORDER BY r.total_vendido DESC LIMIT 5;
   
   -- Para Patrón 2
   SELECT categoria, total_vendido
   FROM mv_resumen_ventas_categoria_dia
   WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
   ORDER BY total_vendido DESC LIMIT 5;
   ```

6. **Medición después**: ejecutar la nueva consulta con `EXPLAIN (ANALYZE, BUFFERS)` y comparar con la basal.

7. **Costo de escritura**: ejecutar 500 INSERT en `detalle_pedido` antes y después (como en `medicion_escritura.sql` del TP5), midiendo el tiempo total.

8. **Script completo** en `food-store/tp_desnormalizacion_top_categorias.sql`.

### 6.2. Lo que NO se puede hacer sin justificación

- Modificar la estructura de `pedido`, `detalle_pedido`, `producto` o `categoria`.
- Eliminar la restricción UNIQUE en detalle_pedido.
- Que más de una función escriba en el resumen (regla del único dueño del steering). Los dos triggers del Patrón 1 se aceptan porque llaman a la misma función; está justificado en 6.1, punto 2.
- Proponer vistas materializadas sin índice único (necesario para REFRESH CONCURRENTLY).
- Agregar índices sobre `total_vendido` o sobre `(fecha, total_vendido)` sin medir antes y después que se necesitan (ver 2.1).
- Borrar una fila del resumen porque `total_vendido` llegó a 0. Se borra solo cuando `cantidad_lineas` llega a 0 (ver 2.1).
- Usar `CURRENT_DATE` o `now()` para decidir a qué día pertenece una línea. El día sale de `pedido.fecha`.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- La nueva consulta devuelve el mismo top 5 que la consulta original (comparado con `EXCEPT` en los dos sentidos, categoría y monto).
- En el Patrón 1, la auditoría de la spec 6 da 0 filas después de cada uno de estos casos, probados dentro de `BEGIN … ROLLBACK`: insertar líneas, cambiar la cantidad de una línea, mover una línea a otro producto de otra categoría, borrar una línea y borrar un pedido completo (cascada).
- El tiempo de lectura mejora de forma medible respecto a la basal (spec 4).
- El costo de escritura (500 INSERT) se mide antes y después, y se documenta.
- El script de reversión funciona (puede eliminarse la estructura sin perder datos fuente).

### 7.2. Salida de descarte

Si el "después" NO mejora de forma medible (dentro del margen de error), se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

- **Fecha:** 21/10/2026, sobre `bd2_tp4u4` (220.005 pedidos, 539.286 detalles). Antes y después medidos el mismo día.
- **Estado:** aceptado. Implementado en `food-store/tp_desnormalizacion_top_categorias.sql` y confirmado con `COMMIT`.
- **Tiempo antes (mediana de 5):** 78,077 ms. Nodo dominante: `Parallel Seq Scan on detalle_pedido`.
- **Tiempo después (mediana de 5):** 0,037 ms. Nodo dominante: `Bitmap Index Scan` sobre la PK del resumen.
- **Mejora:** unas 2.100 veces; de 7.770 buffers a 8.
- **Mismo top 5 que la consulta original:** sí, `EXCEPT` en los dos sentidos da 0 filas.
- **Costo de escritura (500 INSERT, mediana de 5):** 22,653 ms sin trigger y 46,591 ms con trigger (+23,9 ms, 0,048 ms por línea); WAL de 182.576 a 254.056 bytes (+39 %).
- **Reversión:** probada dentro de un `SAVEPOINT`; el resumen desaparece y `pedido` y `detalle_pedido` no cambian.
- **Salidas:** `medicion_antes_salida_bruno.txt`, `medicion_despues_salida_bruno.txt`, `medicion_escritura_salida_bruno.txt` y `tp_desnormalizacion_salida_rollback.txt`.

---

## Dependencias

- Esta spec depende de `spec_top_categorias_antes.md` (spec 4). No se puede ejecutar hasta tener la medición basal.
- Esta spec habilita `spec_top_categorias_auditoria.md` (spec 6).