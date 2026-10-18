# Spec: FNBC - Control de Lote

**Responsable**: Belén  
**Fecha de creación**: 2026-10-18  
**Última revisión**: 2026-10-18 — Esquema alineado con la consigna (lote/deposito con BIGINT, control_lote_almacen con PK compuesta (lote_id, deposito_id), sin `id` ni `cantidad`); instancia de ejemplo ajustada; corregido el supuesto del dominio (cada responsable pertenece a un único depósito)

---

## 1. Objetivo

Crear el esquema inicial de la Parte 1 del TP U4 y demostrar mediante artefactos SQL que la tabla `control_lote_almacen` viola la Forma Normal de Boyce-Codd (FNBC).

---

## 2. Consulta

### 2.1. Estructura de tablas necesarias

```sql
-- Tabla lote (mínima, según decisión tomada)
CREATE TABLE IF NOT EXISTS lote (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL
);

-- Tabla deposito (mínima, según decisión tomada)
CREATE TABLE IF NOT EXISTS deposito (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL
);

-- Tabla control_lote_almacen (esquema exacto de la consigna)
CREATE TABLE IF NOT EXISTS control_lote_almacen (
    lote_id BIGINT NOT NULL REFERENCES lote(id),
    deposito_id BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);
```

### 2.2. Instancia de ejemplo (según consigna)

```sql
INSERT INTO lote (id, nombre) VALUES 
(501, 'Lote A'), (502, 'Lote B'), (503, 'Lote C');

INSERT INTO deposito (id, nombre) VALUES 
(30, 'Depósito Centro'), (31, 'Depósito Norte');

-- Usuarios 801 y 802 (con OVERRIDING SYSTEM VALUE por ser IDENTITY ALWAYS)
INSERT INTO usuario (id, nombre, apellido, mail, contrasena, rol, eliminado)
OVERRIDING SYSTEM VALUE
VALUES 
(801, 'Usuario', 'Admin', 'admin801@test.com', 'hash801', 'ADMIN', FALSE),
(802, 'Usuario', 'Supervisor', 'supervisor802@test.com', 'hash802', 'USUARIO', FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO control_lote_almacen VALUES (501, 30, 801), (502, 30, 801), (503, 31, 802);
```

---

## 3. Frecuencia y carga

- **Frecuencia**: operación manual de control de stock, pocas veces al día.
- **Carga**: ~3-10 registros en la instancia de ejemplo.
- Regla de negocio (consigna): cada responsable pertenece a un único depósito, por lo que la DF `responsable_control_id → deposito_id` se cumple.

---

## 4. Columnas relevantes

| Rol | Columna | Tabla |
|-----|---------|-------|
| PK (compuesta) + FK | `lote_id` | lote |
| PK (compuesta) + FK | `deposito_id` | deposito |
| FK | `responsable_control_id` | usuario |

---

## 5. Estado actual medido

No aplica (es estructura nueva).

---

## 6. Hipótesis para OpenCode

### 6.1. Lo que se pide

1. **Verificación de la DF `responsable_control_id → deposito_id`**:
   - Una consulta que agrupe por `responsable_control_id` y cuente los `deposito_id` distintos:
   ```sql
   SELECT responsable_control_id
   FROM control_lote_almacen
   GROUP BY responsable_control_id
   HAVING COUNT(DISTINCT deposito_id) > 1;
   ```
   - Debe devolver 0 filas (la DF se cumple en esta instancia).

2. **Demostración de anomalías** (en `BEGIN; … ROLLBACK;`):
   - **Inserción**: intentar insertar un registro que violated la DF (mismo responsable, deposito diferente al habitual).
   - **Borrado**: borrar un registro y perder información del responsable.
   - **Actualización**: actualizar el `responsable_control_id` y generar inconsistencia.

3. **Script completo idempotente** para `food-store/tp_fnbc_control_lote.sql` (primera mitad).

### 6.2. Lo que NO se puede hacer sin justificar

- Modificar la estructura de las tablas (agregar constraints que cambien el esquema de la consigna).
- Eliminar datos existentes de lote, deposito o usuario.
- Cambiar los IDs asignados (501, 502, 503 para lote; 30, 31 para deposito; 801, 802 para usuario).

---

## 7. Criterio de aceptación

### 7.1. Condiciones medibles

- El script corre sin errores (`psql -1` con `ON_ERROR_STOP` o equivalente).
- La verificación de DF devuelve 0 filas.
- Las tres anomalías se demuestran correctamente en BEGIN/ROLLBACK.

### 7.2. Salida de descarte

Si el script no corre limpio, o las anomalías no se demuestran, se descarta y se documenta el motivo.

---

## 8. Resultado de la medición

*Pendiente de medición.*  
*Fecha: —*  
*Estado: —*