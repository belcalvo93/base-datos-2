# Concurrencia — TP5 · TPI, objetivo 8

Scripts reproducibles de concurrencia sobre el esquema de Food Store.
Cumplen el objetivo 8 del TPI: *"Transacciones: atomicidad, COMMIT,
ROLLBACK, niveles de aislamiento y control de concurrencia"*.

Los fenómenos ya estaban documentados y verificados contra el motor en
`docs/informe_concurrencia.md` y `docs/verificacion_fantasmas_repeatable_read.md`.
Acá se los convierte en scripts ejecutables, con el mismo método: dos
sesiones contra la misma base y pasos en orden.

---

## 1. Base de reproducción

Los escenarios corren sobre `bd2_trabajo` (la copia de trabajo desechable)
con el seed chico. Se recrea antes de cada corrida como indica el
`protocolo_seguridad.md`; al ser desechable, no requiere backup:

```bash
dropdb -U postgres bd2_trabajo
createdb -U postgres bd2_trabajo
psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/schema.sql
psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/data.sql
psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/restricciones.sql
```

## 2. Cómo ejecutarlos

- **Dos conexiones** a `bd2_trabajo`: dos ventanas de `psql` (Git Bash) o dos
  editors SQL de DBeaver sobre la misma conexión.
- **Ejecutar sentencia por sentencia**, no el archivo completo: los pasos
  alternan entre sesiones. Las líneas `-- ESPERAR <paso>` indican dónde hay
  que pausar hasta que la otra sesión haga su paso.
- En `psql` conviene `\timing on` en el escenario 3 (la espera solo se
  evidencia en el tiempo). En DBeaver el tiempo aparece al pie de cada
  resultado.
- Leer cada script antes de ejecutarlo (protocolo de seguridad).

## 3. Escenarios y orquestación

### Escenario 0 — Atomicidad, COMMIT y ROLLBACK (`escenario0_atomicidad.sql`)

Una sola sesión. Tres partes:
- **A** — dos cambios (INSERT en `detalle_pedido` + UPDATE de stock) y
  `ROLLBACK`: no queda nada (se revierten juntos).
- **B** — los mismos cambios y `COMMIT`: quedan aplicados; el script deja la
  base como estaba al final (elimina la fila de prueba y restaura el stock).
- **C** — fallo parcial: un `UPDATE` válido seguido de un `INSERT` que dispara
  el trigger de stock insuficiente: el ERROR aborta toda la transacción y el
  `UPDATE` también se revierte.

Cubre: atomicidad, `COMMIT`, `ROLLBACK`.

### Escenario 1 — Lectura no repetible (`escenario1_..._sesionA.sql` / `_sesionB.sql`)

Producto `'Agua mineral 2L'` (stock 40 en el seed, según `food-store/data.sql`).

| Orden | Sesión | Comando | Resultado esperado |
|---|---|---|---|
| Fase 1 — READ COMMITTED | | | |
| A1 | A | `BEGIN;` y `SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';` | 40 |
| B1 | B | `UPDATE producto SET stock = 99 WHERE nombre = 'Agua mineral 2L';` | `UPDATE 1` |
| A2 | A | repetir el `SELECT` | **99** (la lectura no se repitió) |
| A3 | A | `ROLLBACK;` | |
| B2 | B | `UPDATE ... SET stock = 40 ...` (restaurar) | `UPDATE 1` |
| Fase 2 — REPEATABLE READ | | | |
| A4 | A | `BEGIN ISOLATION LEVEL REPEATABLE READ;` y `SELECT stock ...` | 40 |
| B3 | B | `UPDATE producto SET stock = 7 ...` | `UPDATE 1` |
| A5 | A | repetir el `SELECT` | **40** (la foto no cambia) |
| A6 | A | `ROLLBACK;` | |
| B4 | B | `UPDATE ... SET stock = 40 ...` (restaurar) | `UPDATE 1` |

Cubre: niveles de aislamiento (READ COMMITTED vs REPEATABLE READ).

### Escenario 2 — Lectura fantasma (`escenario2_..._sesionA.sql` / `_sesionB.sql`)

Categoría Bebidas (2 productos activos en el seed).

| Orden | Sesión | Comando | Resultado esperado |
|---|---|---|---|
| Fase 1 — READ COMMITTED | | | |
| A1 | A | `BEGIN;` y `SELECT COUNT(*) FROM producto WHERE id_categoria = 'Bebidas'...` | 2 |
| B1 | B | `INSERT INTO producto ... ('Cerveza 1L', 'Bebidas')` | `INSERT 0 1` |
| A2 | A | repetir el `COUNT` | **3** (el fantasma aparece) |
| A3 | A | `ROLLBACK;` | |
| B2 | B | `DELETE FROM producto WHERE nombre = 'Cerveza 1L';` (limpieza) | `DELETE 1` |
| Fase 2 — REPEATABLE READ | | | |
| A4 | A | `BEGIN ISOLATION LEVEL REPEATABLE READ;` y `COUNT` | 2 |
| B3 | B | `INSERT ... ('Agua saborizada 1.5L', 'Bebidas')` | `INSERT 0 1` |
| A5 | A | repetir el `COUNT` | **2** (la foto no incorpora filas nuevas) |
| A6 | A | `COMMIT;` y `COUNT` fuera de la transacción | 3 (la fila estaba confirmada) |
| B4 | B | `DELETE ... WHERE nombre = 'Agua saborizada 1.5L';` (limpieza) | `DELETE 1` |

Cubre: niveles de aislamiento (fantasma en RC, ausente en RR, como verificó
`docs/verificacion_fantasmas_repeatable_read.md`).

### Escenario 3 — Control de concurrencia: espera por bloqueo (`escenario3_...`)

Producto `'Gaseosa cola 2.25L'` (stock 1). Las dos sesiones piden el mismo
`SELECT ... FOR UPDATE` sobre la misma fila.

| Orden | Sesión | Comando | Resultado esperado |
|---|---|---|---|
| A1 | A | `BEGIN;` | |
| A2 | A | `SELECT stock FROM producto WHERE nombre = 'Gaseosa cola 2.25L' FOR UPDATE;` | 1 (A bloquea la fila) |
| B1 | B | `BEGIN;` y `SELECT ... FOR UPDATE;` | **queda esperando** |
| A3 | A | `COMMIT;` | A libera la fila |
| B2 | B | (ya destrabada) | devuelve 1, tras ~30 s |
| B3 | B | `ROLLBACK;` | |

La única evidencia del bloqueo es el tiempo: la misma consulta tardó 0,316 ms
sin bloqueo y 31.170 ms en el informe original. En `psql`, `\timing on`.

Cubre: control de concurrencia con `SELECT ... FOR UPDATE` (nadie vende dos
veces el mismo stock).

---

## 4. Mapeo al objetivo 8 del TPI

| Elemento pedido | Escenario |
|---|---|
| Atomicidad | 0 (A y C) |
| `COMMIT` / `ROLLBACK` | 0 (A y B) |
| Niveles de aislamiento | 1 y 2 (README COMMITTED vs REPEATABLE READ) |
| Control de concurrencia | 3 (`FOR UPDATE`, espera por bloqueo) |

## 5. Enlaces

- `docs/informe_concurrencia.md` — informe de la Parte 2 con los tres
  escenarios y la limitación conocida del trigger de stock (lectura sin
  `FOR UPDATE`).
- `docs/verificacion_fantasmas_repeatable_read.md` — verificación del
  fantasma en READ COMMITTED y su ausencia en REPEATABLE READ.
- `food-store/restricciones.sql` — triggers de validación sobre
  `detalle_pedido` (Reglas 1 y 2).