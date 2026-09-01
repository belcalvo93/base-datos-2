# Ejercicio de lectura crítica — Parte 3

Análisis de dos scripts supuestamente generados para «dar de baja registros
vencidos» sobre el esquema genérico de cátedra. Ambos se leen antes de
ejecutarse, según el protocolo de seguridad definido en la Parte 0.

---

## Script 1

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

### Qué filas afecta realmente

El UPDATE no posee una cláusula WHERE, por lo que afecta a **todas** las filas de
la tabla `funcion`. En consecuencia, establece `activa = FALSE` para todas las
funciones, incluyendo aquellas que no fueron retiradas de cartel.

### Por qué no coincide con la consigna

La consigna dice dar de baja únicamente las funciones retiradas de cartel. El
script no filtra nada: da de baja la cartelera completa. El error es que no se
está acotando la operación a las funciones que deben darse de baja.

Nota importante: el script **no produce ningún error**. Se ejecuta con éxito y
PostgreSQL informa la cantidad de filas actualizadas. Solo leyendo el script
antes de ejecutarlo se detecta que esa cantidad es la tabla entera.

### Versión corregida

```sql
-- Corregido: solo las funciones cuya fecha ya pasó
UPDATE funcion
SET activa = FALSE
WHERE fecha_hora < now();
```

Se asume la existencia de una columna `fecha_hora` que identifica cuándo se
proyecta cada función. El criterio exacto depende del esquema real de cátedra;
lo esencial de la corrección es que exista un WHERE que acote las filas
afectadas al subconjunto que la consigna describe.

---

## Script 2

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### Qué filas afecta realmente

El problema está en el uso de `NOT IN` cuando la subconsulta puede devolver
valores NULL, lo que ocurre si `producto.categoria_id` admite nulos.

Si la subconsulta devuelve, por ejemplo, `1, 3, NULL, 5`, para decidir si borra la
categoría 7 el motor debe evaluar si 7 es distinto de cada elemento de esa lista.
La comparación contra NULL no devuelve verdadero ni falso, sino *desconocido*,
porque NULL representa un valor no conocido. Como `NOT IN` exige que todas las
comparaciones sean verdaderas, la condición nunca llega a cumplirse.

El resultado no es un riesgo eventual: **si hay al menos un NULL en la
subconsulta, el DELETE no elimina ninguna fila**.

### Por qué no coincide con la consigna

La consigna dice limpiar las categorías sin productos asociados. Tal como está
escrito, y en presencia de un solo NULL, el script no limpia nada. Al igual que
el Script 1, no produce ningún error: se ejecuta correctamente e informa
`DELETE 0`. El script falla en silencio.

Los dos scripts fallan en direcciones opuestas: el primero hace de más (afecta
toda la tabla), el segundo hace de menos (no afecta ninguna fila). Ninguno de los
dos avisa. Ese es exactamente el motivo por el que el protocolo obliga a leer
antes de ejecutar.

### Versión corregida

Con `NOT EXISTS`, que verifica directamente si existe algún producto asociado a
cada categoría, sin construir una lista que pueda contener NULL:

```sql
-- Corregido: NOT EXISTS es inmune al problema del NULL
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 FROM producto p
    WHERE p.categoria_id = c.id
);
```

También sería válido filtrar los nulos dentro de la subconsulta:

```sql
DELETE FROM categoria
WHERE id NOT IN (
    SELECT categoria_id FROM producto
    WHERE categoria_id IS NOT NULL
);
```

Se prefiere `NOT EXISTS` porque resuelve el problema por diseño y no por un
filtro agregado: si en el futuro alguien quita el `IS NOT NULL`, la segunda
versión vuelve a fallar en silencio.

### Observación adicional sobre el diseño

Más allá del problema del NULL, el script utiliza `DELETE`, lo que implica un
borrado físico de las categorías. Esto contradice el diseño del proyecto
integrador, que aplica baja lógica mediante la columna `activo` y protege las
categorías con `ON DELETE RESTRICT` en la clave foránea de `producto`.

Bajo esas convenciones, la operación correcta no sería un DELETE sino:

```sql
-- Baja lógica, coherente con el patrón del proyecto
UPDATE categoria c
SET activo = FALSE
WHERE NOT EXISTS (
    SELECT 1 FROM producto p
    WHERE p.categoria_id = c.id
);
```

Es decir: un script puede ser sintácticamente correcto, tener el WHERE bien
resuelto, y aun así ser incorrecto para el sistema sobre el que se ejecuta.

---

## Conclusión

Ninguno de los dos scripts produce un error de sintaxis ni una excepción en
tiempo de ejecución. Ambos se ejecutan sin que el motor se queje. Es el mismo
patrón que aparece en los cuatro casos reales documentados en la consigna: el
código generado fue válido y la intención razonable, y lo que falló fue el paso
humano de leer el efecto real antes de ejecutar.