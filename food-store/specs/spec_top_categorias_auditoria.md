# Spec: Top Categorías - Auditoría de desincronización

**Responsable**: Bruno  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-19 — Corrección 3: compara también `cantidad_lineas`, columna `lado`, auditoría del Patrón 2 solo después del refresco, tres pruebas de detección

---

## 1. Objetivo

Detectar desincronización entre el dato redundante (tabla resumen o vista materializada) y su fuente de verdad (pedido, detalle_pedido, producto, categoria).

---

## 2. Consulta

### 2.1. Script de auditoría para Patrón 1 (tabla resumen con trigger)

```sql
-- Compara el dato guardado con el recalculado desde la fuente, para TODOS los días.
-- Debe devolver 0 filas. La columna lado dice de qué lado sobra cada fila.
WITH fuente AS (
    SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha,
           c.id_categoria,
           SUM(dp.cantidad * dp.precio_unitario) AS total_vendido,
           COUNT(*)::int AS cantidad_lineas
    FROM categoria c
    INNER JOIN producto pr ON pr.id_categoria = c.id_categoria
    INNER JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
    INNER JOIN pedido ped ON ped.id_pedido = dp.id_pedido
    GROUP BY 1, 2
),
guardado AS (
    SELECT fecha, id_categoria, total_vendido, cantidad_lineas
    FROM resumen_ventas_categoria_dia
)
(SELECT 'solo en el resumen' AS lado, * FROM (SELECT * FROM guardado EXCEPT SELECT * FROM fuente) a)
UNION ALL
(SELECT 'solo en la fuente' AS lado, * FROM (SELECT * FROM fuente EXCEPT SELECT * FROM guardado) b)
ORDER BY fecha, id_categoria, lado;
```

Cambios respecto de la versión anterior:

- **Se compara también `cantidad_lineas`.** Ese contador decide cuándo se borra una fila del resumen (spec 5, 2.1), así que también tiene que coincidir con la fuente.
- **El recálculo se escribe una sola vez (`WITH fuente`).** Antes estaba copiado en los dos sentidos del `EXCEPT`, y si alguien corregía uno y se olvidaba del otro, la auditoría comparaba cosas distintas.
- **Columna `lado`.** Cuando la auditoría encuentra una diferencia, una desincronización aparece como dos filas, una de cada lado, y se ve enseguida qué valor tiene el resumen y cuál la fuente.
- **Sigue siendo `INNER JOIN` y para todos los días**, como en la versión anterior. Con `LEFT JOIN` aparecerían filas con NULL que esconden diferencias.

### 2.2. Script de auditoría para Patrón 2 (vista materializada)

```sql
-- Comparar: dato en la MV vs dato recalculado
-- Recalcula para TODOS los días de la fuente (pedido y detalle_pedido)
(
    SELECT id_categoria, fecha, total_vendido AS guardado
    FROM mv_resumen_ventas_categoria_dia
    EXCEPT
    SELECT c.id_categoria, 
           (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha, 
           SUM(dp.cantidad * dp.precio_unitario) AS recalculado
    FROM categoria c
    INNER JOIN producto pr ON pr.id_categoria = c.id_categoria
    INNER JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
    INNER JOIN pedido ped ON ped.id_pedido = dp.id_pedido
    GROUP BY c.id_categoria, (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date
)
UNION ALL
(
    SELECT c.id_categoria, 
           (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date AS fecha, 
           SUM(dp.cantidad * dp.precio_unitario) AS recalculado
    FROM categoria c
    INNER JOIN producto pr ON pr.id_categoria = c.id_categoria
    INNER JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
    INNER JOIN pedido ped ON ped.id_pedido = dp.id_pedido
    GROUP BY c.id_categoria, (ped.fecha AT TIME ZONE 'America/Argentina/Mendoza')::date
    EXCEPT
    SELECT id_categoria, fecha, total_vendido
    FROM mv_resumen_ventas_categoria_dia
);
```

**Esta auditoría se corre inmediatamente después de `REFRESH MATERIALIZED VIEW CONCURRENTLY`.** La vista materializada está desactualizada por diseño entre dos refrescos. Si se audita en ese intervalo, las diferencias son el desfase aceptado y no un error del mecanismo.

---

## 3. Frecuencia y carga

- **Frecuencia**: se ejecuta manualmente o como parte de un job de monitoreo.
- **Carga**: equivalente a recalcular la consulta original (mismos joins).

---

## 4. Columnas relevantes

| Rol | Tabla/Estructura |
|-----|------------------|
| Fuente de verdad | pedido, detalle_pedido, producto, categoria |
| Dato redundante | resumen_ventas_categoria_dia o mv_resumen_ventas_categoria_dia |
| Columnas comparadas (Patrón 1) | fecha, id_categoria, total_vendido, cantidad_lineas |
| Columnas comparadas (Patrón 2) | id_categoria, fecha, total_vendido |

---

## 5. Estado actual medido

No aplica (depende de spec 5).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Script de auditoría** que devuelva 0 filas cuando hay sincronización.

2. **Pruebas de detección de fallas**. Cada una va en su propio `BEGIN; … ROLLBACK;`, y en todas la auditoría tiene que devolver filas:
   - **Mecanismo apagado.** `ALTER TABLE detalle_pedido DISABLE TRIGGER <nombre del trigger de sincronización>` (por nombre, no `ALL`: `ALL` apaga también los triggers internos de las FK), después se inserta una línea en un pedido y se corre la auditoría. La línea tiene que ser de un producto activo y con stock, por los triggers del TP2.
   - **Alguien escribe el resumen a mano.** `UPDATE resumen_ventas_categoria_dia SET total_vendido = total_vendido + 1 WHERE …` sobre una fila. Simula que se rompe la regla del único dueño.
   - **Caso fuera de alcance.** `UPDATE producto SET id_categoria = <otra> WHERE id_producto = <uno con ventas>`. Muestra que lo que el trigger no cubre (spec 5) no pasa inadvertido: lo detecta la auditoría.

   En el Patrón 2, la prueba equivalente es insertar una línea sin refrescar y auditar.

   Estas pruebas demuestran que el script de auditoría funciona.

3. **Documentación de la regla del profe**: "si hay diferencias, no se corrige el valor a mano, se audita el mecanismo". La auditoría y sus pruebas van en `food-store/tp_desnormalizacion_top_categorias.sql`, junto con la estructura de la spec 5.

### 6.2. Lo que NO se puede hacer sin justificación

- Modificar el script de auditoría para "corregir" automáticamente los valores.
- Omitir alguna de las pruebas de detección de fallas.
- Usar `LEFT JOIN` en el recálculo, auditar solo el día de hoy o comparar en un solo sentido.
- Comparar valores redondeados o con tolerancia: los dos lados son `NUMERIC` exactos y tienen que coincidir.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- El script de auditoría devuelve 0 filas sobre la base migrada (datos sincronizados).
- Las tres pruebas de detección devuelven filas, y cada una muestra el lado que corresponde.

### 7.2. Salida de descarte

Si la auditoría no detecta las diferencias en la prueba, se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

- **Fecha:** 21/10/2026, sobre `bd2_tp4u4`.
- **Estado:** aceptado. La auditoría y sus pruebas están en `food-store/tp_desnormalizacion_top_categorias.sql`.
- **Filas devueltas por auditoría (sincronizado):** 0, también después de insertar, modificar, mover y borrar líneas y de borrar un pedido entero.
- **Filas devueltas por auditoría (trigger deshabilitado):** 2.
- **Filas devueltas por auditoría (escritura a mano en el resumen):** 2.
- **Filas devueltas por auditoría (cambio de categoría de un producto):** 52 (13 días × 2 categorías × 2 lados).
- **Salida:** `food-store/tp_desnormalizacion_salida_rollback.txt`.

---

## Dependencias

Esta spec depende de `spec_top_categorias_desnormalizacion.md` (spec 5). No se puede ejecutar hasta tener la estructura desnormalizada implementada.