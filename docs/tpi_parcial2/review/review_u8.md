# Revisión de código asistida por IA — Unidad 8 (SQLite móvil e integración con servidor)

**Revisor:** Bruno Fiouchetta con OpenCode (agente Plan, modo de solo lectura) · **Fecha:** 08/11/2026
**Repositorio:** `BaseDatos2-MongoDB`
**Base de comprobación:** SQLite 3.49.1 (`foodstore_movil.db` y `:memory:`) y PostgreSQL 17 (`bd2_tp8` / `bd2_trabajo`)

---

## 1. Alcance de la revisión (8 scripts de la Unidad 8)

| Script | Propósito | Estado de revisión | Hallazgo en `3c_code_review_ia.md` |
|---|---|---|---|
| `food-store/postgresql/10_snapshot_catalogo.sql` | Vista `v_snapshot_movil` en PostgreSQL (precios en centavos enteros y lápidas `NOT p.activo OR NOT c.activo`) | Revisado y corregido | Hallazgo 11 |
| `food-store/movil/schema_sqlite.sql` | 6 tablas `STRICT` en SQLite, índice único parcial `ux_cola_una_pendiente`, tabla `evaluacion_sync` y vista `v_catalogo_disponible` | Revisado con propuesta descartada | Hallazgo 10 |
| `food-store/movil/importar_catalogo.sql` | Importación de `servidor_snapshot.csv` en `snapshot_servidor` y upsert a `producto_cache` preservando claves foráneas | Revisado con propuesta descartada (08/11/2026) | Hallazgo 18 |
| `food-store/movil/pruebas_sqlite.sql` | Pruebas en `pruebas.db`: `COMMIT`, `ROLLBACK`, cálculo de subtotal en centavos/pesos, C1 y errores esperados de C7 (`CHECK` y `FK`) | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.2) |
| `food-store/movil/semaforo.sql` | Evaluación atómica de solicitudes `PENDIENTE`, inserción en `evaluacion_sync` y actualización de `cola_sync` | Revisado y corregido | Hallazgo 11 |
| `food-store/postgresql/casos_servidor.sql` | Guarda de base `bd2_tp8`, reset idempotente (Paso 0), preparación de C2/C3/C4 y exportación de `servidor_snapshot.csv` | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |
| `food-store/movil/casos_sqlite.sql` | Simulación completa de los casos C2 a C6 en SQLite, reenvío tras conflicto en C2 e idempotencia en C6 | Revisado con propuesta descartada (08/11/2026) | Hallazgo 18 |
| `food-store/postgresql/consulta_final.sql` | Verificación de solo lectura en `bd2_tp8` tras la simulación móvil (200.005 pedidos intactos y stock sin cambios por el móvil) | Revisado sin observaciones (08/11/2026) | Sin observaciones (ver §2.3) |

---

## 2. Revisión detallada de los scripts pendientes

### 2.1 `food-store/movil/importar_catalogo.sql` y `food-store/movil/casos_sqlite.sql` — Hallazgo 18

- **Propuesta 1 de la IA (en `importar_catalogo.sql`):** reemplazar el `INSERT INTO producto_cache ... SELECT ... FROM snapshot_servidor WHERE true ON CONFLICT (producto_id) DO UPDATE ...` por un `DELETE FROM producto_cache;` seguido de un `INSERT INTO producto_cache SELECT ... FROM snapshot_servidor;` (igual que se hace con `snapshot_servidor`), o bien eliminar la cláusula `WHERE true` por considerarla superflua.
  - **Decisión humana:** **Descartado en ambos puntos.**
  - **Comprobación en el motor (`sqlite3` 3.49.1 sobre `foodstore_movil.db` y en memoria):**
    1. **Por qué no se puede hacer `DELETE FROM producto_cache`:** en la Etapa 2 de `casos_sqlite.sql` (línea 125), la tablet ya tiene creados en `item_borrador` los borradores offline C2, C3, C4 y C5 (que tienen `FOREIGN KEY (producto_id) REFERENCES producto_cache(producto_id)` con `PRAGMA foreign_keys = ON`) cuando recibe la nueva instantánea y ejecuta `.read movil/importar_catalogo.sql`. Al probar en el motor:
       ```sql
       PRAGMA foreign_keys = ON;
       BEGIN;
       DELETE FROM producto_cache;
       -- Salida de SQLite:
       -- sqlite3.IntegrityError: FOREIGN KEY constraint failed
       ```
       Con el `ON CONFLICT (producto_id) DO UPDATE`, las filas de `producto_cache` nunca se borran: los productos dados de baja en el servidor (como el producto 11 en C4) se actualizan con `eliminado = 1` (lápida), manteniendo intacta la integridad referencial de los borradores pendientes.
    2. **Por qué `WHERE true` es obligatorio en SQLite:** en la gramática de SQLite, cuando un `INSERT INTO ... SELECT ... FROM tabla` va seguido inmediatamente por `ON CONFLICT`, el analizador sintáctico interpreta la palabra clave `ON` como la condición de un `JOIN` sobre `snapshot_servidor` a menos que exista una cláusula `WHERE` previa que cierre el `FROM`. Al comprobarlo en SQLite quitando `WHERE true`:
       ```sql
       INSERT INTO t SELECT id, v FROM s ON CONFLICT(id) DO UPDATE SET v=excluded.v;
       -- Salida de SQLite:
       -- sqlite3.OperationalError: near "DO": syntax error
       ```

- **Propuesta 2 de la IA (en `casos_sqlite.sql`):** en el Caso C2 (parte 2, líneas 164–171), en lugar de insertar una nueva solicitud en `cola_sync` con un nuevo `solicitud_uuid` (`dddddddd-0000-4000-8000-000000000202`), hacer `UPDATE cola_sync SET estado = 'PENDIENTE' WHERE solicitud_uuid = 'dddddddd-0000-4000-8000-000000000002'`.
  - **Decisión humana:** **Descartado.**
  - **Motivo y comprobación:** reutilizar el mismo `solicitud_uuid` después de modificar el precio aceptado por el cliente en `item_borrador` viola el requisito de idempotencia y trazabilidad (REQ-06 y diseño de `evaluacion_sync`): cada intento de envío con condiciones distintas es una solicitud nueva con su propio `solicitud_uuid`, quedando en `cola_sync` y en `evaluacion_sync` la historia completa (primero el intento `...0002` en `CONFLICTO` con visto `140000` vs actual `160000`, y luego la nueva solicitud `...0202` en `SIMULADO_APROBADO` con visto `160000`).

### 2.2 `food-store/movil/pruebas_sqlite.sql` — Revisado sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Activa `PRAGMA foreign_keys = ON;` antes de cualquier `BEGIN`.
  - Prueba la atomicidad de los 3 `INSERT` del borrador con `COMMIT` (1/1/1 filas) y con `ROLLBACK` (antes = después), el cálculo del subtotal en centavos enteros (`300000`) y en pesos (`3000.0`) sin almacenarlo en la tabla, la vista `v_catalogo_disponible` sin servidor (C1) y los 2 rechazos esperados de C7 (`CHECK (cantidad > 0)` y `FOREIGN KEY` de `producto_id` inexistente), cerrando cada prueba fallida con `ROLLBACK` explícito porque en SQLite un error de restricción revierte la sentencia pero mantiene abierta la transacción.

### 2.3 `food-store/postgresql/casos_servidor.sql` y `food-store/postgresql/consulta_final.sql` — Revisados sin observaciones (08/11/2026)

- **Verificación de cumplimiento:**
  - Ambos scripts comienzan con `\set ON_ERROR_STOP on` y la guarda `DO $$ BEGIN IF current_database() <> 'bd2_tp8' THEN RAISE EXCEPTION ... END IF; END $$;`, protegiendo a `bd2_tp3`.
  - `casos_servidor.sql` incluye el Paso 0 de idempotencia (restablece stock 3 en producto 2, precio 1400.00 en producto 3 y `activo = true` en producto 11 antes de tomar la consulta inicial), aplica los cambios de C2, C3 y C4 dentro de `BEGIN … COMMIT`, exporta `movil/servidor_snapshot.csv` y documenta el estado de referencia (200.005 pedidos y stock `1, 40, 30, 0, 10`).
  - `consulta_final.sql` es estrictamente de lectura y verifica que tras ejecutar toda la simulación móvil en SQLite, PostgreSQL conserva exactamente los mismos 200.005 pedidos y el mismo stock del Paso 4.
