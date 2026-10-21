# Spec: Top Categorías - Medición basal (antes de desnormalizar)

**Responsable**: Elías  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-18 — Corregido: tolerate -> tolera, nota de timezone

---

## 1. Objetivo

Obtener la evidencia medida que motiva (o no) la desnormalización de la consulta del punto 5.1 del TP U4.

---

## 2. Consulta

### 2.1. Consulta adaptada del punto 5.1

```sql
SELECT c.nombre AS categoria, SUM(dp.cantidad * dp.precio_unitario) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
WHERE ped.fecha >= CURRENT_DATE AND ped.fecha < CURRENT_DATE + 1
GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5;
```

### 2.2. Origen

- **Origen**: adaptación de la consigna TP U4 punto 5.1 al esquema existente.
- **Decisión tomada**: se usa `pedido.fecha` con rango (`>= CURRENT_DATE AND < CURRENT_DATE + 1`) en lugar de `= CURRENT_DATE` porque `fecha` es TIMESTAMPTZ.
- **Nota**: la consulta basal usa CURRENT_DATE de la sesión, así que se corre con `SET timezone = 'America/Argentina/Mendoza'` para que el día coincida con el de la desnormalización.

---

## 3. Frecuencia y carga

- **Frecuencia**: "muchas veces por minuto" según la consigna.
- **Relación lecturas/escrituras**: a confirmar con las 5 preguntas del profe:
  1. ¿Con qué frecuencia se ejecuta la consulta?
  2. ¿Cuántas escrituras (INSERT/UPDATE/DELETE en detalle_pedido) hay por minuto?
  3. ¿La consulta tolera desfase (consistencia eventual) o requiere tiempo real?
  4. ¿Cuántas categorías hay? ¿El top 5 cambia seguido?
  5. ¿El volumen de datos crece con el tiempo?

---

## 4. Columnas relevantes

| Rol | Tabla | Columna |
|-----|-------|---------|
| Filtro de fecha | pedido | fecha |
| Join | detalle_pedido | id_pedido, id_producto |
| Join | producto | id_producto, id_categoria |
| Join | categoria | id_categoria, nombre |
| Agregación | detalle_pedido | cantidad, precio_unitario |
| Orden | expresión calculada | total_vendido DESC |

---

## 5. Estado actual medido

Medido el 19/10/2026 con `EXPLAIN (ANALYZE, BUFFERS)`, 6 corridas (la primera descartada): mediana de 71,044 ms. Ver sección 8.

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Medición basal** (script `food-store/medicion_top_categorias_antes.sql`):
   - Ejecutar la consulta adaptada con `EXPLAIN (ANALYZE, BUFFERS)`.
   - Ejecutar al menos 5 corridas.
   - Reportar la mediana (descartando la primera carrera que incluye warm-up).
   - Registrar: tiempo total (ms), nodo dominante del plan (tipo de operación más costosa).

2. **Respuestas a las 5 preguntas** del profe (se completan con información del dominio).

3. **Elección justificada del patrón** (un párrafo):
   - **Patrón 1**: columna/tabla precalculada con trigger. Consistencia inmediata, costo en cada escritura.
   - **Patrón 2**: vista materializada con refresco concurrente. Consistencia eventual, costo en refresco.
   - La decisión depende del tiempo medido y la respuesta a "¿toleramos desfase?".

### 6.2. Lo que NO se puede hacer sin justificar

- Modificar la consulta adaptada (ya está fijada por la consigna).
- Sugerir eliminar `precio_unitario` de `detalle_pedido` (es dato histórico, R4).
- Proponer desnormalización sin medición basal.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- Se ejecutan al menos 5 corridas con EXPLAIN ANALYZE.
- Se reporta la mediana de tiempo y el nodo dominante.
- Se responden las 5 preguntas del profe.
- Se justifica la elección del patrón con un párrafo.

### 7.2. Salida de descarte

**Si el tiempo medido NO justifica desnormalizar** (por ejemplo, < 10ms), se documenta este resultado y NO se desnormaliza. Este resultado ES VÁLIDO: la consulta ya es suficientemente rápida.

---

## 8. Resultado de la medición

*Fecha: 19/10/2026*  
*Estado: Medido con `food-store/medicion_top_categorias_antes.sql` en `bd2_tp4u4` (salida en `food-store/medicion_antes_salida.txt`). El tiempo supera los 10 ms de la salida de descarte, así que se justifica desnormalizar.*  
*Tiempo basal (mediana de las corridas 2 a 6): 71,044 ms (rango 68,483 a 72,302 ms)*  
*Nodo dominante: `Parallel Seq Scan on detalle_pedido` (~519.000 filas leídas para quedarse con ~20.000), sin índice sobre `pedido.fecha`*

---

## Dependencia

Esta spec depende de `spec_carga_pedidos_hoy.md` (spec 3). No se puede ejecutar hasta que la carga de pedidos de hoy esté completa.