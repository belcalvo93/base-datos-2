# Declaración de Uso de IA (DUIA) — Parte 5

**Ejercicio:** TP5 (pendiente)

---

## Decisiones de diseño

### Decisión: agregar tabla `usuario` para el criterio de seguridad de la Parte B

**Contexto:** la consigna del TP5 (punto 4.2, Parte B) pide una vista
que oculte la columna `contraseña` de una tabla de login. El esquema
propio de Food Store no tiene ese caso de uso: `cliente` no maneja
autenticación y no tiene columna `contrasena` ni `rol`.

**Consulta a la cátedra:** el profesor (Sergio Neira) confirmó, ante
la misma consulta de otro grupo con el mismo problema de esquema, que
el criterio a seguir es agregar una tabla `usuario` separada de
`cliente`, con columnas `contrasena` (hasheada) y `rol` (tipo ENUM),
en vez de adaptar el criterio de seguridad a otra columna existente.
Confirmado que aplica el mismo criterio a todas las comisiones.

**Decisión tomada:** se agrega la tabla `usuario` (nueva, separada de
`cliente`) al esquema, con el tipo `rol` como ENUM. Esto se aparta de
la restricción general del punto 3 de la consigna ("no se debe
modificar el modelo de datos"), pero se hace por indicación directa
y explícita de la cátedra para este punto puntual.

Se agrega `vista_usuario_reportes` (usuario sin la columna
`contrasena`) como la vista que cumple el criterio de seguridad del
punto 4 de la Parte B. Las 4 vistas ya construidas sobre `cliente`
(`vista_cliente_completo`, `vista_pedidos_cliente`,
`vista_productos_vigentes`, `vista_detalle_pedido_producto`) se
mantienen sin cambios — no se reemplaza ninguna, `usuario` es una
pieza adicional.