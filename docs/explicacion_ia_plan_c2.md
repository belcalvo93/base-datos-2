# Explicación del Plan de EXPLAIN ANALYZE

> **Generado por:** OpenCode (Big Pickle / OpenCode Zen)
> **Fecha:** 02/09/2026
> **Contexto de la consulta:** Se pidió sin más contexto que el texto crudo del plan de EXPLAIN ANALYZE correspondiente a la consulta C2 de la Parte 2, como pide la consigna.
> **Nota:** Esta explicación se conserva sin editar porque constituye el insumo para el análisis crítico de la Parte 3.

---

## Plan de EXPLAIN ANALYZE (texto original)

```
 Sort  (cost=50.60..50.62 rows=10 width=44) (actual time=0.114..0.116 rows=24 loops=1)
   Sort Key: p.fecha DESC
   Sort Method: quicksort  Memory: 26kB
   ->  Nested Loop  (cost=4.66..50.43 rows=10 width=44) (actual time=0.055..0.093 rows=24 loops=1)
         ->  Index Scan using cliente_pkey on cliente c  (cost=0.29..8.30 rows=1 width=32) (actual time=0.017..0.017 rows=1 loops=1)
               Index Cond: (id_cliente = 20155)
         ->  Bitmap Heap Scan on pedido p  (cost=4.37..42.02 rows=10 width=28) (actual time=0.035..0.069 rows=24 loops=1)
               Recheck Cond: (id_cliente = 20155)
               Heap Blocks: exact=23
               ->  Bitmap Index Scan on idx_pedido_id_cliente  (cost=0.00..4.37 rows=10 width=0) (actual time=0.026..0.026 rows=24 loops=1)
                     Index Cond: (id_cliente = 20155)
 Planning Time: 0.513 ms
 Execution Time: 0.147 ms
```

---

## Explicación nodo por nodo

El plan consulta los pedidos de un cliente específico (`id_cliente = 20155`) y los ordena por fecha descendente. Se ejecuta de **abajo hacia arriba** (los hijos primero, el padre al final).

---

### 1. Bitmap Index Scan (nodo hoja — más interno)

```
Bitmap Index Scan on idx_pedido_id_cliente
  Index Cond: (id_cliente = 20155)
  actual time=0.026..0.026  rows=24  loops=1
```

**Qué hace:** Busca en el índice `idx_pedido_id_cliente` todas las entradas donde `id_cliente = 20155`. No accede a la tabla — solo recopila los **TIDs** (punteros a filas) del índice.

**Resultado:** Encuentra 24 TIDs. Tiempo: 0.026 ms. Muy rápido porque es búsqueda puntual en un B-tree/índice.

---

### 2. Bitmap Heap Scan (padre del nodo anterior)

```
Bitmap Heap Scan on pedido p
  Recheck Cond: (id_cliente = 20155)
  Heap Blocks: exact=23
  actual time=0.035..0.069  rows=24  loops=1
```

**Qué hace:** Toma los 24 TIDs del paso anterior y accede a las filas reales en la tabla `pedido`. Usa el **bitmap** para ir directamente a los bloques exactos (23 páginas de disco), sin escanear toda la tabla.

**Por qué "Heap":** Son filas de la tabla heap (almacenamiento principal). El `Recheck Cond` indica que PostgreSQL verifica que cada fila leída realmente cumpla `id_cliente = 20155` (por si hubo cambios concurrentes entre la creación del bitmap y la lectura).

**Rendimiento:** 24 filas en 0.034 ms. El acceso a 23 bloques es eficiente porque es random I/O dirigido, no un sequential scan completo.

---

### 3. Index Scan on cliente_pkey (segundo hijo del Nested Loop)

```
Index Scan using cliente_pkey on cliente c
  Index Cond: (id_cliente = 20155)
  actual time=0.017..0.017  rows=1  loops=1
```

**Qué hace:** Busca directamente en la clave primaria de `cliente` la fila con `id_cliente = 20155`. Devuelve 1 fila (un cliente específico).

**Rendimiento:** 0.017 ms. Acceso puntual a PK = lo más rápido que existe en PostgreSQL.

---

### 4. Nested Loop (combina ambos hijos)

```
Nested Loop
  actual time=0.055..0.093  rows=24  loops=1
```

**Qué hace:** Para **cada fila** del cliente (1 fila), ejecuta el Bitmap Heap Scan de pedidos. Como es 1×24, se traduce en 24 combinaciones totales. En este caso particular, como el lado izquierdo tiene 1 sola fila, el nested loop es óptimo — equivalente a un simple "lookup".

**Patrón:** `Para cada cliente → buscar sus pedidos`. Es el patrón clásico de FK lookup.

---

### 5. Sort (nodo raíz)

```
Sort
  Sort Key: p.fecha DESC
  Sort Method: quicksort  Memory: 26kB
  actual time=0.114..0.116  rows=24  loops=1
```

**Qué hace:** Ordena las 24 filas resultantes por `p.fecha DESC`. Usa quicksort en memoria (26 kB, cabe en work_mem sin problemas).

**Rendimiento:** 0.002 ms para ordenar 24 filas — despreciable.

---

## Resumen de rendimiento

| Métrica | Valor |
|---------|-------|
| Planning Time | 0.513 ms |
| Execution Time | **0.147 ms** |
| Filas devueltas | 24 |
| Bloques leídos | 23 páginas de `pedido` |

**Veredicto:** El plan es **muy eficiente**. No hay sequential scans, no hay hash joins, toda la data se recupera por índices. El tiempo total de ejecución (0.147 ms) es excelente. Las estimaciones del optimizador (`rows=10`) difieren de la realidad (`rows=24`) pero no afectan porque el plan elegido (index scan → nested loop → sort) es el correcto de todas formas.

**Si esto fuera lento**, los candidatos a optimizar serían:
- Agregar un índice compuesto `(id_cliente, fecha DESC)` en `pedido` para satisfacer el ORDER BY sin el paso de Sort
- Pero con 24 filas, el Sort es tan barato que no vale la pena
