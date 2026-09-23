# Declaración de Uso de IA (DUIA) — Pasaje ER→relacional y normalización

**Ejercicio:** documento de pasaje ER→relacional y normalización (dependencias
funcionales, justificación de 3FN/FNBC) del esquema de Food Store.

**Autor responsable:** Elías

**Fecha:** 23/09/2026

---

## Herramienta

Claude Code (modelo Claude Opus 5.5), en la aplicación de escritorio.

---

## Prompt y flujo de trabajo

1. Se le pasó a Claude Code el reparto de tareas del equipo y se le indicó
   cuál era la parte propia.
2. Claude Code leyó `food-store/schema.sql`, `food-store/data.sql`,
   `food-store/carga_masiva.sql`, `.kiro/steering/database.md`,
   `docs/Diagrama ER.png` y `docs/duia/duia_parte1.md`, y **propuso un plan**
   antes de escribir, como pide `AGENTS.md`.
3. El autor aprobó el plan e indicó que:
   - no hay consigna detallada, así que se sigue el plan propuesto;
   - el documento va en `docs/normalizacion_er_relacional.md`;
   - se incluye la verificación contra el motor.
4. Credenciales: Claude Code no escribió la contraseña de PostgreSQL. El autor
   creó `%APPDATA%\postgresql\pgpass.conf`, y con eso Claude Code pudo ejecutar
   el script de solo lectura sin ver la contraseña.

---

## Qué generó

- **`docs/normalizacion_er_relacional.md`**: modelo ER, reglas de pasaje a
  relacional, dependencias funcionales por tabla (incluyendo las que **no**
  existen), análisis de 1FN, 2FN, 3FN y FNBC, decisiones que parecen
  violaciones, contraejemplo de tabla sin normalizar y resultados de la
  verificación.
- **`food-store/verificacion_normalizacion.sql`**: script de solo lectura
  (`BEGIN TRANSACTION READ ONLY … ROLLBACK`) con las comprobaciones V1–V8.

---

## Errores de la IA corregidos con la verificación

La primera versión del documento y del script contenía una **predicción
equivocada**, y los datos del motor la desmintieron:

- **Qué predijo Claude Code:** leyendo `data.sql` y `carga_masiva.sql` por
  separado, supuso que ningún producto tenía dos precios distintos y que V3 iba
  a dar 0. Sobre esa base agregó un bloque V8 que **insertaba** una venta de
  prueba (con `ROLLBACK`) para fabricar el contraejemplo. También supuso que
  `bd2_trabajo` era la base de semillas.
- **Qué mostró el motor:** V3 = 2. `bd2_tp3` contiene las semillas **más** la
  carga masiva: "Pan de campo 1kg" y "Leche entera 1L" se cobraron por debajo
  del precio de lista en el pedido del 01/08/2026 de `data.sql` y a precio de
  lista en las ventas generadas. Además, `bd2_trabajo` resultó ser una copia de
  `bd2_tp3`.
- **Corrección:** se eliminó el `INSERT` de prueba (el script quedó 100 % de
  solo lectura), el nuevo V8 muestra las ventas reales que refutan
  `id_producto → precio_unitario`, y la sección 7 se reescribió con los
  resultados medidos.

Esto confirma la regla del proyecto: lo que la IA afirma sobre los datos es una
hipótesis hasta verificarlo en el motor.

---

## Verificación realizada

Ejecutado el 23/09/2026 sobre `bd2_tp3` y `bd2_trabajo` (resultados idénticos):

| # | Resultado |
|---|---|
| V1 | 14 restricciones: PK, `UNIQUE` y FK esperadas |
| V2 | Sin columna `subtotal` |
| V3 | 2 de 50.008 productos vendidos con más de un precio |
| V4 | 2 de 499.263 líneas con precio distinto al de lista |
| V5 | 0 pares repetidos |
| V6 | 19.936 clientes con más de una forma de pago; 22 fechas compartidas; 0 homónimos; 0 nombres de producto repetidos |
| V7 | 0 duplicados en `email` y `categoria.nombre` |
| V8 | Pan de campo 1kg (2200.00 vs 2500.00) y Leche entera 1L (1650.00 vs 1800.00) |

---

## Qué se aceptó, modificó o descartó

*A completar por el autor después de leer el documento línea por línea.*

| Parte | Decisión (aceptado / modificado / descartado) | Motivo |
|---|---|---|
| Secciones 1–2 (ER y pasaje) | | |
| Sección 3 (DF) | | |
| Sección 4 (formas normales) | | |
| Sección 5 (decisiones) | | |
| Sección 6 (contraejemplo) | | |
| Sección 7 y script de verificación | | |
| Descarte del `INSERT` de prueba (V8 original) | Descartado | Innecesario: los datos reales ya refutan la DF, y el script queda de solo lectura |
