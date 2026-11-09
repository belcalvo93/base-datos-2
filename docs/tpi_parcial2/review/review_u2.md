# Revisión de código asistida por IA — Unidad 2 (Carga masiva)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `base-datos-2`
**Base de comprobación:** `bd2_trabajo` (dentro de `BEGIN … ROLLBACK` y con `EXPLAIN`)

---

## 1. Alcance de la revisión (3 scripts de la Unidad 2)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `food-store/carga_masiva.sql` | Carga masiva de 50.000 productos, 20.000 clientes, 200.000 pedidos y ~500.000 líneas de detalle | Revisado con propuesta descartada (08/11/2026) | Hallazgo 13 |
| `food-store/carga_masiva_bloque3_B.sql` | Variante experimental B del bloque 3 (`MATERIALIZED` + `Hash Join`), medida y descartada frente a la variante A | Revisado sin observaciones (08/11/2026) | Hallazgo 13 |
| `food-store/verificacion_carga_masiva.sql` | Consultas de solo lectura que auditan la distribución de `id_categoria` e `id_cliente` tras la carga | Revisado con observación documentada (08/11/2026) | Hallazgo 13 |

---

## 2. Revisión detallada de los scripts

### 2.1 `food-store/carga_masiva.sql` — Hallazgo 13

- **Propuesta de la IA:** eliminar la expresión `+ s.i * 0` en los bloques 1 y 3 (`ORDER BY random() + s.i * 0 LIMIT 1`) y `+ lpp.id_pedido * 0` en el bloque 4 (`ORDER BY random() + lpp.id_pedido * 0 LIMIT 4`), argumentando que multiplicar por cero y sumar cero es una operación aritmética redundante que ensucia la consulta.
- **Decisión humana:** **Descartado.**
- **Comprobación en el motor (`psql` sobre `bd2_trabajo` con `EXPLAIN`):**
  ```sql
  -- 1) Sin "+ s.i * 0" (propuesta de la IA):
  EXPLAIN SELECT (SELECT id_categoria FROM categoria ORDER BY random() LIMIT 1)
  FROM generate_series(1, 10) s(i);
  -- Plan:
  -- Function Scan on generate_series s  (cost=16.31..16.41 rows=10 width=8)
  --   InitPlan 1
  --     ->  Limit  (cost=16.30..16.30 rows=1 width=16)
  --           ->  Sort  (Sort Key: (random()))

  -- 2) Con "+ s.i * 0" (código actual del repo):
  EXPLAIN SELECT (SELECT id_categoria FROM categoria ORDER BY random() + s.i * 0 LIMIT 1)
  FROM generate_series(1, 10) s(i);
  -- Plan:
  -- Function Scan on generate_series s  (cost=0.00..190.13 rows=10 width=8)
  --   SubPlan 1
  --     ->  Limit  (cost=19.00..19.00 rows=1 width=16)
  --           ->  Sort  (Sort Key: ((random() + ((s.i * 0))::double precision)))
  ```
- **Motivo técnico:** cuando la subconsulta no referencia ninguna columna de la fila externa (`s.i`), el planificador de PostgreSQL la compila como un `InitPlan` no correlacionado (o le inserta un nodo `Materialize` en el `CROSS JOIN LATERAL` del bloque 4), lo ejecuta **una sola vez** (`loops=1`) y reutiliza el mismo resultado en las 50.000 o 200.000 filas, asignando todos los productos a una única categoría y todos los pedidos a un único cliente. La expresión `+ s.i * 0` crea la dependencia sintáctica con la fila exterior sin alterar el valor de `random()`, obligando al optimizador a usar un `SubPlan` evaluado por fila.
- **Otros controles verificados en `carga_masiva.sql`:**
  - El bloque 4 filtra `WHERE activo = TRUE AND stock >= 4` (líneas 168–169) para que el sorteo de 1 a 4 unidades nunca elija los productos semilla inactivos (`id = 10`) o con stock menor a 4 (`id = 2`, `id = 4`) y no aborte por los triggers de `restricciones.sql`.
  - No abre ni cierra transacción por su cuenta, permitiendo envolver la corrida en `BEGIN … ROLLBACK` antes del `COMMIT` definitivo.

### 2.2 `food-store/carga_masiva_bloque3_B.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Está claramente documentado como variante experimental descartada tras medir (6.778 ms vs 9.676 ms en 10.000 filas; mejora de solo 1,4× porque el `CTE Scan on dominio_clientes` seguía ejecutándose `loops=10000` dentro del `Nested Loop`).
  - Explica con precisión por qué usar `AS MATERIALIZED` sobre un dominio determinista (`ROW_NUMBER() OVER (ORDER BY id_cliente)`) es válido, a diferencia de materializar un sorteo aleatorio.

### 2.3 `food-store/verificacion_carga_masiva.sql` — Hallazgo 13 (observación documentada)

- **Observación de la IA:** las subconsultas `recientes` usan `LIMIT 10000` fijo (líneas 20, 35, 52 y 62), que corresponde al volumen del escenario de prueba mediana, mientras que `carga_masiva.sql` quedó configurado con el volumen de producción (`50000` productos y `200000` pedidos).
- **Decisión humana:** **Aceptado como observación documentada (no requiere modificar el script).**
- **Motivo:** el encabezado del propio archivo (línea 6: *"Los LIMIT deben copiar el volumen del bloque correspondiente"*) ya documenta esa calibración, y además tomar una ventana de las últimas 10.000 filas insertadas (`ORDER BY id_producto DESC LIMIT 10000` y `ORDER BY id_pedido DESC LIMIT 10000`) alcanza de forma inmediata para distinguir una distribución sana (~2.000 productos por cada una de las 5 categorías y ~3.900 clientes distintos) del fallo por `InitPlan` (1 sola categoría o 1 solo cliente con las 10.000 filas).
