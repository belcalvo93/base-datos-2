# Spec: FNBC - Descomposición sin pérdida

**Responsable**: Hernán  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-18 — Corregido: migración y verificación en BEGIN/ROLLBACK

---

## 1. Objetivo

Descomponer la tabla `control_lote_almacen` en dos tablas que cumplan FNBC, mantener la equivalencia mediante una vista con NATURAL JOIN, y verificar que no hay pérdida de información.

---

## 2. Consulta

### 2.1. Tablas resultantes

Según el análisis de dependencias funcionales:

- **Depósito del responsable** (`responsable_deposito`):
  - PK: `(responsable_control_id, deposito_id)`
  - FK: `deposito_id → deposito(id)`

- **Control de lote** (`control_lote`):
  - PK: `(lote_id, deposito_id, responsable_control_id)`
  - FKs: `lote_id → lote(id)`, `deposito_id → deposito(id)`

### 2.2. Justificación de la descomposición

La DF `(lote_id, deposito_id) → responsable_control_id` NO se preserva en la descomposición. Esto debe documentarse en el informe.

El atributo común `deposito_id` es superclave de `responsable_deposito`, lo que garantiza la unión sin pérdida.

---

## 3. Frecuencia y carga

- **Frecuencia**: igual que la spec 1 (operación manual).
- **Carga**: ~3-10 registros heredados de la instancia anterior.

---

## 4. Columnas relevantes

| Tabla | Columnas |
|-------|----------|
| `responsable_deposito` | responsable_control_id (PK), deposito_id (PK) |
| `control_lote` | lote_id (PK), deposito_id (PK), responsable_control_id (PK), cantidad |

---

## 5. Estado actual medido

No aplica (depende de spec 1).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Crear las dos tablas** con PKs compuestas y FKs correspondientes.
2. **Crear una vista de compatibilidad**:
   ```sql
   CREATE OR REPLACE VIEW v_control_lote_almacen AS
   SELECT cl.lote_id, cl.deposito_id, cl.responsable_control_id, cl.cantidad
   FROM control_lote cl
   NATURAL JOIN responsable_deposito rd;
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

*Pendiente de medición.*  
*Fecha: —*  
*Estado: —*

---

## Dependencia

Esta spec depende de `spec_fnbc_control_lote.md` (spec 1). No se puede ejecutar hasta que la spec 1 esté aprobada.