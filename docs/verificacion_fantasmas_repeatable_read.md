# Verificación experimental — Repeatable Read y lecturas fantasma

## 1. Por qué se hace esta prueba

El informe de concurrencia del TP2 dejó un punto abierto: se documentó que en PostgreSQL el nivel
Repeatable Read debería evitar también las lecturas fantasma, pero eso no se verificó contra el motor.
Quedó como una afirmación tomada de la documentación, no como un resultado medido.

Este documento cierra ese punto.

La discrepancia que se quiere resolver es concreta. El estándar SQL establece que Repeatable Read previene
lecturas sucias y no repetibles, pero **permite** lecturas fantasma, y que para eliminarlas hace falta
Serializable. PostgreSQL implementa Repeatable Read con snapshot isolation: la transacción trabaja sobre
una foto tomada al inicio, y esa foto tampoco incorpora filas nuevas. Si eso es así, los fantasmas ya
quedan bloqueados un nivel antes de lo que dice el estándar. Repetir el manual no alcanza: hay que medirlo.

## 2. Entorno y método

- PostgreSQL 17.11.
- Base `bd2_trabajo`, recreada desde cero con `food-store/schema.sql`, `food-store/data.sql` y
  `food-store/restricciones.sql`. Cinco categorías, once productos.
- Dos sesiones de `psql` simultáneas contra la misma base, llamadas A y B.
- No se usó la base masiva: el volumen no cambia el fenómeno. Una lectura fantasma se demuestra con dos
  filas igual que con cincuenta mil, y con pocos datos el conteo se lee de un vistazo.

La consulta de prueba cuenta los productos de la categoría Bebidas, que en el seed tiene dos:

```sql
SELECT count(*) FROM producto
WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
```

El experimento se corre dos veces con la misma secuencia, cambiando únicamente el nivel de aislamiento de
la sesión A. Que lo único que cambie sea el nivel es lo que permite atribuirle a él la diferencia.

## 3. Fase 1 — Read Committed: el fantasma aparece

Sesión A abre la transacción en el nivel por defecto y cuenta:

```
bd2_trabajo=# BEGIN;
BEGIN
bd2_trabajo=*# SELECT count(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     2
(1 fila)
```

Sesión B inserta un producto nuevo en esa categoría y lo confirma, mientras la transacción de A sigue
abierta:

```
bd2_trabajo=# INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria) VALUES ('Jugo naranja 1L', 'Jugo exprimido', 2200.00, 18, TRUE, (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'));
INSERT 0 1
```

Sesión A repite la misma consulta, sin haber cerrado la transacción:

```
bd2_trabajo=*# SELECT count(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     3
(1 fila)

bd2_trabajo=*# COMMIT;
COMMIT
```

El conteo pasó de 2 a 3 dentro de la misma transacción. Apareció una fila que antes no estaba, que es la
definición de lectura fantasma. En Read Committed cada sentencia toma una foto nueva al momento de
ejecutarse, así que la segunda consulta ve lo que B confirmó en el medio.

## 4. Fase 2 — Repeatable Read: el fantasma no aparece

Misma secuencia, cambiando solo el nivel de aislamiento de A.

```
bd2_trabajo=# BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
bd2_trabajo=*# SELECT count(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     3
(1 fila)
```

Sesión B inserta un segundo producto y lo confirma:

```
bd2_trabajo=# INSERT INTO producto (nombre, descripcion, precio, stock, activo, id_categoria) VALUES ('Agua saborizada 1.5L', 'Agua saborizada pomelo', 2600.00, 22, TRUE, (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'));
INSERT 0 1
```

Sesión A repite la consulta:

```
bd2_trabajo=*# SELECT count(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     3
(1 fila)
```

Sigue en 3. El fantasma no apareció.

Falta un paso para que la prueba sea concluyente. Que el conteo no cambie podría explicarse también porque
el INSERT de B nunca se confirmó. Para descartarlo, A cierra la transacción y vuelve a contar:

```
bd2_trabajo=*# COMMIT;
COMMIT
bd2_trabajo=# SELECT count(*) FROM producto WHERE id_categoria = (SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas');
 count
-------
     4
(1 fila)
```

Fuera de la transacción el conteo es 4. La fila estaba confirmada todo el tiempo: Repeatable Read la estaba
ocultando a propósito, sosteniendo la foto tomada al inicio, no ignorando el cambio.

## 5. Resultado

| Nivel de aislamiento de A | Conteo inicial | B inserta y confirma | Conteo posterior | ¿Fantasma? |
|---|---:|---|---:|---|
| Read Committed | 2 | `INSERT 0 1` | 3 | Sí |
| Repeatable Read | 3 | `INSERT 0 1` | 3 | No |
| Fuera de transacción | — | — | 4 | — |

Queda verificado contra el motor lo que el informe del TP2 afirmaba sin comprobar: **en PostgreSQL no hace
falta Serializable para evitar lecturas fantasma, alcanza con Repeatable Read.** El comportamiento
contradice al estándar SQL, y la causa es que la implementación usa snapshot isolation en lugar del bloqueo
de rangos que el estándar tiene en mente.

## 6. Lo que esta prueba no demuestra

Que Repeatable Read bloquee los fantasmas no vuelve inútil a Serializable. Queda fuera del alcance de este
experimento la anomalía que sí separa a los dos niveles en PostgreSQL, el **write skew**: dos transacciones
leen el mismo estado, cada una toma por separado una decisión válida contra esa foto, y el resultado
combinado deja la base en un estado que ninguna de las dos habría permitido. Snapshot isolation no lo
evita, porque ninguna de las dos escribe sobre lo que la otra leyó. Serializable sí.

Verificarlo requiere otro montaje y no se hizo acá.

## 7. Cómo reproducirlo

1. Crear la base y cargarla:
   ```bash
   createdb -U postgres bd2_trabajo
   psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/schema.sql
   psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/data.sql
   psql -U postgres -d bd2_trabajo -v ON_ERROR_STOP=1 -f food-store/restricciones.sql
   ```
2. Abrir dos terminales y conectar ambas con `psql -U postgres -d bd2_trabajo`.
3. Seguir las secuencias de las secciones 3 y 4, respetando el orden entre sesiones.

El prompt de psql avisa en qué estado está cada sesión: `bd2_trabajo=#` sin transacción abierta y
`bd2_trabajo=*#` con una transacción en curso.
