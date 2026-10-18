# Spec: Top Categorías - Auditoría de desincronización

**Responsable**: Bruno  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-18 — Corrección 2: comentarios de auditoría alineados con la fuente

---

## 1. Objetivo

Detectar desincronización entre el dato redundante (tabla resumen o vista materializada) y su fuente de verdad (pedido, detalle_pedido, producto, categoria).

---

## 2. Consulta

### 2.1. Script de auditoría para Patrón 1 (tabla resumen con trigger)

```sql
-- Comparar: dato guardado vs dato recalculado
-- Debe devolver 0 filas si están sincronizados
-- Recalcula para TODOS los días de la fuente (pedido y detalle_pedido)
(
    SELECT r.id_categoria, r.fecha, r.total_vendido AS guardado
    FROM resumen_ventas_categoria_dia r
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
    SELECT r.id_categoria, r.fecha, r.total_vendido
    FROM resumen_ventas_categoria_dia r
);
```

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

---

## 5. Estado actual medido

No aplica (depende de spec 5).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Script de auditoría** que devuelva 0 filas cuando hay sincronización.

2. **Prueba de detección de fallas** (en `BEGIN; … ROLLBACK;`):
   - Deshabilitar el trigger (si existe).
   - Insertar un detalle de pedido que cambie las ventas.
   - Ejecutar la auditoría (debe devolver filas = detecta la diferencia).
   - Hacer ROLLBACK para no persistir el cambio.
   
   Esta prueba demuestra que el script de auditoría funciona.

3. **Documentación de la regla del profe**: "si hay diferencias, no se corrige el valor a mano, se audita el mecanismo". El script de auditoría se integra al archivo de spec 5.

### 6.2. Lo que NO se puede hacer sin justificación

- Modificar el script de auditoría para "corregir" automáticamente los valores.
- Omitir la prueba de detección de fallas.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- El script de auditoría devuelve 0 filas sobre la base migrada (datos sincronizados).
- La prueba de detección de fallas demuestra que el script detecta diferencias (devuelve filas cuando el trigger está deshabilitado).

### 7.2. Salida de descarte

Si la auditoría no detecta las diferencias en la prueba, se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

*Pendiente de medición.*  
*Fecha: —*  
*Estado: —*  
*Filas devueltas por auditoría (sincronizado): —*  
*Filas devueltas por auditoría (trigger deshabilitado): —*

---

## Dependencias

Esta spec depende de `spec_top_categorias_desnormalizacion.md` (spec 5). No se puede ejecutar hasta tener la estructura desnormalizada implementada.