# Pasaje ER → relacional y normalización — Food Store

Documento de la Unidad 1 que justifica cómo el modelo entidad-relación se
transformó en las seis tablas de `food-store/schema.sql` y por qué cada tabla
está en tercera forma normal (3FN) y, además, en forma normal de Boyce-Codd
(FNBC).

Las reglas de negocio citadas (R1–R7) son las mismas que aparecen en los
comentarios de `schema.sql` y en `.kiro/steering/database.md`. La verificación
contra los datos está en `food-store/verificacion_normalizacion.sql` (solo
lectura) y sus resultados, en la sección 7.

---

## 1. Modelo entidad-relación

### 1.1 Reglas de negocio que condicionan el modelo

| Regla | Enunciado | Dónde impacta |
|---|---|---|
| R1 | Todo producto pertenece a exactamente una categoría; una categoría puede no tener productos | Participación de la relación *contiene* |
| R2 | Todo pedido pertenece a exactamente un cliente registrado | Participación de la relación *realiza* |
| R4 | El precio de una línea de pedido es el del momento de la venta, independiente del precio de lista actual | Atributo `precio_unitario` de la relación *incluye* |
| R5 | Precios y stock no negativos | `CHECK` sobre `precio`, `stock`, `precio_unitario` |
| R6 | El email identifica al cliente | `email` es clave candidata |
| R7 | Categorías y productos no se borran físicamente | Atributo `activo` (baja lógica) |

### 1.2 Entidades

| Entidad | Identificador | Claves candidatas alternativas | Atributos |
|---|---|---|---|
| CLIENTE | `id_cliente` | `email` (R6) | nombre, apellido, email, telefono (opcional) |
| CATEGORIA | `id_categoria` | `nombre` | nombre, activo |
| PRODUCTO | `id_producto` | — | nombre, descripcion (opcional), precio, stock, activo |
| PEDIDO | `id_pedido` | — | fecha, forma_pago |
| USUARIO | `id` | `mail` | nombre, apellido, mail, celular (opcional), contrasena, rol, eliminado |

`categoria`, `cliente`, `producto` y `usuario` agregan además `created_at` como
atributo de auditoría (en `pedido` ese papel lo cumple `fecha`). No es un
atributo del dominio; se menciona porque aparece en el esquema y no en el
diagrama.

### 1.3 Relaciones

| Relación | Entidades | Cardinalidad | Participación | Atributos propios |
|---|---|---|---|---|
| *realiza* | CLIENTE – PEDIDO | 1 : N | CLIENTE parcial (un cliente puede no haber comprado nunca); PEDIDO **total** (R2) | — |
| *contiene* | CATEGORIA – PRODUCTO | 1 : N | CATEGORIA parcial (R1: puede estar vacía); PRODUCTO **total** (R1) | — |
| *incluye* | PEDIDO – PRODUCTO | N : M | Ambas parciales (un producto puede no haberse vendido nunca; el esquema no obliga a que un pedido tenga líneas) | **cantidad**, **precio_unitario** |

USUARIO no participa en ninguna relación. Representa un actor de sistema
(login y reportes), distinto del actor de negocio CLIENTE; se agregó en el
TP5 por indicación de la cátedra (ver `food-store/specs/spec_usuario.md`).

El punto clave del modelo es que `cantidad` y `precio_unitario` **no son
atributos de PEDIDO ni de PRODUCTO, sino de la relación *incluye***: la
cantidad depende de qué producto y en qué pedido; el precio histórico también
(R4). Por eso terminan en `detalle_pedido`.

> El diagrama actualizado está en `docs/diagrama_er.mmd` (fuente Mermaid de
> `docs/Diagrama ER.png`). Incluye `usuario` y muestra la relación N:M ya
> resuelta como entidad `DETALLE_PEDIDO`, con las mismas participaciones que
> esta tabla.

---

## 2. Pasaje al modelo relacional

### 2.1 Reglas de transformación aplicadas

| Caso del ER | Regla de transformación | Resultado en el esquema |
|---|---|---|
| Entidad fuerte | Una tabla por entidad; el identificador pasa a ser PK | `cliente`, `categoria`, `producto`, `pedido`, `usuario` |
| Identificador | Clave sustituta `BIGINT GENERATED ALWAYS AS IDENTITY` | `id_<tabla>` (en `usuario`, `id`) |
| Clave candidata alternativa | Restricción `UNIQUE` + `NOT NULL` | `cliente.email`, `categoria.nombre`, `usuario.mail` |
| Relación 1:N | La PK del lado 1 viaja como FK al lado N | `pedido.id_cliente`, `producto.id_categoria` |
| Participación total del lado N | La FK es `NOT NULL` | `pedido.id_cliente` (R2), `producto.id_categoria` (R1) |
| Participación parcial del lado 1 | No se agrega nada: una fila del lado 1 sin filas que la referencien es válida | Categoría sin productos, cliente sin pedidos |
| Relación N:M | Tabla intermedia con una FK hacia cada entidad + los atributos de la relación | `detalle_pedido(id_pedido, id_producto, cantidad, precio_unitario)` |
| Dominio cerrado | Tipo `ENUM` | `forma_pago_enum`, `rol` |
| Atributo derivado | **No se almacena**; se calcula en la consulta | `subtotal = cantidad * precio_unitario` |
| Atributo opcional | Columna que admite `NULL` | `telefono`, `descripcion`, `celular` |

### 2.2 Decisión sobre la tabla intermedia `detalle_pedido`

La clave natural de la relación *incluye* es el par `(id_pedido, id_producto)`:
dentro de un pedido, cada producto aparece en una sola línea (si se compran más
unidades, sube `cantidad`). Hay dos formas de declararla:

1. PK compuesta `(id_pedido, id_producto)`.
2. **PK sustituta `id_detalle` + `UNIQUE (id_pedido, id_producto)`** ← elegida.

Se eligió la segunda porque la línea de detalle queda identificada por una sola
columna (más simple para referenciarla o actualizarla), igual que el resto de
las tablas del proyecto. El `UNIQUE` conserva la regla de negocio: el motor
sigue rechazando un producto repetido en el mismo pedido. Para la
normalización, las dos opciones son equivalentes, porque las formas normales se
evalúan contra **todas** las claves candidatas, no solo contra la PK (ver 4.2).

### 2.3 Políticas de borrado de las FK

| FK | `ON DELETE` | Motivo |
|---|---|---|
| `producto.id_categoria` → `categoria` | `RESTRICT` | Una categoría con productos no se borra: se da de baja lógica (R7) |
| `pedido.id_cliente` → `cliente` | `RESTRICT` | Protege el historial de pedidos |
| `detalle_pedido.id_pedido` → `pedido` | `CASCADE` | Una línea no tiene sentido sin su pedido (dependencia de existencia) |
| `detalle_pedido.id_producto` → `producto` | `RESTRICT` | Protege el historial de ventas: el producto se da de baja lógica (R7) |

### 2.4 Esquema relacional resultante

Notación: el primer atributo de cada tabla es la PK, `*` marca una clave
candidata alternativa (`UNIQUE`) y `→` una FK.

```
CATEGORIA      (id_categoria, nombre*, activo, created_at)
CLIENTE        (id_cliente, nombre, apellido, email*, telefono, created_at)
PRODUCTO       (id_producto, nombre, descripcion, precio, stock, activo,
                id_categoria → CATEGORIA, created_at)
PEDIDO         (id_pedido, fecha, forma_pago, id_cliente → CLIENTE)
DETALLE_PEDIDO (id_detalle, cantidad, precio_unitario,
                id_pedido → PEDIDO, id_producto → PRODUCTO)
                UNIQUE (id_pedido, id_producto)*
USUARIO        (id, nombre, apellido, mail*, celular, contrasena, rol,
                eliminado, created_at)
```

---

## 3. Dependencias funcionales

Una dependencia funcional (DF) `X → Y` significa que dos filas con el mismo
valor de `X` tienen necesariamente el mismo valor de `Y`. Las DF salen de las
**reglas del dominio**, no de mirar los datos: los datos pueden refutar una DF
(un contraejemplo alcanza), pero nunca demostrarla.

Para cada tabla se listan las DF no triviales y, para que el análisis sea
completo, las DF que **podrían parecer** válidas y **no lo son**.

### 3.1 `categoria`

- `id_categoria → nombre, activo, created_at`
- `nombre → id_categoria, activo, created_at` (nombre es único)
- Claves candidatas: `{id_categoria}`, `{nombre}`.

### 3.2 `cliente`

- `id_cliente → nombre, apellido, email, telefono, created_at`
- `email → id_cliente, nombre, apellido, telefono, created_at` (R6)
- Claves candidatas: `{id_cliente}`, `{email}`.
- **No son DF:**
  - `nombre, apellido ↛ id_cliente`: puede haber homónimos.
  - `telefono ↛ id_cliente`: dos clientes pueden compartir un teléfono fijo
    (por eso `telefono` no es `UNIQUE`).

### 3.3 `producto`

- `id_producto → nombre, descripcion, precio, stock, activo, id_categoria, created_at`
- Clave candidata: `{id_producto}`.
- **No son DF:**
  - `nombre ↛ id_producto`: el dominio no exige nombres únicos (dos
    presentaciones pueden llamarse igual), por eso `nombre` no es `UNIQUE`.
  - `id_categoria ↛` ningún otro atributo de `producto`. En la tabla no se
    guarda nada de la categoría excepto su id: el nombre de la categoría vive en
    `categoria`. Si se guardara acá, habría una DF transitiva (ver 4.3).

### 3.4 `pedido`

- `id_pedido → fecha, forma_pago, id_cliente`
- Clave candidata: `{id_pedido}`.
- **No son DF:**
  - `id_cliente ↛ forma_pago`: el cliente elige la forma de pago en cada pedido.
  - `fecha ↛ id_cliente`: dos clientes pueden comprar en el mismo instante.
  - Tampoco se guarda ningún dato del cliente (nombre, email) en `pedido`: se
    obtiene con un `JOIN` por `id_cliente`.

### 3.5 `detalle_pedido`

- `id_detalle → id_pedido, id_producto, cantidad, precio_unitario`
- `id_pedido, id_producto → id_detalle, cantidad, precio_unitario`
- Claves candidatas: `{id_detalle}`, `{id_pedido, id_producto}`.
- **No son DF (las más importantes de todo el análisis):**
  - `id_producto ↛ precio_unitario`: por R4 el precio se congela en el
    momento de la venta; el mismo producto vendido en dos pedidos distintos
    puede tener dos precios distintos. `precio_unitario` depende del **par**
    (qué producto, en qué pedido).
  - `id_producto ↛ cantidad` y `id_pedido ↛ cantidad`: la cantidad es de esa
    línea, no del pedido ni del producto.
  - `precio_unitario` **no es** `producto.precio`: el primero es histórico y el
    segundo, el precio de lista actual. Son datos distintos, no una copia.
- **DF que existiría si se almacenara `subtotal`:**
  `cantidad, precio_unitario → subtotal`. Es una DF entre atributos no clave;
  por eso `subtotal` no se guarda (ver 4.3).

### 3.6 `usuario`

- `id → nombre, apellido, mail, celular, contrasena, rol, eliminado, created_at`
- `mail → id, nombre, apellido, celular, contrasena, rol, eliminado, created_at`
- Claves candidatas: `{id}`, `{mail}`.
- **No son DF:** `rol ↛` nada (muchos usuarios comparten rol);
  `nombre, apellido ↛ id` (homónimos).

### 3.7 Resumen de determinantes

| Tabla | Determinantes de DF no triviales | ¿Todos son clave candidata? |
|---|---|---|
| `categoria` | `id_categoria`, `nombre` | Sí |
| `cliente` | `id_cliente`, `email` | Sí |
| `producto` | `id_producto` | Sí |
| `pedido` | `id_pedido` | Sí |
| `detalle_pedido` | `id_detalle`, `(id_pedido, id_producto)` | Sí |
| `usuario` | `id`, `mail` | Sí |

Esta tabla es la base de la conclusión de la sección 4.4.

---

## 4. Formas normales

Se analiza cada forma normal para todas las tablas.

### 4.1 Primera forma normal (1FN)

**Condición:** todos los atributos toman valores atómicos y no hay grupos
repetitivos.

| Tabla | Justificación |
|---|---|
| `cliente` | `nombre` y `apellido` están separados (se usan por separado para ordenar y buscar). Un solo `telefono`: el dominio no pide varios; si los pidiera, irían a una tabla `telefono_cliente`, no a una lista en una columna |
| `pedido` | `forma_pago` es un único valor del ENUM, no una lista |
| `pedido` / `detalle_pedido` | Los productos de un pedido **no** son columnas `producto1, producto2, …` ni un arreglo: cada producto comprado es una fila de `detalle_pedido`. Este es el grupo repetitivo que la tabla intermedia elimina |
| `categoria`, `producto`, `usuario` | Todos los atributos son escalares (`VARCHAR`, `NUMERIC`, `INTEGER`, `BOOLEAN`, `TIMESTAMPTZ`, ENUM) |

Todas las tablas tienen PK, así que no hay filas duplicadas. **Todas cumplen 1FN.**

### 4.2 Segunda forma normal (2FN)

**Condición:** está en 1FN y ningún atributo no primo depende de una **parte**
de una clave candidata (no hay dependencias parciales).

Un atributo es *primo* si forma parte de alguna clave candidata.

- En `categoria`, `cliente`, `producto`, `pedido` y `usuario` todas las claves
  candidatas son de **una sola columna**. Una clave simple no tiene "partes",
  así que no puede haber dependencia parcial: cumplen 2FN directamente.
- `detalle_pedido` es el único caso a analizar, porque tiene la clave
  candidata compuesta `{id_pedido, id_producto}`. Que la PK sea `id_detalle` no
  exime del análisis: 2FN se evalúa contra **todas** las claves candidatas.
  Si solo se mirara la PK sustituta, una dependencia parcial podría quedar
  "escondida" detrás de ella.

  Atributos no primos: `cantidad`, `precio_unitario` (`id_detalle` es primo
  porque es clave candidata).

  | Atributo | ¿Depende solo de `id_pedido`? | ¿Depende solo de `id_producto`? | Conclusión |
  |---|---|---|---|
  | `cantidad` | No: un pedido tiene varias líneas con cantidades distintas | No: el mismo producto se compra en cantidades distintas | Depende de la clave completa |
  | `precio_unitario` | No: un pedido tiene productos con precios distintos | **No, por R4**: el precio se congela en cada venta | Depende de la clave completa |

  El caso de `precio_unitario` es el que hay que defender: si el precio de la
  línea fuera siempre el de lista, existiría `id_producto → precio_unitario`,
  habría una dependencia parcial y el atributo sobraría (se leería de
  `producto.precio`). Como R4 exige conservar el precio histórico, esa DF no
  existe y el atributo está bien ubicado.

**Todas las tablas cumplen 2FN.**

### 4.3 Tercera forma normal (3FN)

**Condición:** está en 2FN y ningún atributo no primo depende
**transitivamente** de una clave candidata, es decir, a través de otro
atributo no primo (`clave → A → B`, con A no clave).

Casos donde podría aparecer una dependencia transitiva y cómo se evitó:

| Tabla | Dependencia transitiva que se evitó | Cómo |
|---|---|---|
| `detalle_pedido` | `id_detalle → (cantidad, precio_unitario) → subtotal` | `subtotal` **no se almacena**: se calcula como `cantidad * precio_unitario`. Guardarlo permitiría que quede inconsistente si se modifica `cantidad` sin recalcularlo |
| `producto` | `id_producto → id_categoria → nombre_categoria` | Solo se guarda `id_categoria`; el nombre se obtiene con `JOIN categoria` |
| `pedido` | `id_pedido → id_cliente → email / nombre del cliente` | Solo se guarda `id_cliente`; los datos del cliente están en `cliente` |
| `detalle_pedido` | `id_detalle → id_producto → nombre / precio de lista` | Solo se guarda `id_producto`; `precio_unitario` no es el precio de lista (ver 3.5) |

En `cliente`, `email` determina al resto de los atributos, pero no es una
dependencia transitiva: `email` es clave candidata (atributo primo), y 3FN solo
prohíbe las DF cuyo determinante es un atributo **no primo**. Lo mismo vale
para `categoria.nombre` y `usuario.mail`.

**Todas las tablas cumplen 3FN.**

### 4.4 Forma normal de Boyce-Codd (FNBC)

**Condición:** para toda DF no trivial `X → Y`, `X` es superclave.

La tabla 3.7 muestra que, en las seis tablas, todo determinante de una DF no
trivial es una clave candidata. **Todas las tablas cumplen FNBC**, que es más
estricta que 3FN.

FNBC y 3FN solo difieren cuando hay claves candidatas compuestas que se
solapan y un atributo no clave determina una parte de una clave. En
`detalle_pedido`, la única clave compuesta es `{id_pedido, id_producto}` y
ningún otro atributo determina a `id_pedido` ni a `id_producto`, así que ese
caso no se da.

---

## 5. Decisiones que parecen violaciones y no lo son

| Decisión | Por qué parece un problema | Por qué no lo es |
|---|---|---|
| `detalle_pedido.precio_unitario` | "El precio ya está en `producto`, está duplicado" | Es otro dato: el precio al momento de la venta (R4). Si se leyera de `producto.precio`, un aumento de precio cambiaría retroactivamente el total de pedidos viejos |
| No guardar `subtotal` | "Hay que calcularlo en cada consulta" | Es un atributo derivado. Guardarlo agrega una DF entre no primos (rompe 3FN) y un riesgo de inconsistencia. Calcularlo cuesta una multiplicación por fila |
| `producto.stock` almacenado | "El stock se podría derivar de las ventas" | No hay una tabla de movimientos (compras a proveedores, ajustes, mermas) de la que derivarlo; con solo las ventas no alcanza para reconstruirlo. Es un dato de estado propio del producto: depende solo de `id_producto` |
| `cliente` y `usuario` con columnas parecidas (nombre, apellido, mail) | "Hay datos repetidos" | Son entidades distintas (actor de negocio vs. actor de sistema), sin FK entre sí. No existe una DF que vincule una fila de `cliente` con una de `usuario`: una persona puede ser cliente sin usuario, o usuario sin ser cliente. Redundancia sería que el **mismo hecho** estuviera en dos lugares, y acá no es el mismo hecho |
| `activo` / `eliminado` (baja lógica) | "Es un estado, no un dato" | Es un atributo de la entidad que depende solo de su clave. No afecta la normalización (R7) |
| `created_at` | "No figura en el ER" | Atributo de auditoría que depende solo de la clave. Tampoco afecta la normalización |
| PK sustituta `id_detalle` en lugar de la PK compuesta | "Oculta la clave real" | La clave real sigue declarada con `UNIQUE`, y el análisis de 2FN se hizo contra ella (4.2) |

---

## 6. Contraejemplo: la tabla sin normalizar

Para mostrar qué evita el diseño, este sería el pedido guardado en una sola
tabla "plana", una fila por producto comprado:

```
PEDIDO_PLANO (id_pedido, fecha, forma_pago,
              id_cliente, nombre_cliente, apellido_cliente, email_cliente,
              id_producto, nombre_producto, precio_lista, stock,
              nombre_categoria,
              cantidad, precio_unitario, subtotal)
Clave: (id_pedido, id_producto)
```

| Paso | DF problemática en `PEDIDO_PLANO` | Qué se viola | Se resuelve con |
|---|---|---|---|
| 1 | `id_pedido → fecha, forma_pago, id_cliente` | 2FN: dependencia parcial (parte de la clave) | Tabla `pedido` |
| 2 | `id_producto → nombre_producto, precio_lista, stock, …` | 2FN: dependencia parcial | Tabla `producto` |
| 3 | `id_cliente → nombre_cliente, email_cliente, …` (vía `id_pedido`) | 3FN: transitiva | Tabla `cliente` |
| 4 | `nombre_categoria` (vía `id_producto`) | 3FN: transitiva | Tabla `categoria` |
| 5 | `cantidad, precio_unitario → subtotal` | 3FN: transitiva | Se elimina `subtotal` |

Lo que queda con la clave `(id_pedido, id_producto)` es exactamente
`detalle_pedido(cantidad, precio_unitario)`.

Anomalías que tendría `PEDIDO_PLANO`:

- **Actualización:** si un cliente cambia su email, hay que modificarlo en
  todas las filas de todos sus pedidos; si se olvida una, la base queda
  inconsistente. Lo mismo con el nombre de una categoría o el stock de un
  producto.
- **Inserción:** no se puede cargar un producto nuevo, una categoría vacía ni
  un cliente registrado que todavía no compró, porque no hay pedido que les dé
  una clave. Esto contradice R1 (la categoría puede estar vacía).
- **Borrado:** si se borra el único pedido de un cliente, se pierden sus datos
  de contacto; si se borra la única venta de un producto, se pierde el
  producto.

En el esquema normalizado cada hecho está en un solo lugar: el email en
`cliente`, el nombre de la categoría en `categoria`, el stock en `producto`.

---

## 7. Verificación en el motor

Script: `food-store/verificacion_normalizacion.sql`. Es de solo lectura: corre
dentro de `BEGIN TRANSACTION READ ONLY … ROLLBACK`, así que el motor rechaza
cualquier escritura.

```bash
psql -U postgres -d bd2_tp3 -X -f food-store/verificacion_normalizacion.sql
```

Se ejecutó el 23/09/2026 sobre `bd2_tp3` y sobre `bd2_trabajo`. Las dos bases
dieron resultados idénticos: hoy `bd2_trabajo` es una copia de `bd2_tp3`. La
base contiene las semillas de `data.sql` más la carga masiva de la Unidad 2:
50.011 productos (11 de las semillas) y 499.263 líneas de detalle.

| # | Qué comprueba | Resultado | Lectura |
|---|---|---|---|
| V1 | Claves y FK declaradas en el catálogo | 14 restricciones: una PK por tabla; `UNIQUE (nombre)` en `categoria`, `UNIQUE (email)` en `cliente`, `UNIQUE (mail)` en `usuario`, `UNIQUE (id_pedido, id_producto)` en `detalle_pedido`; las cuatro FK con las políticas de 2.3 | Todas las claves candidatas de la sección 3 las hace cumplir el motor: las DF `clave → resto` están garantizadas por el esquema, no por los datos |
| V2 | Columna `subtotal` en `detalle_pedido` | 0 filas | `subtotal` no se almacena (3FN, 4.3) |
| V3 | Productos vendidos con más de un `precio_unitario` | **2** de 50.008 productos vendidos | **Refuta `id_producto → precio_unitario`** (ver V8) |
| V4 | Líneas con `precio_unitario` distinto del precio de lista vigente | **2** de 499.263 | `precio_unitario` no es una copia de `producto.precio` (R4) |
| V5 | Pares `(id_pedido, id_producto)` repetidos | 0 | Consistente con la clave candidata compuesta |
| V6 | Cliente con más de una `forma_pago` | **19.936** | Refuta `id_cliente → forma_pago` |
| V6 | Fecha de pedido compartida por clientes distintos | **22** | Refuta `fecha → id_cliente` |
| V6 | Homónimos en `cliente` / nombres repetidos en `producto` | 0 / 0 | No prueba nada: la carga generó nombres únicos. Que `nombre` no sea clave se sostiene por el dominio (3.2, 3.3) |
| V7 | Duplicados en `cliente.email` y `categoria.nombre` | 0 / 0 | Consistente con las claves candidatas alternativas |

### V8: el contraejemplo de `id_producto → precio_unitario`

Los dos productos de V3 son de las semillas. En el pedido del 01/08/2026 de
`data.sql` se cargaron a propósito precios históricos menores al de lista.
Después, la carga masiva vendió esos mismos productos a precio de lista:

| Producto | Precio de lista vigente | Pedido del 01/08/2026 | Resto de sus ventas |
|---|---|---|---|
| Pan de campo 1kg | 2500.00 | **2200.00** | 13 ventas a 2500.00 |
| Leche entera 1L | 1800.00 | **1650.00** | 7 ventas a 1800.00 |

El mismo `id_producto` aparece con dos valores distintos de `precio_unitario`,
así que `id_producto → precio_unitario` **no es una DF**. Es el argumento de
2FN en 4.2 verificado con datos: `precio_unitario` depende del par
`(id_pedido, id_producto)` y no solo del producto. Por lo tanto no hay
dependencia parcial, y guardar el precio en la línea no es redundante.

Queda una aclaración para la lectura del resto de los resultados. Los valores
en 0 de V6 **no demuestran** que una DF exista: los datos solo pueden refutar
una DF, nunca probarla. Por ejemplo, que hoy no haya homónimos no hace que
`nombre, apellido` sea una clave. Por eso las DF de la sección 3 se derivan de
las reglas del dominio, y la verificación en el motor se usa para confirmar
las que **no** existen y para comprobar que las claves están declaradas.
