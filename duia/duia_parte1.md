# Declaración de Uso de IA (DUIA) — Parte 1

**Ejercicio:** Integridad versionada — restricciones de integridad para reglas de
negocio del proyecto integrador.

**Fecha:** 26/08/2026

---

## Herramienta

OpenCode v1.18.23, modelo **Big Pickle** (proveedor OpenCode Zen, plan gratuito).

Se usó además Kiro para generar los steering docs del repositorio
(`.kiro/steering/database.md`), como contexto previo del esquema. Kiro no
participó en la generación de las restricciones.

---

## Spec o prompt utilizado

La spec se escribió antes de abrir OpenCode y se commiteó en el repositorio como
`spec_restricciones.md`. El prompt dado a OpenCode, en modo Plan, fue:

> Leé la spec en spec_restricciones.md y proponé un plan para implementar las dos
> reglas de negocio que describe. El resultado debe ser un archivo
> sql/restricciones.sql para PostgreSQL 17. No escribas nada todavía, solo
> describí el plan.

Tras revisar el plan propuesto, se le pidieron tres correcciones antes de
autorizar la escritura:

> El plan está bien, con tres ajustes:
>
> 1. Usá BEFORE INSERT OR UPDATE a secas, sin la cláusula UPDATE OF columnas.
> Prefiero el comportamiento más simple aunque se dispare de más.
>
> 2. Los casos de prueba NO van en restricciones.sql. Generá un segundo archivo
> sql/pruebas_restricciones.sql con los 4 casos de la spec, envueltos en
> BEGIN ... ROLLBACK, para poder correrlos sin modificar datos.
> restricciones.sql debe contener solo las funciones y los triggers.
>
> 3. Todos los comentarios en castellano, explicando qué hace cada bloque y por qué.
>
> Sí a dos triggers separados. No hace falta documentar el DISABLE TRIGGER.
>
> Ahora sí, escribí los dos archivos.

---

## Qué generó

Dos archivos:

**`sql/restricciones.sql`** (86 líneas): dos funciones PL/pgSQL y dos triggers.

- `fn_verificar_producto_activo()` — consulta `producto.activo` a partir de
  `NEW.id_producto` y lanza `RAISE EXCEPTION` si el producto está dado de baja.
- `trg_verificar_producto_activo` — `BEFORE INSERT OR UPDATE ... FOR EACH ROW`
  sobre `detalle_pedido`.
- `fn_verificar_stock_suficiente()` — consulta `producto.stock` y lanza
  `RAISE EXCEPTION` si `NEW.cantidad` lo supera, informando cantidad pedida y
  stock disponible.
- `trg_verificar_stock_suficiente` — mismo timing y nivel que el anterior.
- Cada `CREATE TRIGGER` va precedido de un `DROP TRIGGER IF EXISTS` para que el
  archivo sea reejecutable.

**`sql/pruebas_restricciones.sql`** (71 líneas): los cuatro casos de la spec,
cada uno en su propio bloque `BEGIN ... ROLLBACK`.

---

## Qué se aceptó

Se aceptó tal cual la estructura generada: dos funciones separadas, un trigger
por regla, timing `BEFORE`, nivel `FOR EACH ROW`, y el patrón
`DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`.

Se aceptó también la decisión de resolver ambas reglas con triggers y no con
`CHECK`: una restricción `CHECK` solo puede evaluar columnas de la propia fila, y
estas dos reglas necesitan leer datos de la tabla `producto` desde una operación
sobre `detalle_pedido`.

---

## Qué se modificó o descartó, y por qué

**1. Se descartó la cláusula `UPDATE OF id_producto, cantidad`.**
El plan original proponía disparar los triggers solo cuando esas columnas
aparecieran en el `SET` de un UPDATE. Se pidió `BEFORE INSERT OR UPDATE` a secas.
Motivo: `UPDATE OF columna` se dispara cuando la columna figura en el SET aunque
se le asigne el mismo valor, lo que hace el comportamiento menos predecible. Se
prefirió que el trigger se dispare de más antes que tener una condición
adicional difícil de justificar.

**2. Se separaron los casos de prueba en un archivo aparte.**
El plan ofrecía incluirlos dentro de `restricciones.sql`. Se rechazó: ese archivo
debe contener únicamente estructura. Si los INSERT de prueba estuvieran adentro,
cada aplicación del archivo modificaría datos.

**3. Se descartó documentar `ALTER TABLE ... DISABLE TRIGGER`.**
OpenCode lo ofreció como nota para cargas masivas. Se descartó por no formar
parte del alcance de esta consigna.

**4. Se decidió que los triggers solo validen, sin descontar stock.**
Esta decisión se tomó al escribir la spec, antes de consultar a la IA. Se evaluó
la alternativa de que el trigger actualizara `producto.stock` automáticamente y
se descartó: obligaría a definir además qué ocurre al eliminar una línea de
detalle, qué ocurre al modificar la cantidad, y cómo evitar el doble descuento si
la aplicación también actualiza el stock. El descuento sigue siendo
responsabilidad de la aplicación.

---

## Verificación realizada

Se aplicó el protocolo de seguridad completo: respaldo previo con `pg_dump`
(`respaldos/bd2_trabajo_20260826_pre_triggers.dump`), aplicación sobre la copia
`bd2_trabajo`, y ejecución de los cuatro casos, cada uno dentro de
`BEGIN ... ROLLBACK`.

Aplicación de las restricciones:

```
CREATE FUNCTION
DROP TRIGGER
CREATE TRIGGER
CREATE FUNCTION
DROP TRIGGER
CREATE TRIGGER
```

Ejecución de los casos de prueba:

```
BEGIN
psql:sql/pruebas_restricciones.sql:24: ERROR:  No se puede vender el producto con id 10: está dado de baja (activo = FALSE)
CONTEXT:  función PL/pgSQL fn_verificar_producto_activo() en la línea 10 en RAISE
ROLLBACK
BEGIN
INSERT 0 1
ROLLBACK
BEGIN
psql:sql/pruebas_restricciones.sql:54: ERROR:  Stock insuficiente para el producto con id 4: se solicitan 50 unidades, pero hay 1 en stock
CONTEXT:  función PL/pgSQL fn_verificar_stock_suficiente() en la línea 10 en RAISE
ROLLBACK
BEGIN
INSERT 0 1
ROLLBACK
```

| # | Caso | Esperado | Resultado |
|---|---|---|---|
| 1 | 'Helado 1L' (`activo = FALSE`) | Rechazado por Regla 1 | Rechazado ✓ |
| 2 | 'Agua mineral 2L', cantidad 2 (stock 40) | Aceptado | `INSERT 0 1` ✓ |
| 3 | 'Gaseosa cola 2.25L', cantidad 50 (stock 1) | Rechazado por Regla 2 | Rechazado ✓ |
| 4 | 'Medialunas x6', cantidad 3 (stock 3) | Aceptado (límite exacto) | `INSERT 0 1` ✓ |

Los cuatro casos coincidieron con lo esperado.

---

## Limitaciones detectadas al revisar el código generado

**1. Los triggers no protegen frente a concurrencia.**
`fn_verificar_stock_suficiente()` lee el stock con un `SELECT` simple, sin tomar
bloqueo. Dos sesiones concurrentes pueden leer el mismo valor de stock, pasar
ambas la validación y confirmar, quedando el stock vendido por encima del
disponible. Resolverlo requeriría `SELECT ... FOR UPDATE`, que obliga a la
segunda sesión a esperar. Esta limitación se reproduce y verifica en la Parte 2
de este trabajo práctico.

**2. Producto inexistente no es cubierto por los triggers.**
La comparación `IF v_activo = FALSE` no se cumple cuando `v_activo` es NULL, que
es lo que ocurriría si el `id_producto` no existiera. En ese caso el trigger deja
pasar la fila; el rechazo lo produce después la clave foránea
`detalle_pedido.id_producto → producto`. Lo mismo aplica a
`IF NEW.cantidad > v_stock` en la Regla 2.

**3. Validación por línea, no por stock acumulado.**
Cada línea de detalle se valida por separado contra el stock. Varias líneas en
pedidos distintos pueden, sumadas, superar el stock total sin que ninguna sea
rechazada individualmente.

Ninguna de las tres limitaciones invalida las restricciones para el alcance
definido en la spec, pero las tres se documentan porque surgieron de la lectura
línea por línea del código generado.