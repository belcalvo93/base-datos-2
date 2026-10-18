# Spec: Top Categorías - Desnormalización

**Responsable**: Bruno  
**Fecha de creación**: 2026-10-18  
**Última revisión**: —

---

## 1. Objetivo

Implementar el patrón elegido (trigger o vista materializada) con un único dueño del dato, para acelerar la consulta del punto 5.1.

---

## 2. Consulta

### 2.1. Estructura propuesta (Patrón 1: tabla resumen con trigger)

```sql
-- Tabla resumen por categoría y día
CREATE TABLE IF NOT EXISTS resumen_ventas_categoria_dia (
    id_categoria BIGINT NOT NULL,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    total_vendido NUMERIC(12,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (id_categoria, fecha)
);

-- Índice para la consulta optimizada
CREATE INDEX IF NOT EXISTS idx_resumen_ventas_fecha 
    ON resumen_ventas_categoria_dia (fecha DESC, total_vendido DESC);
```

### 2.2. Estructura propuesta (Patrón 2: vista materializada)

```sql
-- Vista materializada
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_resumen_ventas_categoria_dia AS
SELECT c.id_categoria, c.nombre AS categoria, 
       CURRENT_DATE AS fecha,
       COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0) AS total_vendido
FROM categoria c
LEFT JOIN producto pr ON pr.id_categoria = c.id_categoria AND pr.activo = TRUE
LEFT JOIN detalle_pedido dp ON dp.id_producto = pr.id_producto
LEFT JOIN pedido ped ON ped.id_pedido = dp.id_pedido 
    AND ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.id_categoria, c.nombre
ORDER BY total_vendido DESC
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_resumen_categoria_dia 
    ON mv_resumen_ventas_categoria_dia (id_categoria, fecha);
```

---

## 3. Frecuencia y carga

- **Frecuencia de lectura**: "muchas veces por minuto" (según spec 4).
- **Frecuencia de escritura**: depende del volumen de pedidos nuevos por minuto.
- **Patrón elegido**: se definirá en spec 4 según las mediciones.

---

## 4. Columnas relevantes

| Tabla resumen | Columnas |
|---------------|----------|
| resumen_ventas_categoria_dia | id_categoria (PK), fecha (PK), total_vendido |
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
   - Función trigger que ejecuta en cada INSERT/UPDATE/DELETE sobre `detalle_pedido`.
   - Debe actualizar `resumen_ventas_categoria_dia` sumando o restando `cantidad * precio_unitario`.
   - Considerar: ¿qué pasa si cambia `pedido.fecha`? ¿Qué pasa si cambia `producto.id_categoria`? Documentar como "fuera de alcance" si no se cubre.
   - Zona horaria: usar `CURRENT_DATE` sin timezone (asume server timezone).
   
   **Si es Patrón 2 (vista materializada)**:
   - Función de refresco con `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

3. **Carga inicial**: populal la estructura desnormalizada con los datos existentes de hoy.

4. **Reversión**: script que borre trigger, función y tabla (o vista materializada) sin afectar los datos fuente.

5. **Nueva consulta** (punto 5.2d):
   ```sql
   -- Para Patrón 1
   SELECT c.nombre AS categoria, r.total_vendido
   FROM resumen_ventas_categoria_dia r
   JOIN categoria c ON c.id_categoria = r.id_categoria
   WHERE r.fecha = CURRENT_DATE
   ORDER BY r.total_vendido DESC LIMIT 5;
   
   -- Para Patrón 2
   SELECT categoria, total_vendido
   FROM mv_resumen_ventas_categoria_dia
   WHERE fecha = CURRENT_DATE
   ORDER BY total_vendido DESC LIMIT 5;
   ```

6. **Medición después**: ejecutar la nueva consulta con `EXPLAIN (ANALYZE, BUFFERS)` y comparar con la basal.

7. **Costo de escritura**: ejecutar 500 INSERT en `detalle_pedido` antes y después (como en `medicion_escritura.sql` del TP5), midiendo el tiempo total.

8. **Script completo** en `food-store/tp_desnormalizacion_top_categorias.sql`.

### 6.2. Lo que NO se puede hacer sin justificación

- Modificar la estructura de `pedido`, `detalle_pedido`, `producto` o `categoria`.
- Eliminar la restricción UNIQUE en detalle_pedido.
- Usar más de un trigger/único mecanismo para mantener la redundancia (regla del steering).
- Proponer vistas materializadas sin índice único (necesario para REFRESH CONCURRENTLY).

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- La nueva consulta devuelve el mismo top 5 que la consulta original.
- El tiempo de lectura mejora de forma medible respecto a la basal (spec 4).
- El costo de escritura (500 INSERT) se mide antes y después, y se documenta.
- El script de reversión funciona (puede eliminarse la estructura sin perder datos fuente).

### 7.2. Salida de descarte

Si el "después" NO mejora de forma medible (dentro del margen de error), se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

*Pendiente de medición.*  
*Fecha: —*  
*Estado: —*  
*Tiempo antes (mediana): — ms*  
*Tiempo después (mediana): — ms*  
*Mejora: — %*  
*Costo de escritura adicional: — ms*

---

## Dependencias

- Esta spec depende de `spec_top_categorias_antes.md` (spec 4). No se puede ejecutar hasta tener la medición basal.
- Esta spec habilita `spec_top_categorias_auditoria.md` (spec 6).