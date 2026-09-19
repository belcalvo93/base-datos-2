# Food Store — cómo reproducir las pruebas

Pasos para levantar la base desde cero y repetir las mediciones del TP5. Todo se corre sobre una copia
de trabajo, nunca sobre la base del proyecto, siguiendo el protocolo de seguridad de la cátedra
(`../protocolo_seguridad.md`).

## Requisitos

- PostgreSQL 17.11 (la consigna pide 16 o superior)
- `psql` en el PATH
- Usuario `postgres`

## 1. Levantar la base

Dos caminos. El segundo es el recomendado si alguien del equipo ya corrió la carga masiva.

### Opción A — desde los scripts

```bash
createdb -U postgres bd2_tp3
psql -U postgres -d bd2_tp3 -v ON_ERROR_STOP=1 -f schema.sql
psql -U postgres -d bd2_tp3 -v ON_ERROR_STOP=1 -f data.sql
psql -U postgres -d bd2_tp3 -v ON_ERROR_STOP=1 -f restricciones.sql
psql -U postgres -d bd2_tp3 -v ON_ERROR_STOP=1 -f carga_masiva.sql
```

La carga masiva tarda alrededor de **una hora** (1:00:08 en la corrida de producción del 01/09). El
cuello de botella es el bloque de `detalle_pedido`.

**Ojo:** `carga_masiva.sql` usa `random()`, así que **cada corrida genera datos distintos**. Si dos
personas la corren por separado, las mediciones dejan de ser comparables entre sí.

### Opción B — restaurar el dump (recomendada)

```bash
createdb -U postgres bd2_tp3
pg_restore -U postgres -d bd2_tp3 backups/bd2_tp3_poblada.dump
```

El dump no está versionado —los `.dump` están en el `.gitignore`— y se comparte por fuera del repo
justamente para que todos midan sobre los mismos datos.

## 2. Verificar el volumen

```sql
SELECT 'categoria' AS tabla, count(*) FROM categoria
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'producto', count(*) FROM producto
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido;
```

Esperado: 5 categorías, 20.005 clientes, 50.011 productos, 200.005 pedidos, 499.263 detalles.

## 3. Actualizar las estadísticas

```sql
ANALYZE;
```

Sin esto el planificador trabaja con estimaciones viejas y elige planes que no corresponden al volumen
real. Es la causa más común de mediciones que no se pueden reproducir.

## 4. Medir el "antes"

Los planes previos a los índices del TP5 se toman con los índices heredados del TP1 ya presentes. Para
ver cuáles están:

```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename, indexname;
```

Cada consulta se corre **al menos dos veces** y se reporta la segunda: la primera incluye el costo de
traer las páginas a memoria.

```sql
EXPLAIN (ANALYZE, BUFFERS) <consulta de queries.sql>;
```

## 5. Aplicar los objetos del TP5

Primero se lee el script línea por línea, después se prueba dentro de una transacción reversible, y
recién con el resultado a la vista se confirma:

```sql
BEGIN;
\i indices.sql
-- revisar el efecto
ROLLBACK;   -- cambiar por COMMIT cuando el resultado sea el esperado
```

Lo mismo con `views.sql`.

## 6. Medir el "después"

Se repite el paso 4 sobre las mismas consultas y se completan las tablas de
`informe_mediciones.md`.

Para el costo sobre las escrituras (Parte A, punto 5), la carga de `INSERT` en `detalle_pedido` se mide
con `\timing on` dentro de `BEGIN ... ROLLBACK`, antes y después de crear los índices.

## Archivos

| Archivo | Contenido |
|---|---|
| `schema.sql` | Las cinco tablas. Heredado, no se modifica |
| `data.sql` | Datos iniciales. Heredado |
| `queries.sql` | Consultas de negocio de las Semanas 3 y 4. Fuente de la carga de trabajo a indexar |
| `restricciones.sql` | Triggers de integridad del TP2 |
| `carga_masiva.sql` | Generador de volumen del TP3 |
| `indices.sql` | Índices aceptados en la Parte A |
| `views.sql` | Vistas de la Parte B y la vista materializada de la Parte C |
| `specs/` | Especificaciones de Kiro, una por pieza |
| `duia.md` | Bitácora de uso de IA |
| `informe_mediciones.md` | `EXPLAIN ANALYZE` antes y después, lectura y escritura |
