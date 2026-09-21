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
pg_restore -U postgres -d bd2_tp3 backups/bd2_tp3_actualizada_20260919.dump
```

El dump no está versionado —los `.dump` están en el `.gitignore`— y se comparte por fuera del repo
justamente para que todos midan sobre los mismos datos. Las mediciones de la Parte A del informe se hicieron
sobre `bd2_tp3_actualizada_20260919.dump`; `pg_restore` no trae estadísticas, por eso el paso 3 es obligatorio.

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
VACUUM ANALYZE;
```

`VACUUM` además deja armado el mapa de visibilidad, que el `Index Only Scan` del índice de C1 necesita.
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

`medicion_planes.sql` hace esto para cada índice candidato: imprime el `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`
antes y después, y cada "después" corre en `BEGIN … ROLLBACK`.

```bash
psql -U postgres -d bd2_trabajo -X -f medicion_planes.sql > planes_tp5_parteA.txt
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

Lo mismo con `views.sql` y con `materializadas.sql`.

## 6. Medir el "después"

Se repite el paso 4 sobre las mismas consultas y se completan las tablas de
`informe_mediciones.md`.

Para el costo sobre las escrituras (Parte A, punto 5), `medicion_escritura.sql` corre 500 `INSERT`
individuales por tabla y 500 `UPDATE` de `stock`, cada estado en su propia transacción con `ROLLBACK`, y
reporta tiempo y bytes de WAL. Una ejecución es una ronda; el informe usó 15 y tomó la mediana:

```bash
psql -U postgres -d bd2_trabajo -X -A -t -f medicion_escritura.sql
```

## Archivos

| Archivo | Contenido |
|---|---|
| `schema.sql` | Las tablas del modelo. Heredado, salvo la tabla `usuario` que se agregó en la Parte B por indicación de la cátedra |
| `data.sql` | Datos iniciales. Heredado, más los usuarios de prueba de la Parte B |
| `queries.sql` | Consultas de negocio de las Semanas 3 y 4. Fuente de la carga de trabajo a indexar |
| `restricciones.sql` | Triggers de integridad del TP2 |
| `carga_masiva.sql` | Generador de volumen del TP3 |
| `indices.sql` | Índices aceptados en la Parte A (uno) y los descartados, comentados con su motivo |
| `medicion_planes.sql` | Planes `EXPLAIN` antes y después de cada índice candidato (Parte A) |
| `medicion_escritura.sql` | Costo de escritura de los índices, en tiempo y WAL (Parte A) |
| `planes_tp5_parteA.txt` | Salida de `medicion_planes.sql` |
| `views.sql` | Las cinco vistas de la Parte B, incluida `vista_usuario_reportes` |
| `materializadas.sql` | La vista materializada de la Parte C y su índice único para `REFRESH CONCURRENTLY` |
| `specs/` | Especificaciones de Kiro, una por pieza (Partes A, B y C) |
| `duia.md` | Bitácora de uso de IA de las Partes A, B y C |
| `informe_mediciones.md` | Mediciones de las tres partes: planes y escritura (A), equivalencia de las vistas (B) y vista materializada (C) |
