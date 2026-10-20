# Informe TP U4 — FNBC y desnormalización controlada en Food Store

## Datos del trabajo

Trabajo práctico de la Unidad 4 de Base de Datos II (Tecnicatura Universitaria en Programación, UTN), sobre el proyecto Food Store, con el profesor Sergio Neira.

| Dato | Detalle |
| --- | --- |
| Grupo | Belén Calvo, Hernán González, Elías Tello y Bruno Fiouchetta |
| Repositorio | [belcalvo93/base-datos-2](https://github.com/belcalvo93/base-datos-2) |
| Base de trabajo | `bd2_tp4u4`, copia de `bd2_tp3` (PostgreSQL 17) |
| Scripts entregados | `food-store/tp_fnbc_control_lote.sql` y `food-store/tp_desnormalizacion_top_categorias.sql` |
| Herramientas | Kiro (specs), OpenCode (SQL), Claude Code (revisión y mediciones), PostgreSQL y Git Bash |

## Parte 1 — FNBC de `control_lote_almacen` (puntos a–d)

`control_lote_almacen` está en 3FN pero **no en FNBC**: la dependencia ResponsableControlID → DepositoID tiene un determinante que no es superclave. Todo lo que sigue se demuestra con `food-store/tp_fnbc_control_lote.sql`, ejecutado sobre `bd2_tp4u4`, que termina en `ROLLBACK`.

Esquema: R(LoteID, DepositoID, ResponsableControlID). Instancia de la consigna: (501, 30, 801), (502, 30, 801), (503, 31, 802).

### a) Dependencias funcionales

- **F1:** {LoteID, DepositoID} → ResponsableControlID. Primera regla de negocio: para un lote y un depósito dados, el responsable queda determinado. La garantiza la clave primaria.
- **F2:** ResponsableControlID → DepositoID. Segunda regla: cada responsable pertenece a un único depósito.

*Artefacto (bloque a del script):* `pg_get_constraintdef` muestra la PK `(lote_id, deposito_id)` y las tres FK. F2 no está declarada como restricción, por eso el motor no la hace cumplir. La consulta de verificación (`GROUP BY responsable_control_id HAVING COUNT(DISTINCT deposito_id) > 1`) devuelve **0 filas**: no hay contraejemplo en la instancia. Los datos pueden refutar una DF, pero no demostrarla para toda extensión posible.

### b) Clausuras y claves candidatas

| Conjunto X | Clausura X⁺ | ¿Superclave? |
| --- | --- | --- |
| {LoteID, DepositoID} | {LoteID, DepositoID, ResponsableControlID}, por F1 | Sí, clave candidata |
| {LoteID, ResponsableControlID} | {LoteID, ResponsableControlID, DepositoID}, por F2 | Sí, clave candidata |
| {ResponsableControlID} | {ResponsableControlID, DepositoID}, por F2 | No |
| {LoteID} | {LoteID} | No |
| {DepositoID} | {DepositoID} | No |
| {DepositoID, ResponsableControlID} | {DepositoID, ResponsableControlID}; F1 necesita LoteID | No |

Claves candidatas: {LoteID, DepositoID} y {LoteID, ResponsableControlID}. Atributos primos: los tres. No primos: ninguno.

### c) Determinación de FNBC

Definición: R está en FNBC si, para toda dependencia no trivial X → A, X es superclave de R.

- **F1:** el determinante {LoteID, DepositoID} es clave candidata. Cumple.
- **F2:** el determinante ResponsableControlID tiene clausura {ResponsableControlID, DepositoID}, distinta de R. **No es superclave: F2 viola la FNBC.**

La relación sí cumple 3FN, porque DepositoID es atributo primo. Por eso la 3FN no lo detecta y la FNBC sí.

### d) Anomalías

Hay redundancia: el hecho "801 pertenece al depósito 30" se guarda dos veces, en los lotes 501 y 502. Cada anomalía se probó en el script con `SAVEPOINT` y se deshizo.

| Anomalía | Escenario | Qué pasa | Evidencia en el script |
| --- | --- | --- | --- |
| Inserción | Registrar (501, 31, 801) | La PK está libre y las FK son válidas: el motor lo acepta y 801 queda en dos depósitos (30 y 31), contra la regla. Nada en la tabla lo impide. | Bloque d.1: la consulta de verificación pasa de 0 filas a 1 (responsable 801) |
| Borrado | Eliminar (503, 31, 802), el único control de 802 | Se pierde que 802 pertenece al depósito 31: no está en ninguna otra fila. | Bloque d.2: la tabla pasa de 3 filas a 2 y 802 desaparece |
| Actualización | Mover a 801 al depósito 31 cambiando solo (501, 30, 801) | 801 queda en los depósitos 30 y 31 a la vez. Para moverlo hay que actualizar todas sus filas. | Bloque d.3: la consulta de verificación devuelve 801 |

La descomposición que corrige esto se desarrolla en los puntos e y f, en la sección siguiente.

## Parte 1 — Descomposición sin pérdida (puntos e–f)

### e) Descomposición en FNBC

A partir de la dependencia que violaba FNBC (**F2:** ResponsableControlID → DepositoID), se descompone `control_lote_almacen` en dos relaciones:

| Relación | Tabla SQL | Esquema y restricciones | ¿Cumple FNBC? |
| --- | --- | --- | --- |
| **R₁** | `responsable_deposito` | `(responsable_control_id PK, deposito_id)` con FK a `usuario(id)` y `deposito(id)` | **Sí:** la única DF no trivial es F2 y su determinante (`responsable_control_id`) es la clave primaria (superclave de R₁). |
| **R₂** | `control_lote` | `(lote_id, responsable_control_id)` con PK compuesta y FK a `lote(id)` y `responsable_deposito(responsable_control_id)` | **Sí:** no tiene DFs no triviales propias; su única clave candidata es la tupla completa `{lote_id, responsable_control_id}`. |

- **Unión sin pérdida (Teorema de Heath):** el atributo común entre ambas relaciones es $R_1 \cap R_2 = \{\text{responsable\_control\_id}\}$. Como en $R_1$ se cumple $\text{responsable\_control\_id} \rightarrow \text{deposito\_id}$, el atributo común es **superclave de $R_1$**, lo que garantiza que $R_1 \bowtie R_2$ reconstruye exactamente la relación original sin generar tuplas espurias ni perder información.
- **Preservación de dependencias funcionales:** **F2** queda impuesta estructuralmente por la PK de `responsable_deposito` (lo que elimina las tres anomalías del punto d). En cambio, **F1** ($\{\text{LoteID}, \text{DepositoID}\} \rightarrow \text{ResponsableControlID}$) **no se preserva** en una sola tabla, porque `lote_id` quedó en `control_lote` y `deposito_id` en `responsable_deposito`. Este es el *trade-off* clásico al pasar de 3FN a FNBC: validar F1 requeriría un *join* entre ambas tablas.

### f) Migración, vista de compatibilidad y verificación con `EXCEPT`

En la segunda mitad de `food-store/tp_fnbc_control_lote.sql` se migran los datos desde `control_lote_almacen` y se crea la vista de compatibilidad mediante `NATURAL JOIN` (cuya única columna homónima es `responsable_control_id`):

- **`responsable_deposito` (R₁):** recibe `SELECT DISTINCT responsable_control_id, deposito_id FROM control_lote_almacen` → **2 filas** (`(801, 30)` y `(802, 31)`), eliminando la repetición del depósito 30 para el responsable 801.
- **`control_lote` (R₂):** recibe `SELECT lote_id, responsable_control_id FROM control_lote_almacen` → **3 filas** (`(501, 801)`, `(502, 801)` y `(503, 802)`).
- **Vista `v_control_lote_almacen`:** `SELECT lote_id, deposito_id, responsable_control_id FROM control_lote NATURAL JOIN responsable_deposito` → reconstruye las **3 filas** originales (`(501, 30, 801)`, `(502, 30, 801)`, `(503, 31, 802)`).
- **Verificación de equivalencia de conjuntos ($R = V \iff R \setminus V = \emptyset \land V \setminus R = \emptyset$):**
  1. `SELECT ... FROM control_lote_almacen EXCEPT SELECT ... FROM v_control_lote_almacen` → **0 filas** (no se perdieron tuplas).
  2. `SELECT ... FROM v_control_lote_almacen EXCEPT SELECT ... FROM control_lote_almacen` → **0 filas** (no aparecieron tuplas espurias).

## Parte 2 a — Consulta y medición antes

*Pendiente: Elías.*

## Parte 2 b — Patrón de desnormalización elegido

*Pendiente: Elías.*

## Parte 2 c–e — Implementación, antes/después y auditoría

*Pendiente: Bruno.*

## Uso de IA

*Pendiente. El registro completo está en `docs/duia/duia_tp_u4.md`.*
