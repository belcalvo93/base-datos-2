# Revisión de código asistida por IA — Unidad 1 (Modelo, normalización, restricciones y concurrencia)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `base-datos-2`
**Base de comprobación:** `bd2_trabajo` (copia de laboratorio, dentro de `BEGIN … ROLLBACK` o `READ ONLY`)

---

## 1. Alcance de la revisión (13 scripts de la Unidad 1)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `food-store/schema.sql` | DDL de las 5 tablas del núcleo (`categoria`, `cliente`, `producto`, `pedido`, `detalle_pedido`), índices iniciales y tabla `usuario` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.1) |
| `food-store/data.sql` | Semilla inicial del TP1 (5 categorías, 5 clientes, 10 productos, 5 pedidos, 9 detalles y 3 usuarios) | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.2) |
| `food-store/verificacion_normalizacion.sql` | Consultas `READ ONLY` que contrastan las dependencias funcionales y 1FN–3FN contra los datos | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |
| `food-store/restricciones.sql` | Triggers `trg_verificar_producto_activo` y `trg_verificar_stock_suficiente` sobre `detalle_pedido` | Revisado con propuesta descartada (08/11/2026) | Hallazgo 12 |
| `food-store/pruebas_restricciones.sql` | Pruebas transaccionales (`BEGIN … ROLLBACK`) de los casos válidos e inválidos de las reglas R1 y R2 | Revisado con observación documentada (08/11/2026) | Hallazgo 12 |
| `food-store/procedimientos.sql` | Procedimiento transaccional `registrar_pedido` | Revisado y corregido | Hallazgos 1 y 2 |
| `concurrencia/escenario0_atomicidad.sql` | Demostración de atomicidad (`COMMIT` y `ROLLBACK`) | Revisado con decisión documentada | Hallazgo 2 |
| `concurrencia/escenario1_lectura_no_repetible_sesionA.sql` · `_sesionB.sql` | Fenómeno de lectura no repetible bajo `READ COMMITTED` vs `REPEATABLE READ` | Revisado con decisión documentada | Hallazgo 2 |
| `concurrencia/escenario2_lectura_fantasma_sesionA.sql` · `_sesionB.sql` | Fenómeno de lectura fantasma entre dos sesiones | Revisado con decisión documentada | Hallazgo 2 |
| `concurrencia/escenario3_espera_bloqueo_sesionA.sql` · `_sesionB.sql` | Bloqueo pesimista de fila con `SELECT … FOR UPDATE` | Revisado con decisión documentada | Hallazgo 2 |

---

## 2. Revisión detallada de los scripts pendientes

### 2.1 `food-store/schema.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Las 5 tablas del dominio usan `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` y nombres en `snake_case` singular.
  - `detalle_pedido` declara `UNIQUE (id_pedido, id_producto)`, `CHECK (cantidad > 0)`, `CHECK (precio_unitario >= 0)` y no almacena `subtotal` (cumple 3FN al evitar la dependencia transitiva `cantidad, precio_unitario -> subtotal`).
  - Las claves foráneas aplican la política de borrado correcta: `ON DELETE RESTRICT` hacia `categoria`, `cliente` y `producto` (baja lógica con `activo`) y `ON DELETE CASCADE` desde `detalle_pedido` hacia `pedido`.
  - La tabla `usuario` conserva exactamente el DDL indicado por la cátedra (`id`, ENUM `rol`, `eliminado`).
- **Observación menor evaluada y descartada:** la IA sugirió cambiar `id` por `id_usuario` y `eliminado` por `activo` en `usuario` para uniformar el estilo. Se **descartó** porque `usuario` responde al DDL literal exigido por el profesor para la práctica de vistas y seguridad, documentado en los comentarios del propio archivo (líneas 115–128).

### 2.2 `food-store/data.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - No inserta IDs manuales en columnas `GENERATED ALWAYS AS IDENTITY`: resuelve las claves foráneas mediante subconsultas por clave candidata (`categoria.nombre`, `cliente.email`, `producto.nombre`).
  - Incluye casos de borde deliberados que usan las pruebas posteriores: una categoría inactiva (`Congelados`), un producto inactivo (`Helado 1L`), un producto con stock crítico (`Gaseosa cola 2.25L`, stock 1; `Medialunas x6`, stock 3), precios históricos en `detalle_pedido` distintos al precio de lista actual y un usuario dado de baja (`eliminado = TRUE`).
  - No contiene datos personales reales ni contraseñas en texto plano (usa dominios `@example.com` y hashes hexadecimales sintéticos).

### 2.3 `food-store/verificacion_normalizacion.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Abre con `BEGIN TRANSACTION READ ONLY;`, confirma la base con `SELECT current_database();` y cierra con `ROLLBACK;`, garantizando que no puede modificar ningún dato aunque se corra sobre `bd2_tp3`.
  - Cubre las 8 verificaciones (V1 a V8): restricciones en `pg_constraint`, ausencia de columna `subtotal` en `information_schema.columns`, refutación de `id_producto -> precio_unitario`, diferencia entre `precio_unitario` y `producto.precio`, unicidad de `(id_pedido, id_producto)` y contraejemplos de atributos no clave.

### 2.4 `food-store/restricciones.sql` y `food-store/pruebas_restricciones.sql` — Hallazgo 12

- **Propuesta 1 de la IA (en `restricciones.sql`):** reemplazar el trigger `trg_verificar_stock_suficiente` por una restricción declarativa `CHECK (cantidad <= (SELECT stock FROM producto p WHERE p.id_producto = id_producto))` en la tabla `detalle_pedido`, argumentando que una restricción `CHECK` es más declarativa que un trigger PL/pgSQL.
  - **Decisión humana:** **Descartado.**
  - **Comprobación en el motor (`psql` sobre `bd2_trabajo` dentro de `BEGIN … ROLLBACK`):**
    ```sql
    BEGIN;
    ALTER TABLE detalle_pedido
      ADD CONSTRAINT chk_stock
      CHECK (cantidad <= (SELECT stock FROM producto p WHERE p.id_producto = id_producto));
    ROLLBACK;
    -- Salida del motor:
    -- ERROR:  no se pueden usar subconsultas en una restricción «check»
    ```
  - **Motivo:** PostgreSQL prohíbe subconsultas en cláusulas `CHECK` (`SQLSTATE 0A000`) porque una modificación posterior en la tabla `producto` invalidaría la condición sin pasar por `detalle_pedido`. Cuando una regla de integridad cruza dos tablas distintas (`detalle_pedido` y `producto`), el mecanismo correcto en PostgreSQL es un trigger `BEFORE INSERT OR UPDATE FOR EACH ROW`.

- **Observación 2 de la IA (en `pruebas_restricciones.sql`):** en los 4 bloques de prueba se resuelve el pedido con `(SELECT id_pedido FROM pedido LIMIT 1)` sin cláusula `ORDER BY`.
  - **Decisión humana:** **Aceptado como observación documentada (sin modificar el entregable histórico de la U1).**
  - **Comprobación en el motor (`bd2_trabajo`):** sobre la semilla de `data.sql`, el primer pedido físico (`id_pedido = 1`) solo tiene cargados los productos 1 (`Pan de campo 1kg`) y 5 (`Leche entera 1L`), por lo que el Caso 2 (`Agua mineral 2L`, producto 3) y el Caso 4 (`Medialunas x6`, producto 2) no colisionan con `UNIQUE (id_pedido, id_producto)` y prueban correctamente el trigger de stock. Sin embargo, si el recorrido secuencial devolviera `id_pedido = 2` (que ya incluye `Agua mineral 2L`) o `id_pedido = 3` (que ya incluye `Medialunas x6`), el `INSERT` fallaría por clave única antes o después del trigger. Se deja documentado para la defensa que en scripts nuevos se fija el pedido por clave o con `ORDER BY id_pedido LIMIT 1`.
