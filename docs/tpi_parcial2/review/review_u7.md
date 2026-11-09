# Revisión de código asistida por IA — Unidad 7 (Modelado documental en MongoDB)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `BaseDatos2-MongoDB`
**Base de comprobación:** PostgreSQL (`bd2_trabajo` / `bd2_tp3` en modo lectura) y MongoDB (`foodstore`)

---

## 1. Alcance de la revisión (4 scripts de la Unidad 7)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `seleccion_pedidos.sql` | Selección de solo lectura en PostgreSQL de los 8 pedidos (30 líneas) a migrar, resumen de control y generación del documento JSON con `jsonb_build_object` | Revisado con propuesta descartada (08/11/2026) | Hallazgo 17 |
| `consultas_postgresql.sql` |Las 5 consultas de verificación en SQL sobre el subconjunto de 8 pedidos migrados para contrastar contra MongoDB | Revisado con propuesta descartada (08/11/2026) | Hallazgo 17 |
| `consultas_mongodb.js` | Creación de la colección `pedidos` con validador `$jsonSchema`, inserción con `NumberDecimal`, 5 consultas equivalentes y auditoría del total | Revisado y corregido | Hallazgo 9 |
| `prueba_indice_unico_ia.js` | Demostración de laboratorio en `mongosh` del fallo del índice único multikey sobre `lineas.id_producto` | Revisado sin observaciones (08/11/2026) | Hallazgo 9 |

---

## 2. Revisión detallada de los scripts pendientes

### 2.1 `seleccion_pedidos.sql` y `consultas_postgresql.sql` — Hallazgo 17

- **Propuesta 1 de la IA (en `seleccion_pedidos.sql`):** dentro de la consulta 3 (`jsonb_build_object` de las líneas 69–88), agregar el atributo `'subtotal', dp.cantidad * dp.precio_unitario` dentro de cada objeto del arreglo `lineas`, y dejar `p.fecha` sin convertir a `UTC`.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en el motor (`psql` sobre `bd2_trabajo`):**
    1. Si se persiste `subtotal` dentro de cada elemento de `lineas[]` en MongoDB, se introduce redundancia interna dentro del mismo subdocumento (`subtotal = cantidad * precio_unitario`) que contradice la especificación de `modelo_documental.md` (donde solo se almacena `total` en la cabecera del documento como `Decimal128` y se audita contra la suma de `cantidad * precio_unitario` de `lineas[]`). En `seleccion_pedidos.sql`, `subtotal_linea` se proyecta únicamente en la consulta tabular 1 (línea 28) para lectura humana, pero se excluye deliberadamente del JSON de migración en la consulta 3 (líneas 80–85).
    2. Al ejecutar en PostgreSQL `SET TIME ZONE 'America/Argentina/Mendoza'; SELECT id_pedido, fecha FROM pedido WHERE id_pedido = 1;` devuelve `2026-08-01 10:15:00-03`, mientras que con `SET TIME ZONE 'UTC'` o `AT TIME ZONE 'UTC'` devuelve `2026-08-01 13:15:00+00` (`2026-08-01T13:15:00Z`). Convertir explícitamente a UTC en `seleccion_pedidos.sql` (línea 71) y fijar `SET TIME ZONE 'UTC';` en `consultas_postgresql.sql` (línea 16) garantiza que las marcas de tiempo coincidan exactamente con la representación ISO-8601 UTC de MongoDB.

- **Propuesta 2 de la IA (en `consultas_postgresql.sql`):** agregar `AND p.eliminado = FALSE` en las consultas SQL de verificación y quitar el predicado `WHERE p.id_pedido IN (1, 2, 3, 4, 5, 45018, 59428, 74364)`.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en el motor (`psql` sobre `bd2_trabajo`):**
    ```sql
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN ('pedido', 'detalle_pedido', 'cliente', 'producto')
      AND column_name = 'eliminado';
    -- Salida: (0 filas)
    ```
  - **Motivo técnico:** ni `pedido` ni `detalle_pedido` tienen columna `eliminado` (esa columna pertenece exclusivamente a `usuario`, mientras que `producto` y `categoria` usan `activo`, que no filtra ventas históricas cerradas). Además, como a MongoDB se migró una muestra representativa de 8 pedidos (y no los 200.005 pedidos de `bd2_tp3`), quitar el filtro `WHERE p.id_pedido IN (...)` en `consultas_postgresql.sql` impediría comparar cardinalidades e IDs 1 a 1 entre ambos motores en `consigna5_tabla_comparativa.md`.
