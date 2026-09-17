# Declaración de Uso de IA (DUIA) — Parte 5

**Ejercicio:** TP5, Parte A — plan de indexado

## Estado

La Parte A se encuentra en preparación. Primero se redactaron las specs de
Kiro y todavía no se acepta ningún índice sin medirlo en PostgreSQL.

## Specs preparadas

- `food-store/specs/spec_indice_productos_categoria_precio.md`
- `food-store/specs/spec_indice_pedidos_cliente_fecha.md`
- `food-store/specs/spec_indice_detalle_producto_pedido.md`

Cada spec fija la consulta, la frecuencia esperada, las columnas relevantes,
la hipótesis del índice y el criterio de aceptación.

## Próximas interacciones documentadas

Se utilizará OpenCode para proponer el SQL de cada índice a partir de su spec.
La propuesta se leerá línea por línea y se verificará con:

```text
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
```

La decisión final será propia y se basará en el plan, el tiempo, los buffers y
el costo de escritura. También se registrará al menos una propuesta descartada
por redundancia o sobreindexación.