# Informe de concurrencia — Parte 2

Reproducción de anomalías de concurrencia sobre el esquema del proyecto
integrador, con dos sesiones simultáneas de `psql` conectadas a la base de
trabajo `bd2_trabajo`.

**Motor:** PostgreSQL 17.11 sobre Windows 11
**Cliente:** psql, dos ventanas de Git Bash identificadas como SESION-A y SESION-B
**Fecha:** 26/08/2026

Las sesiones se identificaron en pantalla con `\set PROMPT1` para poder distinguir
cuál ejecutó cada comando en las capturas.

---

## Escenario 1 — Lectura no repetible

### Cómo se reprodujo

| Orden | Sesión | Comando |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';` |
| 3 | B | `UPDATE producto SET stock = 99 WHERE nombre = 'Agua mineral 2L';` |
| 4 | A | `SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';` |
| 5 | A | `ROLLBACK;` |

La sesión B no abrió transacción explícita: PostgreSQL aplicó autocommit y el
UPDATE quedó confirmado al terminar la sentencia. Esto se verificó porque el
`COMMIT;` posterior devolvió `WARNING: no hay una transacción en curso`.

### Qué se observó

SESION-A:

```
SESION-A=# BEGIN;
BEGIN
SESION-A=# SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';
 stock
-------
    40
(1 fila)

SESION-A=# SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';
 stock
-------
    99
(1 fila)

SESION-A=# ROLLBACK;
ROLLBACK
```

SESION-B:

```
SESION-B=# UPDATE producto SET stock = 99 WHERE nombre = 'Agua mineral 2L';
UPDATE 1
SESION-B=# COMMIT;
WARNING:  no hay una transacción en curso
COMMIT
```

La misma consulta, ejecutada dos veces dentro de la misma transacción, devolvió
40 y luego 99.

### Explicación de la IA

Herramienta consultada: Claude (Anthropic). Explicación registrada tal como fue
dada:

> El nivel de aislamiento por defecto de PostgreSQL es Read Committed. En ese
> nivel, cada sentencia dentro de una transacción ve una foto nueva de la base:
> la que refleja todo lo confirmado hasta el momento en que esa sentencia
> empieza. Por eso la segunda consulta de A ve el 99 que B ya confirmó, aunque la
> transacción de A siga abierta. La lectura no se repitió.
>
> El nivel que lo evita es Repeatable Read: ahí la transacción congela una única
> foto al inicio y todas sus consultas la usan, sin importar lo que confirmen
> otras sesiones mientras tanto.

### Verificación en el motor

Se repitió el experimento con A en `REPEATABLE READ`, mientras B modificaba el
mismo valor a 7 y confirmaba:

SESION-A:

```
SESION-A=# BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
SESION-A=# SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';
 stock
-------
    99
(1 fila)

SESION-A=# SELECT stock FROM producto WHERE nombre = 'Agua mineral 2L';
 stock
-------
    99
(1 fila)

SESION-A=# ROLLBACK;
ROLLBACK
```

SESION-B:

```
SESION-B=# BEGIN;
BEGIN
SESION-B=# UPDATE producto SET stock = 7 WHERE nombre = 'Agua mineral 2L';
UPDATE 1
SESION-B=# COMMIT;
COMMIT
```

Las dos lecturas de A devolvieron 99, pese a que B había confirmado el 7 entre
medio.

### Conclusión

La explicación de la IA **se confirmó en el motor**. Con Read Committed la
lectura cambió (40 → 99); con Repeatable Read se mantuvo estable (99 → 99). El
mecanismo que resuelve la anomalía es elevar el nivel de aislamiento a
Repeatable Read.

---

## Escenario 2 — Lectura fantasma

### Cómo se reprodujo

| Orden | Sesión | Comando |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `SELECT COUNT(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');` |
| 3 | B | `BEGIN;` |
| 4 | B | `INSERT INTO producto (...) VALUES ('Cerveza 1L', ..., categoría 'Bebidas');` |
| 5 | B | `COMMIT;` |
| 6 | A | (repite el mismo COUNT) |
| 7 | A | `ROLLBACK;` |

### Qué se observó

SESION-A:

```
SESION-A=# BEGIN;
BEGIN
SESION-A=# SELECT COUNT(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     2
(1 fila)

SESION-A=# SELECT COUNT(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     3
(1 fila)

SESION-A=# ROLLBACK;
ROLLBACK
```

SESION-B:

```
SESION-B=# BEGIN;
BEGIN
SESION-B=# INSERT INTO producto (nombre, descripcion, precio, stock, id_categoria)
VALUES ('Cerveza 1L', 'Producto agregado para probar lectura fantasma', 4500.00, 10,
    (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'));
INSERT 0 1
SESION-B=# COMMIT;
COMMIT
```

El mismo COUNT devolvió 2 y luego 3 dentro de la misma transacción.

### Explicación de la IA

> La diferencia con el escenario anterior es qué cambió: acá no se modificó una
> fila existente, apareció una fila nueva que cumple la condición del WHERE. Por
> eso se llama fantasma: no estaba cuando A empezó a contar y aparece en la
> segunda lectura.
>
> El mecanismo de fondo es el mismo que en la lectura no repetible: con Read
> Committed cada sentencia toma una foto nueva. Elevar a Repeatable Read también
> lo evita en PostgreSQL.

### Verificación en el motor

La anomalía quedó demostrada con Read Committed: el conteo pasó de 2 a 3 sin que
A hubiera cerrado su transacción.

### Conclusión

La explicación de la IA se confirmó en cuanto a la reproducción del fenómeno. El
conteo cambió dentro de una misma transacción por la inserción confirmada de otra
sesión.

**Observación adicional registrada:** la IA mencionó que en PostgreSQL el nivel
Repeatable Read también evita las lecturas fantasma. Este punto **no se verificó
experimentalmente en este trabajo**, a diferencia del escenario 1, donde sí se
repitió la prueba con el nivel elevado. Se deja constancia de la afirmación sin
darla por confirmada, ya que el criterio de la cátedra es que vale lo que
confirma el motor, no lo que dice el modelo. Es un punto pendiente de
verificación.

---

## Escenario 3 — Espera por bloqueo

### Cómo se reprodujo

| Orden | Sesión | Comando |
|---|---|---|
| 1 | B | `\timing on` |
| 2 | A | `BEGIN;` |
| 3 | A | `SELECT stock FROM producto WHERE nombre = 'Gaseosa cola 2.25L' FOR UPDATE;` |
| 4 | B | `BEGIN;` |
| 5 | B | `SELECT stock FROM producto WHERE nombre = 'Gaseosa cola 2.25L' FOR UPDATE;` → **queda esperando** |
| 6 | A | `COMMIT;` |
| 7 | B | (se destraba y devuelve el resultado) |
| 8 | B | `ROLLBACK;` |

Se activó `\timing on` en la sesión B porque la espera no deja ninguna marca en
el resultado de la consulta: el valor devuelto es el mismo que se obtendría sin
bloqueo. La única evidencia observable es el tiempo transcurrido.

### Qué se observó

SESION-A:

```
SESION-A=# BEGIN;
BEGIN
SESION-A=# SELECT stock FROM producto WHERE nombre = 'Gaseosa cola 2.25L' FOR UPDATE;
 stock
-------
     1
(1 fila)

SESION-A=# COMMIT;
COMMIT
```

SESION-B:

```
SESION-B=# \timing on
El despliegue de duración está activado.
SESION-B=# BEGIN;
BEGIN
Duración: 0,316 ms
SESION-B=# SELECT stock FROM producto WHERE nombre = 'Gaseosa cola 2.25L' FOR UPDATE;
 stock
-------
     1
(1 fila)

Duración: 31170,470 ms (00:31,170)
```

El `BEGIN;` tardó 0,316 ms. El `SELECT ... FOR UPDATE` tardó 31.170 ms — más de
31 segundos — para devolver una única fila con un único valor entero. La
diferencia no se explica por el costo de la consulta sino por el tiempo que la
sesión estuvo bloqueada esperando que A confirmara.

### Explicación de la IA

> `FOR UPDATE` no solo lee la fila: la bloquea. Le dice al motor que esa fila
> queda reservada hasta que la transacción termine. Cuando B pide el mismo
> bloqueo sobre la misma fila, el motor no le devuelve un error ni le da una
> versión vieja: la pone a esperar. B se destraba en el instante en que A hace
> COMMIT o ROLLBACK.
>
> Esto es lo que evita que dos sesiones lean el mismo stock y vendan las dos. Sin
> `FOR UPDATE`, ambas leen 1, ambas validan que alcanza, y ambas confirman.

### Verificación en el motor

Confirmada por el tiempo medido: 31.170,470 ms de espera frente a 0,316 ms de una
operación no bloqueada en la misma sesión. La sesión B permaneció detenida sin
devolver resultado ni error hasta que A ejecutó `COMMIT`, momento en el cual
retomó y devolvió el valor.

### Conclusión

La explicación de la IA **se confirmó en el motor**. El mecanismo que resuelve el
problema de dos sesiones compitiendo por la misma fila es el bloqueo explícito
con `SELECT ... FOR UPDATE`, que serializa el acceso: la segunda sesión espera en
lugar de operar sobre un valor que la primera está por modificar.

---

## Conexión con la Parte 1 de este trabajo práctico

El escenario 3 no es un ejercicio abstracto: expone una limitación concreta de las
restricciones implementadas en la Parte 1.

La función `fn_verificar_stock_suficiente()`, en `sql/restricciones.sql`, lee el
stock así:

```sql
SELECT stock INTO v_stock
  FROM producto
 WHERE id_producto = NEW.id_producto;
```

Es un `SELECT` sin `FOR UPDATE`. Aplicando lo verificado en el escenario 3, dos
sesiones concurrentes que intenten vender el mismo producto pueden leer ambas el
mismo valor de stock, pasar ambas la validación del trigger y confirmar ambas,
dejando el producto vendido por encima de las existencias. El trigger valida
correctamente de forma aislada, pero no bajo concurrencia.

La corrección sería cambiar esa lectura por:

```sql
SELECT stock INTO v_stock
  FROM producto
 WHERE id_producto = NEW.id_producto
 FOR UPDATE;
```

Esto no se aplicó en la Parte 1 porque el alcance definido en `spec_restricciones.md`
era la validación por línea, no el control de concurrencia. Queda documentado como
limitación conocida en `duia/duia_parte1.md` y verificado experimentalmente en
este informe.