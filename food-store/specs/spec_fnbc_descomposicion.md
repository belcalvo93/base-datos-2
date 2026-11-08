# Spec: FNBC - Descomposición sin pérdida

**Responsable**: Hernán  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-11-08 — Se agrega la sección 9 «Plan de reversión» y la evidencia del ciclo completo `migrar → verificar → revertir → verificar` en `food-store/tp_fnbc_reversion.sql` (`food-store/tp_fnbc_reversion_salida.txt`). Antes (2026-10-18): descomposición ajustada al esquema de la consigna (R1 con PK `responsable_control_id`, R2 con PK `(lote_id, responsable_control_id)`, unión por `responsable_control_id` y vista `v_control_lote_almacen`).

---

## 1. Objetivo

Descomponer la tabla `control_lote_almacen` en dos tablas que cumplan FNBC, mantener la equivalencia mediante una vista con NATURAL JOIN, y verificar que no hay pérdida de información.

---

## 2. Consulta

### 2.1. Tablas resultantes

Según el análisis de dependencias funcionales:

- **R1 — Depósito del responsable** (`responsable_deposito`):
  - PK: `responsable_control_id`
  - FKs: `deposito_id → deposito(id)`, `responsable_control_id → usuario(id)`

- **R2 — Control de lote** (`control_lote`):
  - PK: `(lote_id, responsable_control_id)`
  - FKs: `lote_id → lote(id)`, `responsable_control_id → responsable_deposito(responsable_control_id)`

### 2.2. Justificación de la descomposición

La DF `(lote_id, deposito_id) → responsable_control_id` NO se preserva en la descomposición. Esto debe documentarse en el informe.

El atributo común de la unión es `responsable_control_id`, que es superclave de R1 (`responsable_deposito`); eso garantiza la unión sin pérdida.

---

## 3. Frecuencia y carga

- **Frecuencia**: igual que la spec 1 (operación manual).
- **Carga**: ~3-10 registros heredados de la instancia anterior.

---

## 4. Columnas relevantes

| Tabla | Columnas |
|-------|----------|
| `responsable_deposito` | responsable_control_id (PK), deposito_id |
| `control_lote` | lote_id (PK), responsable_control_id (PK) |

---

## 5. Estado actual medido

No aplica (depende de spec 1).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Crear las dos tablas** con sus PKs y FKs correspondientes.
2. **Crear una vista de compatibilidad** que reconstruya `(lote_id, deposito_id, responsable_control_id)` con NATURAL JOIN (la única columna común es `responsable_control_id`):
   ```sql
   CREATE OR REPLACE VIEW v_control_lote_almacen AS
   SELECT lote_id, deposito_id, responsable_control_id
   FROM control_lote
   NATURAL JOIN responsable_deposito;
   ```
3. **Migrar los datos** desde `control_lote_almacen` a las nuevas tablas (primero dentro de `BEGIN; … ROLLBACK;` para verificar el resultado antes de confirmar).
4. **Verificar equivalencia** en ambas direcciones usando EXCEPT (también dentro de `BEGIN; … ROLLBACK;`):
   - Datos originales menos datos reconstruidos (debe dar 0 filas).
   - Datos reconstruidos menos datos originales (debe dar 0 filas).

5. **Script completo idempotente** para `food-store/tp_fnbc_control_lote.sql` (segunda mitad).

### 6.2. Lo que NO se puede hacer sin justificar

- Modificar la estructura de `lote`, `deposito` o `usuario`.
- Eliminar la tabla original `control_lote_almacen` (se mantiene para comparaciones).
- Cambiar la lógica de la vista o la migración.

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- Las dos tablas nuevas se crean sin errores.
- La vista `v_control_lote_almacen` devuelve los mismos datos que la tabla original.
- Ambos EXCEPT devuelven 0 filas (equivalencia verificada).
- El conteo de filas en las tablas nuevas es igual al conteo en la tabla original.

### 7.2. Salida de descarte

Si la equivalencia no se verifica (EXCEPT devuelve filas), se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

- **Fecha**: 2026-10-20 (descomposición) / 2026-11-08 (plan y prueba de reversión)
- **Estado**: Aceptado (verificado en `bd2_tp4u4` primero dentro de `BEGIN; … ROLLBACK;` y luego con `COMMIT` en la copia)
- **Resultados obtenidos**:
  - Creación limpia de `responsable_deposito` (2 filas migradas: `801 → 30`, `802 → 31`) y `control_lote` (3 filas migradas: `(501, 801)`, `(502, 801)`, `(503, 802)`).
  - La vista `v_control_lote_almacen` (`control_lote NATURAL JOIN responsable_deposito`) reconstruye las 3 filas originales (`filas_original = 3`, `filas_vista_reconstruida = 3`).
  - Equivalencia verificada con `EXCEPT` en ambas direcciones: `control_lote_almacen EXCEPT v_control_lote_almacen` devuelve **0 filas** y `v_control_lote_almacen EXCEPT control_lote_almacen` devuelve **0 filas**.
  - Reversión verificada el 2026-11-08 con `food-store/tp_fnbc_reversion.sql` (primero con `ROLLBACK` y luego con `COMMIT` sobre `bd2_tp4u4`; salida en `food-store/tp_fnbc_reversion_salida.txt`): reconstrucción íntegra de las 3 filas en `control_lote_almacen` desde `control_lote NATURAL JOIN responsable_deposito`, `EXCEPT` en ambas direcciones con **0 filas** antes y después de borrar `v_control_lote_almacen`, `control_lote` y `responsable_deposito` en orden de FK sin `CASCADE`.

---

## 9. Plan de reversión

### 9.1. Cuándo se aplica

El plan de reversión se ejecuta si, una vez migrado el esquema a FNBC (`responsable_deposito` y `control_lote`), se presenta alguno de estos escenarios:

1. **Incompatibilidad con escrituras directas:** procesos o clientes que intentan ejecutar `INSERT`, `UPDATE` o `DELETE` sobre `control_lote_almacen` (la vista `v_control_lote_almacen` usa `NATURAL JOIN` entre dos tablas y no es actualizable de forma automática en PostgreSQL sin un trigger `INSTEAD OF`).
2. **Necesidad de imponer declarativamente la dependencia $F_1$:** como la descomposición a FNBC preserva $F_2$ ($\text{responsable\_control\_id} \rightarrow \text{deposito\_id}$) pero **no preserva** $F_1$ ($\{\text{lote\_id}, \text{deposito\_id}\} \rightarrow \text{responsable\_control\_id}$) en una sola tabla, si el negocio prioriza garantizar $F_1$ mediante la clave primaria compuesta `(lote_id, deposito_id)` sin costo de `JOIN` en validación, se revierte a la tabla unificada `control_lote_almacen`.

### 9.2. Qué se deshace y cómo se garantiza que no hay pérdida

Dado que la descomposición cumple el Teorema de Heath ($R_1 \cap R_2 = \{\text{responsable\_control\_id}\}$ es superclave de $R_1$), la unión natural `control_lote NATURAL JOIN responsable_deposito` conserva exactamente toda la información vigente en las tablas descompuestas. La reversión se ejecuta íntegramente dentro de una única transacción (`BEGIN … ROLLBACK` en la prueba inicial y `BEGIN … COMMIT` al confirmar sobre la copia `bd2_tp4u4`, con guarda previa `current_database() = 'bd2_tp4u4'`):

1. **Captura de referencia previa a la reversión:** se guarda en una tabla temporal de la transacción (`temp_pre_reversion`) el conjunto de tuplas reconstruido desde `v_control_lote_almacen` (`SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen`).
2. **Restauración de `control_lote_almacen`:** se asegura la existencia de la tabla original `control_lote_almacen(lote_id, deposito_id, responsable_control_id)` con su PK `(lote_id, deposito_id)` y sus tres claves foráneas (`lote(id)`, `deposito(id)`, `usuario(id)`), se limpia cualquier estado obsoleto y se vuelcan en ella todas las filas desde las tablas descompuestas:
   ```sql
   TRUNCATE TABLE control_lote_almacen;

   INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
   SELECT cl.lote_id, rd.deposito_id, cl.responsable_control_id
   FROM control_lote cl
   NATURAL JOIN responsable_deposito rd;
   ```
3. **Verificación previa al borrado de objetos:** antes de eliminar la vista y las tablas en FNBC, se comprueba que `control_lote_almacen` contiene exactamente las mismas tuplas que `v_control_lote_almacen` mediante `EXCEPT` en ambas direcciones (ambas consultas deben devolver **0 filas**).

### 9.3. Orden de eliminación por dependencias y claves foráneas

Los objetos creados por la descomposición se eliminan en orden inverso al de creación, **sin usar `CASCADE`**, de modo que el motor valide que no queda ninguna dependencia colgada en cada paso:

| Paso | Sentencia | Por qué va en este orden |
|------|-----------|--------------------------|
| **1.º** | `DROP VIEW v_control_lote_almacen;` | La vista depende de `control_lote` y de `responsable_deposito`. Si se intentara borrar cualquiera de las dos tablas antes, PostgreSQL abortaría la sentencia porque `v_control_lote_almacen` las referencia. |
| **2.º** | `DROP TABLE control_lote;` | Es la tabla hija ($R_2$): declara la clave foránea `responsable_control_id REFERENCES responsable_deposito(responsable_control_id)`. Debe eliminarse antes que la tabla padre. |
| **3.º** | `DROP TABLE responsable_deposito;` | Es la tabla padre ($R_1$). Una vez eliminados la vista `v_control_lote_almacen` y la tabla hija `control_lote`, ningún objeto la referencia y puede borrarse limpiamente sin `CASCADE`. |

*(Las tablas de referencia `lote`, `deposito` y `usuario` no se eliminan ni se alteran porque son entidades maestras referenciadas por `control_lote_almacen`).*

### 9.4. Verificación post-reversión (criterio de aceptación)

La reversión solo se da por válida si dentro de la misma transacción se cumplen las cuatro comprobaciones siguientes:

1. **Inexistencia de los objetos descompuestos y vigencia de la tabla original:**
   - `to_regclass('public.v_control_lote_almacen') IS NULL` (`vista_fnbc_existe = f`)
   - `to_regclass('public.control_lote') IS NULL` (`r2_control_lote_existe = f`)
   - `to_regclass('public.responsable_deposito') IS NULL` (`r1_responsable_deposito_existe = f`)
   - `to_regclass('public.control_lote_almacen') IS NOT NULL` (`tabla_original_existe = t`)
2. **Igualdad de cardinalidad:** `COUNT(*)` de `control_lote_almacen` tras revertir coincide con `COUNT(*)` de `temp_pre_reversion` (`3 = 3`).
3. **Equivalencia de conjuntos en ambas direcciones (`EXCEPT` = 0 filas):**
   - `SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen EXCEPT SELECT lote_id, deposito_id, responsable_control_id FROM temp_pre_reversion;` → **0 filas** (no aparecieron filas espurias).
   - `SELECT lote_id, deposito_id, responsable_control_id FROM temp_pre_reversion EXCEPT SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen;` → **0 filas** (no se perdió ninguna fila durante la reversión).
4. **Restricciones activas en `control_lote_almacen`:** `pg_constraint` confirma la PK `(lote_id, deposito_id)` y las 3 FK hacia `deposito(id)`, `lote(id)` y `usuario(id)`.

Script de implementación y prueba del ciclo completo (`migrar → verificar → revertir → verificar`): `food-store/tp_fnbc_reversion.sql`. Evidencia de ejecución (corrida con `ROLLBACK` y corrida con `COMMIT` en la copia `bd2_tp4u4`): `food-store/tp_fnbc_reversion_salida.txt`.

---

## Dependencia

Esta spec depende de `spec_fnbc_control_lote.md` (spec 1). No se puede ejecutar hasta que la spec 1 esté aprobada.
