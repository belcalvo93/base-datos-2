# Spec de la vista materializada — TP5 Parte C

**Archivo de implementación:** `food-store/views.sql`
**Informe de mediciones:** `food-store/informe_mediciones.md`

> **Estado: esqueleto.** Los campos marcados con `...` los completa quien tome la Parte C.

---

## Vista materializada — `...`

### Propósito

El reporte agregado que se materializa y por qué vale la pena: ...

La consigna sugiere facturación por categoría y mes, pero admite cualquier otro reporte que salga de
las consultas analíticas de la Semana 4 (`docs/informe_tp4_semana4.md`).

### Consulta base

```sql
...
```

Sobre `bd2_tp3` esta consulta atraviesa ... filas antes de agregar, y ahí está el costo que justifica
materializarla.

### Columnas de la vista

| Columna | Origen | Tipo | Notas |
|---|---|---|---|
| ... | ... | ... | ... |

### Índice único para `REFRESH CONCURRENTLY`

`REFRESH MATERIALIZED VIEW CONCURRENTLY` no funciona sin un índice único sobre la vista. Es el que
permite refrescar sin bloquear a quien esté leyendo: sin él, el `REFRESH` toma un `ACCESS EXCLUSIVE` y
el reporte queda inaccesible mientras dura.

El índice tiene que ser único sobre la combinación de columnas que identifica una fila del reporte, sin
nulos:

```sql
CREATE UNIQUE INDEX ... ON ... (...);
```

Columnas elegidas y por qué identifican una fila unívocamente: ...

### Restricciones de implementación

- Se crea con `WITH DATA`, así queda poblada desde el arranque.
- Las columnas se listan explícitamente; no se usa `SELECT *`.
- No se modifica el modelo de datos ni las restricciones de las tablas base.

### Criterio de aceptación

1. El tiempo de consultar la vista materializada es al menos ... veces menor que el de la consulta sin
   materializar, medido con `EXPLAIN ANALYZE` en las dos.
2. Los resultados coinciden: `EXCEPT` en las dos direcciones devuelve 0 filas contra la consulta
   original, ejecutado inmediatamente después del `REFRESH`.
3. `REFRESH MATERIALIZED VIEW CONCURRENTLY` corre sin error, lo que prueba que el índice único sirve.

### Frecuencia de refresco

El punto 3 de la Parte C pide justificar cada cuánto correr el `REFRESH` y qué implica para el usuario
que el dato no se actualice entre uno y otro.

| Pregunta | Respuesta |
|---|---|
| Cada cuánto se consulta el reporte | ... |
| Cada cuánto cambian los datos de origen | ... |
| Frecuencia de refresco propuesta | ... |
| Desfasaje máximo que ve el usuario | ... |
| Qué decisión se tomaría mal con un dato desactualizado | ... |

La última fila es la que define de verdad la frecuencia: si con datos de ayer nadie toma una decisión
equivocada, refrescar cada hora es gasto puro.
